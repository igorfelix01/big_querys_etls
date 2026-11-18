"""
ATUALIZACAO COMPLETA - Sienge -> BigQuery -> Looker
(pasta AtualizacaoCompleta, dentro da BigQuery_Financeiro)

Roda tudo, na ordem certa:
  1.  Dados do Sienge       sienge_rapido.py (deste pacote), que usa as
                            funcoes de InserirDados\\AtualizacaoDiaria
                            (clientes, unidades, vendas, a receber,
                             recebidas historico, recebidas atualizavel)
                            as 6 cargas ao mesmo tempo. Com --sienge-original
                            roda o Atualizacao.py antigo (uma de cada vez).
  1b. Unidades das vendas   AtualizarVendasUnidades.py  (raw.vendas_unidades)
  1c. Telefones             script do InserirDados que carrega
                            raw.clientes_telefones (achado pelo conteudo)
  2.  Obras                 InserirDados\\Obrasatt.py
                            (raw.pagas_obras + raw.planejamento_obras)
  2b. Planilhas do BI       cargas_planilhas_BI\\ (vem neste pacote)
                            nome_companhias.py              -> raw.nome_companhias
                            reparcelamento_analise.py       -> raw.reparcelamento_analise
                            distratos_controle_operacoes.py -> raw.distratos_controle_operacoes
                            (mesmos arquivos do Power BI; se o arquivo nao
                             existir no computador - ex.: EC2 - a etapa e pulada)
  3.  SQLs                  executar_pipeline.py + sql_bigquery\\ DESTE pacote
                            (todos os .sql, na ordem das dependencias)
                            NAO roda se a etapa 1 falhar (raw pela metade)

MAIS RAPIDO (EC2): as cargas rodam em 2 fases, cada fase ao mesmo tempo:
  FASE 1: Sienge + Unidades das vendas + Obras + planilhas (independentes)
  FASE 2: Telefones (depois do Sienge, se o script existir)
  depois: SQLs, ate 10 ao mesmo tempo (PARALELO_SQL), comecando pelos que
          tem o caminho mais longo pela frente (Saldo Devedor etc.)
  Com --sequencial volta a rodar uma carga de cada vez.

NAO grava nem copia nada dentro das pastas dos seus scripts: so le.
(o unico arquivo que ele cria e o log, na pasta logs ao lado dele)

  python atualizar_tudo.py                 -> faz tudo
  python atualizar_tudo.py --com-planilhas -> tambem recarrega as outras
                                              tabelas de Excel/CSV do InserirDados
  python atualizar_tudo.py --so-sql        -> so os SQLs
  python atualizar_tudo.py --sequencial    -> cargas uma de cada vez (como antes)
  python atualizar_tudo.py --so-planilhas  -> so as planilhas (BI + InserirDados)
                                              e depois os SQLs. Recarrega as
                                              tabelas que o BigQuery apaga com
                                              60 dias (db_perfomados, situacoes...)
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from pathlib import Path

PASTA = Path(__file__).resolve().parent
# pasta que tem o InserirDados: procura nesta pasta e nas de cima, e tambem
# em ...\BI\Bases_API\BigQuery_Financeiro (assim funciona mesmo se a pasta
# AtualizacaoCompleta for extraida em outro lugar dentro da pasta do BI)
def _achar_base():
    for pasta in [PASTA, *PASTA.parents]:
        for c in (pasta,
                  pasta / "BigQuery_Financeiro",
                  pasta / "Bases_API" / "BigQuery_Financeiro"):
            try:
                if (c / "InserirDados").is_dir():
                    return c
            except OSError:
                pass
    return PASTA.parent


BASE = _achar_base()
# pasta "BI" do SharePoint (BI\\Bases_API\\BigQuery_Financeiro)
PASTA_BI = BASE.parents[1] if len(BASE.parents) > 1 else BASE
PASTA_LOGS = PASTA / "logs"
PASTA_LOGS.mkdir(exist_ok=True)
ARQUIVO_LOG = PASTA_LOGS / f"atualizacao_completa_{date.today():%Y-%m-%d}.log"

# limite de tempo de cada etapa (minutos)
LIMITE_MIN = {"sienge": 240, "unidades": 60, "telefones": 120,
              "obras": 120, "sql": 180, "planilhas": 60}

# 2b. cargas das planilhas do BI (vem neste pacote, pasta cargas_planilhas_BI)
#     (script, arquivo de origem dentro da pasta BI)
CARGAS_BI = [
    ("nome_companhias.py",              Path("Nome_Companhias.xlsx")),
    ("reparcelamento_analise.py",       Path("Bases_API") / "Extratos" / "EXTRATO_GERAL_Reparcelamento_Analise.csv"),
    ("distratos_controle_operacoes.py", Path("DISTRATOS - CONTROLE OPERAÇOES.xlsx")),
]

# tabelas que vem de Excel/CSV do SharePoint (mesma lista e ordem do
# atualizar_raw.py; raw.comparativo vem do db_perfomados.py, como hoje)
SCRIPTS_PLANILHAS = [
    "situacoes.py",
    "classificacao_bloko_niveis.py",
    "nome_companhias_pag.py",
    "db_perfomados.py",
    # "cri_excel.py" FORA: o Excel do CRI esta parado desde 2025 e
    # sobrescreveria raw.cri (hoje carregada pelo cri_extranet_bigquery.py)
    "contas_bancarias.py",
    "cobranca3p.py",
    "linhas_temporais_geral.py",
]

IGNORAR_PASTAS = {"Old", "old", "teste", "backup", "__pycache__", ".venv", "logs"}


# ====================================================================
_TRAVA_LOG = threading.Lock()


def log(msg=""):
    linha = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}"
    with _TRAVA_LOG:
        print(linha, flush=True)
        with open(ARQUIVO_LOG, "a", encoding="utf-8") as f:
            f.write(linha + "\n")


def em_paralelo(tarefas, sequencial=False):
    """tarefas = {etapa: funcao_sem_argumento}. Roda junto (ou em fila com
    --sequencial) e devolve {etapa: True/False}."""
    if sequencial or len(tarefas) <= 1:
        return {etapa: f() for etapa, f in tarefas.items()}
    with ThreadPoolExecutor(max_workers=len(tarefas)) as ex:
        futuros = {etapa: ex.submit(f) for etapa, f in tarefas.items()}
        return {etapa: fut.result() for etapa, fut in futuros.items()}


def valido(p):
    return not (set(p.parts) & IGNORAR_PASTAS)


def achar(nome, onde=None):
    """Procura um arquivo pelo nome dentro da pasta (ate 3 niveis)."""
    base = onde or PASTA
    for profundidade in range(4):
        padrao = "/".join(["*"] * profundidade + [nome]) if profundidade else nome
        achados = sorted(p for p in base.glob(padrao) if valido(p))
        if achados:
            return achados[0]
    return None


def achar_telefones(onde):
    """Acha o script que carrega raw.clientes_telefones (pelo conteudo)."""
    candidatos = []
    for p in sorted(onde.rglob("*.py")):
        if not valido(p) or p.resolve() == Path(__file__).resolve():
            continue
        try:
            txt = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if "clientes_telefones" in txt and ("load_table" in txt or "to_gbq" in txt):
            candidatos.append(p)
    # prefere o que esta na pasta Telefones
    candidatos.sort(key=lambda p: (0 if "Telefones" in p.parts else 1, len(p.parts)))
    return candidatos[0] if candidatos else None


def ambiente(pasta_extra=None):
    env = os.environ.copy()
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    # conta de servico (recomendado no EC2): credencial_bigquery.json nesta pasta
    cred = PASTA / "credencial_bigquery.json"
    if cred.exists() and not env.get("GOOGLE_APPLICATION_CREDENTIALS"):
        env["GOOGLE_APPLICATION_CREDENTIALS"] = str(cred)
    if pasta_extra:
        env["PYTHONPATH"] = str(pasta_extra) + os.pathsep + env.get("PYTHONPATH", "")
    return env


def rodar(nome, script, limite_min, args=(), cwd=None, pasta_extra=None):
    log("=" * 90)
    log(f"INICIO: {nome}  ({script})")
    log("=" * 90)
    inicio = time.time()
    try:
        proc = subprocess.Popen(
            [sys.executable, "-u", str(script), *args],
            cwd=str(cwd or script.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=ambiente(pasta_extra),
        )
        prefixo = f"[{nome}] "          # etapas em paralelo: cada linha diz de quem e
        for linha in proc.stdout:
            with _TRAVA_LOG:
                print(prefixo + linha, end="", flush=True)
                with open(ARQUIVO_LOG, "a", encoding="utf-8") as f:
                    f.write(prefixo + linha)
            if time.time() - inicio > limite_min * 60:
                proc.kill()
                log(f"PASSOU DO LIMITE DE {limite_min} MIN - {nome} interrompida")
                return False
        codigo = proc.wait()
    except Exception as e:
        log(f"ERRO ao iniciar {script}: {e}")
        return False

    minutos = (time.time() - inicio) / 60
    if codigo == 0:
        log(f"OK: {nome} ({minutos:.1f} min)")
        return True
    log(f"FALHOU: {nome} (codigo {codigo}, {minutos:.1f} min)")
    return False


def raw_principal_carregado_hoje() -> bool:
    """True se raw.areceber e raw.recebidas_atualizavel foram gravados hoje."""
    try:
        import datetime as _dt
        from google.cloud import bigquery as _bq
        cli = _bq.Client(project="dadosfinanceiro-501613")
        hoje = _dt.date.today()
        for nome in ("raw.areceber", "raw.recebidas_atualizavel"):
            t = cli.get_table(f"dadosfinanceiro-501613.{nome}")
            quando = t.modified.astimezone()
            log(f"   {nome}: ultima carga {quando:%d/%m/%Y %H:%M}")
            if quando.date() < hoje:
                return False
        return True
    except Exception as e:
        log(f"   nao consegui conferir o raw no BigQuery: {e}")
        return False


def rodar_obras(obras_py):
    """
    O Obrasatt.py le o Empreendimentos.xlsx da propria pasta.
    Se ele nao estiver la, roda uma COPIA TEMPORARIA do Obrasatt.py numa pasta
    temporaria do sistema, junto do Empreendimentos.xlsx de Bases_API\\Obras.
    Nada e copiado para as suas pastas; a pasta temporaria e apagada no fim.
    """
    if (obras_py.parent / "Empreendimentos.xlsx").exists():
        return rodar("Obras", obras_py, LIMITE_MIN["obras"])

    planilha = next((c for c in [PASTA / "Empreendimentos.xlsx",
                                 BASE / "Empreendimentos.xlsx",
                                 BASE.parent / "Obras" / "Empreendimentos.xlsx"]
                     if c.exists()), None)
    if not planilha:
        log("ERRO: nao achei o Empreendimentos.xlsx (nem junto do Obrasatt.py, "
            "nem em Bases_API\\Obras)")
        return False

    temp = Path(tempfile.mkdtemp(prefix="obras_"))
    try:
        shutil.copy2(obras_py, temp / obras_py.name)
        shutil.copy2(planilha, temp / "Empreendimentos.xlsx")
        log(f"Usando Empreendimentos.xlsx de {planilha}")
        return rodar("Obras", temp / obras_py.name, LIMITE_MIN["obras"],
                     pasta_extra=obras_py.parent)
    finally:
        shutil.rmtree(temp, ignore_errors=True)


# ====================================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--com-planilhas", action="store_true")
    ap.add_argument("--so-sql", action="store_true")
    ap.add_argument("--so-planilhas", action="store_true")
    ap.add_argument("--sequencial", action="store_true",
                    help="roda as cargas uma de cada vez (como antes)")
    ap.add_argument("--sienge-original", action="store_true",
                    help="usa o Atualizacao.py antigo (6 cargas uma de cada vez)")
    ap.add_argument("--limite-api", default="5",
                    help="chamadas simultaneas na API bulk-data do Sienge (padrao 5)")
    a = ap.parse_args()
    if a.so_planilhas:
        a.com_planilhas = True

    inicio = time.time()
    log("#" * 90)
    log(f"ATUALIZACAO COMPLETA - pasta {PASTA}")
    log("#" * 90)

    resultado = {}

    inserir = BASE / "InserirDados"
    if not inserir.exists():
        log(f"AVISO: nao achei a pasta InserirDados em {BASE}")
        inserir = BASE

    seq = a.sequencial
    fase1, fase2 = {}, {}

    if not a.so_sql and not a.so_planilhas:
        diaria = achar("Atualizacao.py", inserir)
        unid = achar("AtualizarVendasUnidades.py", inserir) or achar("AtualizarVendasUnidades.py")
        pasta_cred = diaria.parent if diaria else inserir
        tel = achar_telefones(inserir)
        obras = achar("Obrasatt.py", inserir)

        # 1. Sienge (clientes, unidades, vendas, a receber, recebidas)
        rapido = PASTA / "sienge_rapido.py"
        if diaria and rapido.exists() and not a.sienge_original:
            fase1["1. Dados do Sienge"] = lambda: rodar(
                "Dados do Sienge", rapido, LIMITE_MIN["sienge"],
                ["--pasta", str(diaria.parent), "--limite-api", str(a.limite_api)],
                cwd=diaria.parent)
        elif diaria:
            fase1["1. Dados do Sienge"] = lambda: rodar("Dados do Sienge", diaria, LIMITE_MIN["sienge"])
        else:
            log("ERRO: nao achei InserirDados/AtualizacaoDiaria/Atualizacao.py")
            resultado["1. Dados do Sienge"] = False

        # 2. Obras (raw.pagas_obras + raw.planejamento_obras) - independe do Sienge diario
        if obras:
            fase1["2. Obras"] = lambda: rodar_obras(obras)
        else:
            log("ERRO: nao achei Obrasatt.py")
            resultado["2. Obras"] = False

        # 1b. Unidades das vendas (raw.vendas_unidades) - nao depende das
        #     outras cargas (le direto da API): roda junto, na fase 1
        if unid:
            fase1["1b. Unidades das vendas"] = lambda: rodar(
                "Unidades das vendas", unid, LIMITE_MIN["unidades"],
                cwd=pasta_cred, pasta_extra=pasta_cred)
        else:
            log("ERRO: nao achei AtualizarVendasUnidades.py")
            resultado["1b. Unidades das vendas"] = False

        # 1c. Telefones (raw.clientes_telefones) - depois do Sienge
        if tel:
            fase2["1c. Telefones"] = lambda: rodar("Telefones", tel, LIMITE_MIN["telefones"])
        else:
            log("AVISO: nao achei nenhum script que carregue raw.clientes_telefones "
                "(a tabela fica como esta; o Clientes.sql so usa como reserva)")

    if not a.so_sql:
        # 2b. Planilhas do BI (versoes deste pacote) - leem arquivo local,
        #     rodam junto com o Sienge
        pasta_cargas = PASTA / "cargas_planilhas_BI"
        for nome, origem in CARGAS_BI:
            script = pasta_cargas / nome
            etapa = f"2b. {nome}"
            if not script.exists():
                log(f"ERRO: nao achei {script}")
                resultado[etapa] = False
            elif not (PASTA_BI / origem).exists():
                log(f"AVISO: {PASTA_BI / origem} nao existe neste computador - {nome} pulado")
            else:
                fase1[etapa] = (lambda n=nome, sc=script:
                                rodar(n, sc, LIMITE_MIN["planilhas"]))

        # (opcional) planilhas Excel/CSV - em fila entre si, junto com o Sienge
        if a.com_planilhas:
            def planilhas():
                # cada planilha vai para uma tabela diferente: rodam juntas
                tarefas = {}
                for nome in SCRIPTS_PLANILHAS:
                    arq = achar(nome, inserir)
                    if not arq:
                        log(f"AVISO: {nome} nao encontrado - pulando")
                        continue
                    tarefas[nome] = (lambda n=nome, arq=arq:
                                     rodar(f"Planilha {n}", arq, LIMITE_MIN["planilhas"]))
                return all(em_paralelo(tarefas, seq).values()) if tarefas else True
            fase1["Planilhas Excel/CSV"] = planilhas

    if fase1:
        log(f"FASE 1 ({'em fila' if seq else 'ao mesmo tempo'}): {', '.join(fase1)}")
        resultado.update(em_paralelo(fase1, seq))
    if fase2:
        log(f"FASE 2 ({'em fila' if seq else 'ao mesmo tempo'}): {', '.join(fase2)}")
        resultado.update(em_paralelo(fase2, seq))

    # 3. SQLs
    #    Se a carga do Sienge (A Receber, Recebidas...) FALHOU, o raw pode estar
    #    PARCIAL (a carga apaga a tabela e recarrega por periodo). Rodar os SQLs
    #    em cima disso estraga trusted/analytics (ex.: contratos com so 6 das 37
    #    parcelas). Entao NAO roda os SQLs: as tabelas ficam com a versao anterior.
    pipeline = PASTA / "executar_pipeline.py"
    if not pipeline.exists():
        pipeline = achar("executar_pipeline.py", BASE)
    sienge_falhou = (not a.so_sql and not a.so_planilhas
                     and resultado.get("1. Dados do Sienge") is False)
    if sienge_falhou and raw_principal_carregado_hoje():
        # alguma parte secundaria do Sienge falhou (ex.: Clientes), mas o
        # A Receber e as Recebidas foram carregados hoje -> roda os SQLs
        log("ATENCAO: a carga do Sienge teve erro em alguma etapa, mas raw.areceber e")
        log("         raw.recebidas_atualizavel foram carregados HOJE -> os SQLs vao rodar.")
        log("         Veja acima qual etapa do Sienge falhou.")
        sienge_falhou = False
    if sienge_falhou:
        log("ATENCAO: a carga do Sienge FALHOU -> SQLs NAO foram rodados para nao")
        log("         gerar tabelas com dados pela metade. Rode de novo a atualizacao (ATUALIZAR_TUDO.bat ou atualizar_tudo.sh).")
        resultado["3. SQLs (BigQuery)"] = False
    elif pipeline:
        resultado["3. SQLs (BigQuery)"] = rodar("SQLs do BigQuery", pipeline, LIMITE_MIN["sql"],
                                                ["--sem-conferir-raw"])
    else:
        log("ERRO: nao achei executar_pipeline.py")
        resultado["3. SQLs (BigQuery)"] = False

    # resumo
    log("#" * 90)
    log("RESUMO")
    for etapa, ok in resultado.items():
        log(f"  {etapa}: {'OK' if ok else 'FALHOU'}")
    log(f"Tempo total: {(time.time() - inicio) / 60:.1f} min")
    log(f"Log: {ARQUIVO_LOG}")
    log("#" * 90)
    sys.exit(0 if all(resultado.values()) else 1)


if __name__ == "__main__":
    main()
