# -*- coding: utf-8 -*-
"""
CARGA DO SIENGE MAIS RAPIDA (substitui o InserirDados\\AtualizacaoDiaria\\Atualizacao.py)

Usa as MESMAS funcoes dos seus scripts (importadas da pasta AtualizacaoDiaria,
sem alterar nada nelas): mesma API, mesmos periodos, mesmo tratamento das
colunas, mesmo schema. O resultado nas tabelas do raw e o mesmo.
So muda a ORGANIZACAO do trabalho:

  1. As 6 cargas rodam AO MESMO TEMPO (antes: uma depois da outra).
     Clientes, Unidades, Vendas, A Receber, Recebidas Historico e
     Recebidas Atualizavel.

  2. Recebidas (historico e atualizavel) e A Receber: as chamadas da API
     vao saindo sem parar. Antes o script pedia 5 periodos, esperava o
     MAIS LENTO dos 5 terminar e depois enviava um por um ao BigQuery
     (a API ficava parada nesse tempo). Agora, assim que um periodo chega,
     ele vai para o BigQuery em segundo plano enquanto os outros continuam
     baixando.
     As 3 cargas usam a mesma API (bulk-data/income); o total de chamadas
     simultaneas e LIMITADO (padrao 5, o mesmo maximo de hoje), para nao
     estourar o limite do Sienge.

  3. Seguranca: a carga vai para uma tabela de apoio (<tabela>__carga) e
     so no final, se TUDO deu certo e a contagem de linhas bate, substitui
     a tabela do raw de uma vez. Se der erro no meio, a tabela do raw
     continua com a carga anterior inteira (antes ficava pela metade e os
     SQLs rodavam em cima de dado incompleto).

  4. Clientes, Vendas e Unidades: as paginas da API (200 por pagina) sao
     pedidas 2 de cada vez em vez de 1 (as mesmas paginas, na mesma ordem).

Uso:
    python sienge_rapido.py                    -> tudo
    python sienge_rapido.py --so recebidas_historico a_receber
    python sienge_rapido.py --limite-api 5     -> chamadas simultaneas (bulk)
    python sienge_rapido.py --pasta "C:\\...\\InserirDados\\AtualizacaoDiaria"
"""

import argparse
import asyncio
import contextvars
import importlib
import os
import sys
import threading
import time
import traceback
from datetime import datetime
from pathlib import Path

PASTA = Path(__file__).resolve().parent

ETAPAS_ORDEM = [
    "clientes", "unidades", "vendas",
    "a_receber", "recebidas_historico", "recebidas_atualizavel",
]
NOMES = {
    "clientes": "Clientes",
    "unidades": "Unidades",
    "vendas": "Vendas",
    "a_receber": "A Receber",
    "recebidas_historico": "Recebidas Historico",
    "recebidas_atualizavel": "Recebidas Atualizavel",
}

# paginas simultaneas nas APIs paginadas (clientes/vendas/unidades).
# Os seus scripts ja abrem 2 conexoes (TCPConnector limit=2).
PAGINAS_SIMULTANEAS = 2
# envios simultaneos ao BigQuery por carga
CARGAS_BQ_SIMULTANEAS = 4


# ====================================================================
# LOG: cada linha com o nome da etapa (as etapas rodam juntas)
# ====================================================================
ETAPA_ATUAL = contextvars.ContextVar("etapa", default="")


class SaidaComEtapa:
    def __init__(self, original):
        self.original = original
        self.trava = threading.Lock()
        self.pendente = {}

    def write(self, texto):
        etapa = ETAPA_ATUAL.get()
        with self.trava:
            buf = self.pendente.get(etapa, "") + texto
            *linhas, resto = buf.split("\n")
            self.pendente[etapa] = resto
            for ln in linhas:
                self.original.write((f"[{etapa}] " if etapa else "") + ln + "\n")
            self.original.flush()
        return len(texto)

    def flush(self):
        self.original.flush()

    def __getattr__(self, nome):
        return getattr(self.original, nome)


def log(msg):
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} - {msg}", flush=True)


def fmt_tempo(seg):
    return f"{int(seg // 60)} min {int(seg % 60)} s"


# ====================================================================
# achar a pasta dos scripts do Sienge
# ====================================================================
def achar_pasta_scripts(informada=None):
    if informada:
        p = Path(informada)
        if (p / "CarregarHistorico.py").exists():
            return p
        raise SystemExit(f"Nao achei CarregarHistorico.py em {p}")
    for base in [PASTA, *PASTA.parents]:
        for c in (base / "InserirDados" / "AtualizacaoDiaria",
                  base / "BigQuery_Financeiro" / "InserirDados" / "AtualizacaoDiaria",
                  base / "Bases_API" / "BigQuery_Financeiro" / "InserirDados" / "AtualizacaoDiaria"):
            try:
                if (c / "CarregarHistorico.py").exists():
                    return c
            except OSError:
                pass
    raise SystemExit(
        "Nao achei a pasta InserirDados\\AtualizacaoDiaria (com CarregarHistorico.py). "
        "Use --pasta para informar o caminho.")


# ====================================================================
# 1. cargas em PERIODOS (bulk-data/income): historico, atualizavel, a receber
# ====================================================================
class CargaPeriodos:
    """Liga as funcoes do script original a um fluxo continuo.
    cfg:
      tabela_attr   nome da variavel global com a tabela de destino
      bq            cliente BigQuery do modulo
      preparar      funcao(df, schema) ou None (A Receber ja vem pronto)
      carregar      funcao(df, schema, periodo) sincrona (envia ao BigQuery)
      contar        funcao(tentativas, espera, esperado) -> linhas
    """

    def __init__(self, nome, mod, cfg, conector_extra):
        self.nome, self.mod, self.cfg = nome, mod, cfg
        self.conector_extra = conector_extra

    async def rodar(self, planejar, criar_vazia, limite_bq, limite_api):
        mod, cfg = self.mod, self.cfg
        final = getattr(mod, cfg["tabela_attr"])
        apoio = final + "__carga"
        inicio = time.time()

        # planejamento (le a tabela atual, como o script original)
        periodos, schema_esperado = planejar()
        if not periodos:
            raise RuntimeError("Nenhum periodo foi criado.")
        log(f"{len(periodos)} periodos planejados")

        # a partir daqui o script grava na tabela de apoio
        setattr(mod, cfg["tabela_attr"], apoio)
        try:
            schema_final = criar_vazia(apoio, schema_esperado)

            import aiohttp
            timeout = aiohttp.ClientTimeout(total=None, connect=120,
                                            sock_connect=120, sock_read=1800)
            connector = aiohttp.TCPConnector(limit=limite_api,
                                             limit_per_host=limite_api,
                                             ttl_dns_cache=300,
                                             enable_cleanup_closed=True,
                                             **self.conector_extra)
            fila = asyncio.Queue()
            for p in periodos:
                fila.put_nowait(p)
            sem_bq = asyncio.Semaphore(limite_bq)
            estado = {"linhas": 0, "feitos": 0}

            async def trabalhador(session):
                while True:
                    try:
                        periodo = fila.get_nowait()
                    except asyncio.QueueEmpty:
                        return
                    res = await mod.processar_periodo(session=session, periodo=periodo)
                    df = res["df"]
                    if not df.empty:
                        if cfg["preparar"] is not None:
                            df = await asyncio.to_thread(cfg["preparar"], df, schema_final)
                        async with sem_bq:
                            n = await asyncio.to_thread(cfg["carregar"], df, schema_final, res)
                        estado["linhas"] += n
                    estado["feitos"] += 1
                    if estado["feitos"] % 10 == 0 or estado["feitos"] == len(periodos):
                        log(f"progresso: {estado['feitos']}/{len(periodos)} periodos | "
                            f"{estado['linhas']:,} linhas | {fmt_tempo(time.time() - inicio)}")
                    del df, res

            # mais trabalhadores que chamadas simultaneas: enquanto um envia
            # ao BigQuery, outro ja esta baixando (o limite da API e o SEM_API)
            n_trab = max(limite_api, 1) + limite_bq
            async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
                tarefas = [asyncio.create_task(trabalhador(session)) for _ in range(n_trab)]
                try:
                    await asyncio.gather(*tarefas)
                except BaseException:
                    for t in tarefas:
                        t.cancel()
                    await asyncio.gather(*tarefas, return_exceptions=True)
                    raise

            total = estado["linhas"]
            linhas_bq = cfg["contar"](10, 3, total)
            log(f"linhas Python: {total:,} | linhas BigQuery (apoio): {linhas_bq:,}")
            if linhas_bq != total:
                raise RuntimeError("Quantidade no BigQuery diferente da carregada pelo Python.")
            if linhas_bq == 0:
                raise RuntimeError("A carga terminou sem registros.")
        except BaseException:
            setattr(mod, cfg["tabela_attr"], final)
            log(f"ERRO: a tabela {final} NAO foi alterada (continua com a carga anterior). "
                f"Dados parciais ficaram em {apoio}.")
            raise

        # troca: apoio -> final de uma vez (copia substituindo)
        setattr(mod, cfg["tabela_attr"], final)
        from google.cloud import bigquery
        bq = cfg["bq"]
        job = bq.copy_table(apoio, final, job_config=bigquery.CopyJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE))
        job.result(timeout=1800)
        linhas_final = int(bq.get_table(final).num_rows or 0)
        if linhas_final != total:
            raise RuntimeError(f"Depois da troca {final} tem {linhas_final:,} linhas "
                               f"(esperado {total:,}).")
        bq.delete_table(apoio, not_found_ok=True)
        log(f"OK {final}: {linhas_final:,} linhas | {fmt_tempo(time.time() - inicio)}")
        return linhas_final


def _criar_vazia_bignumeric(mod, recriar, validar):
    """Cria a tabela de apoio vazia com as funcoes do proprio script
    (recriar exclui e cria; a de apoio precisa existir antes)."""
    def criar(apoio, schema):
        from google.cloud import bigquery
        mod.BQ_CLIENT.delete_table(apoio, not_found_ok=True)
        mod.BQ_CLIENT.create_table(bigquery.Table(apoio, schema=schema))
        recriar(novo_schema=schema)          # mesma criacao do script original
        return validar(schema_esperado=schema)
    return criar


async def carga_historico(H, limite_bq, limite_api):
    def planejar():
        schema_original = H.obter_schema_original()
        schema_big = H.converter_schema_para_bignumeric(schema_original)
        periodos = H.criar_periodos_historicos_ponderados(
            subdominios=H.SUBDOMINIOS,
            data_inicial=H.DATA_INICIAL_HISTORICO,
            data_final=H.DATA_FINAL_HISTORICO)
        return periodos, schema_big

    cfg = dict(tabela_attr="TABELA_HISTORICO", bq=H.BQ_CLIENT,
               preparar=lambda df, s: H.preparar_para_schema_bigquery(df=df, schema=s),
               carregar=H.carregar_dataframe_sync,
               contar=lambda t, e, q: H.contar_linhas_historico(
                   tentativas=t, espera_segundos=e, quantidade_esperada=q))
    c = CargaPeriodos("recebidas_historico", H, cfg, {})
    return await c.rodar(planejar,
                         _criar_vazia_bignumeric(H, H.recriar_tabela_historico,
                                                 H.validar_tabela_recriada),
                         limite_bq, limite_api)


async def carga_atualizavel(A, limite_bq, limite_api):
    def planejar():
        if A.DATA_INICIAL_ATUALIZAVEL > A.DATA_FINAL_ATUALIZAVEL:
            raise RuntimeError("A data inicial do atualizavel e posterior a data atual.")
        schema_original = A.obter_schema_original()
        schema_big = A.converter_schema_para_bignumeric(schema_original)
        periodos = A.criar_periodos_atualizaveis(
            subdominios=A.SUBDOMINIOS,
            data_inicial=A.DATA_INICIAL_ATUALIZAVEL,
            data_final=A.DATA_FINAL_ATUALIZAVEL)
        return periodos, schema_big

    cfg = dict(tabela_attr="TABELA_ATUALIZAVEL", bq=A.BQ_CLIENT,
               preparar=lambda df, s: A.preparar_para_schema_bigquery(df=df, schema=s),
               carregar=A.carregar_dataframe_sync,
               contar=lambda t, e, q: A.contar_linhas_atualizavel(
                   tentativas=t, espera_segundos=e, quantidade_esperada=q))
    c = CargaPeriodos("recebidas_atualizavel", A, cfg, {})
    return await c.rodar(planejar,
                         _criar_vazia_bignumeric(A, A.recriar_tabela_atualizavel,
                                                 A.validar_tabela_recriada),
                         limite_bq, limite_api)


async def carga_a_receber(R, limite_bq, limite_api):
    def planejar():
        R.verificar_dataset()
        periodos, origem = R.montar_planejamento()   # le a tabela atual
        R.exibir_planejamento(periodos=periodos, origem=origem)
        return periodos, None

    def criar(apoio, _schema):
        R.recriar_tabela_final()          # (TABELA_BIGQUERY ja aponta p/ apoio)
        R.validar_tabela_recriada()
        return None

    cfg = dict(tabela_attr="TABELA_BIGQUERY", bq=R.client_bq,
               preparar=None,                                   # ja vem pronto
               carregar=lambda df, _s, periodo: R.carregar_dataframe_sync(df, periodo),
               contar=lambda t, e, q: R.contar_linhas_tabela(
                   tentativas=t, espera_segundos=e, quantidade_esperada=q))
    c = CargaPeriodos("a_receber", R, cfg, {"force_close": True})
    return await c.rodar(planejar, criar, limite_bq, limite_api)


# ====================================================================
# 2. APIs paginadas: as mesmas paginas, 2 de cada vez, na mesma ordem
# ====================================================================
async def _paginas_em_ordem(buscar_pagina, total, limite, simultaneas):
    """buscar_pagina(offset) -> lista. Devolve as paginas 2..n em ordem,
    parando na primeira vazia (igual ao laco original)."""
    offsets = list(range(limite, total, limite))
    sem = asyncio.Semaphore(simultaneas)

    async def uma(off):
        async with sem:
            return await buscar_pagina(off)

    tarefas = [asyncio.create_task(uma(o)) for o in offsets]
    try:
        paginas = await asyncio.gather(*tarefas)
    except BaseException:
        for t in tarefas:
            t.cancel()
        raise
    saida = []
    for pg in paginas:
        if not pg:
            break
        saida.append(pg)
    return saida


def instalar_paginacao_clientes(C):
    original = C.buscar_clientes

    async def buscar_clientes(session, subdominio):
        url = f"https://api.sienge.com.br/{subdominio}/public/api/v1/customers"
        headers = {"Authorization": C.obter_credenciais(subdominio),
                   "Accept-Encoding": "identity", "Connection": "close"}

        async def pagina(off):
            data = await C.fazer_requisicao(session=session, url=url, headers=headers,
                                            params={"limit": C.LIMIT, "offset": off},
                                            subdominio=subdominio)
            if isinstance(data, dict) and "results" in data:
                return data.get("results", []), (data.get("resultSetMetadata") or {}).get("count")
            if isinstance(data, list):
                return data, None
            raise ValueError("Estrutura de dados inesperada na API customers.")

        primeira, total = await pagina(0)
        if total is None or not primeira:
            return await original(session, subdominio)   # comportamento original
        todas = [primeira] + await _paginas_em_ordem(
            lambda o: _so_resultados(pagina, o),
            total, C.LIMIT, PAGINAS_SIMULTANEAS)
        all_data = []
        for results in todas:
            for cliente in results:
                cliente["subdominio"] = subdominio
            all_data.extend(results)
        C.log_status(f"Total extraido do subdominio {subdominio}: {len(all_data):,}")
        return all_data

    C.buscar_clientes = buscar_clientes


async def _so_resultados(pagina, off):
    res, _ = await pagina(off)
    return res


def instalar_paginacao_vendas(V):
    import pandas as pd

    async def processar_dados(session, subdominio):
        base_url = f"https://api.sienge.com.br/{subdominio}/public/api/v1/sales-contracts?"

        async def pagina(off):
            data = await V.fazer_requisicao(session, f"{base_url}limit={V.LIMIT}&offset={off}",
                                            subdominio)
            if "resultSetMetadata" not in data:
                raise RuntimeError("Estrutura da API nao contem resultSetMetadata.")
            return data.get("results", []), data["resultSetMetadata"].get("count", 0)

        primeira, total = await pagina(0)
        todas = [primeira] if primeira else []
        if primeira:
            todas += await _paginas_em_ordem(lambda o: _so_resultados(pagina, o),
                                             total, V.LIMIT, PAGINAS_SIMULTANEAS)
        all_data = []
        for results in todas:
            for r in results:
                r["subdominio"] = subdominio
                all_data.append(r)
        df = pd.DataFrame(all_data)
        V.log_status(f"Total extraido do subdominio {subdominio}: {len(df):,} registros")
        return df

    V.processar_dados = processar_dados


def instalar_paginacao_unidades(U):
    import pandas as pd
    from concurrent.futures import ThreadPoolExecutor

    def processar_dados(subdominio):
        base_url = f"https://api.sienge.com.br/{subdominio}/public/api/v1/units?"

        def pagina(off):
            data = U.fazer_requisicao(f"{base_url}limit={U.LIMIT}&offset={off}", subdominio)
            if "resultSetMetadata" not in data:
                raise RuntimeError("Dados retornaram sem resultSetMetadata.")
            return data.get("results", []), data["resultSetMetadata"].get("count", 0)

        primeira, total = pagina(0)
        todas = []
        if primeira:
            todas.append(primeira)
            offsets = list(range(U.LIMIT, total, U.LIMIT))
            ctx = contextvars.copy_context()
            with ThreadPoolExecutor(PAGINAS_SIMULTANEAS) as ex:
                for res, _ in ex.map(lambda o: ctx.copy().run(pagina, o), offsets):
                    if not res:
                        break
                    todas.append(res)
        all_data = []
        for results in todas:
            for item in results:
                item["subdominio"] = subdominio
                all_data.append(item)
        U.log_status(f"Dados coletados de {subdominio}: {len(all_data):,} registros.")
        return pd.DataFrame(all_data)

    U.processar_dados = processar_dados


# ====================================================================
# EXECUCAO
# ====================================================================
async def rodar_etapa(chave, coro_fn):
    ETAPA_ATUAL.set(NOMES[chave])
    inicio = time.time()
    log(f"INICIANDO {NOMES[chave]}")
    try:
        await coro_fn()
        log(f"ETAPA CONCLUIDA: {NOMES[chave]} | {fmt_tempo(time.time() - inicio)}")
        return chave, True, time.time() - inicio
    except Exception:
        log(f"ETAPA FALHOU: {NOMES[chave]} | {fmt_tempo(time.time() - inicio)}")
        traceback.print_exc()
        return chave, False, time.time() - inicio


async def principal(args):
    pasta = achar_pasta_scripts(args.pasta)
    sys.path.insert(0, str(pasta))
    os.chdir(pasta)
    log(f"Scripts do Sienge: {pasta}")

    etapas = args.so or ETAPAS_ORDEM
    mods = {}
    imp = {"clientes": "AtualizarClientes", "unidades": "AtualizarUnidades",
           "vendas": "AtualizarVendas", "a_receber": "AtualizarReceber",
           "recebidas_historico": "CarregarHistorico",
           "recebidas_atualizavel": "CarregarAtualizavel"}
    for e in etapas:
        mods[e] = importlib.import_module(imp[e])

    # limite UNICO de chamadas simultaneas para a API bulk-data (as 3 cargas)
    sem_bulk = asyncio.Semaphore(args.limite_api)
    for e in ("a_receber", "recebidas_historico", "recebidas_atualizavel"):
        if e in mods:
            mods[e].SEM_API = sem_bulk

    if "clientes" in mods:
        instalar_paginacao_clientes(mods["clientes"])
    if "vendas" in mods:
        instalar_paginacao_vendas(mods["vendas"])
    if "unidades" in mods:
        instalar_paginacao_unidades(mods["unidades"])

    fabricas = {
        "clientes": lambda: mods["clientes"].main(),
        "unidades": lambda: asyncio.to_thread(mods["unidades"].main),
        "vendas": lambda: mods["vendas"].main(),
        "a_receber": lambda: carga_a_receber(mods["a_receber"], CARGAS_BQ_SIMULTANEAS, args.limite_api),
        "recebidas_historico": lambda: carga_historico(mods["recebidas_historico"], CARGAS_BQ_SIMULTANEAS, args.limite_api),
        "recebidas_atualizavel": lambda: carga_atualizavel(mods["recebidas_atualizavel"], CARGAS_BQ_SIMULTANEAS, args.limite_api),
    }

    inicio = time.time()
    log("#" * 80)
    log(f"ATUALIZACAO DO SIENGE (etapas ao mesmo tempo, limite API bulk = {args.limite_api})")
    log("#" * 80)

    # cada etapa vira uma tarefa com o proprio contexto (nome no log)
    resultados = await asyncio.gather(*(rodar_etapa(e, fabricas[e]) for e in etapas))
    ETAPA_ATUAL.set("")
    log("#" * 80)
    log("RESUMO")
    for chave, ok, seg in resultados:
        log(f"  {NOMES[chave]:24s} {'OK' if ok else 'FALHOU':7s} {fmt_tempo(seg)}")
    log(f"Tempo total: {fmt_tempo(time.time() - inicio)}")
    log("#" * 80)
    return all(ok for _, ok, _ in resultados)


def main():
    ap = argparse.ArgumentParser(description="Carga do Sienge (rapida)")
    ap.add_argument("--so", nargs="+", choices=ETAPAS_ORDEM)
    ap.add_argument("--limite-api", type=int, default=5,
                    help="chamadas simultaneas na API bulk-data (padrao 5)")
    ap.add_argument("--pasta", help="pasta InserirDados\\AtualizacaoDiaria")
    args = ap.parse_args()
    sys.stdout = SaidaComEtapa(sys.stdout)
    sys.stderr = SaidaComEtapa(sys.stderr)
    ok = asyncio.run(principal(args))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
