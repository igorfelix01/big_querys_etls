# -*- coding: utf-8 -*-
"""
Atualizacao diaria do BigQuery
==============================

Roda TODOS os arquivos .sql da pasta sql_bigquery, sem ignorar nenhum.

A ordem e descoberta sozinha, lendo cada arquivo:
  - quais tabelas ele CRIA (CREATE TABLE / CREATE VIEW / INSERT / MERGE)
  - quais tabelas ele LE (FROM / JOIN dentro desses comandos)
Um arquivo so roda depois que todos os arquivos que criam as tabelas que
ele le terminaram. Arquivos que nao dependem um do outro rodam em paralelo.

Se um arquivo der erro, os arquivos que dependem dele NAO rodam (para nao
gerar tabela com dado velho/misturado). Os demais continuam normalmente.

Arquivo novo na pasta? E incluido automaticamente na proxima execucao.

Uso:
    python executar_pipeline.py              -> roda tudo
    python executar_pipeline.py --simular    -> mostra a ordem, nao executa
    python executar_pipeline.py --so "Clientes.sql"   -> roda so este arquivo
    python executar_pipeline.py --sem-conferir-raw    -> nao confere a carga do dia

Saida: log em ..\\logs\\pipeline_AAAA-MM-DD.log
       codigo de saida 0 = tudo OK, 1 = algum arquivo falhou
"""

import argparse
import datetime as dt
import logging
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, FIRST_COMPLETED, wait
from pathlib import Path

try:
    from google.cloud import bigquery
    from google.api_core import exceptions as gexc
except ImportError:                                  # instala sozinho na 1a vez
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet",
                           "google-cloud-bigquery"])
    from google.cloud import bigquery
    from google.api_core import exceptions as gexc


# ==========================================================
# CONFIGURACOES
# ==========================================================

PROJECT_ID = "dadosfinanceiro-501613"
LOCATION = "southamerica-east1"

# Pasta dos SQLs: a pasta "sql_bigquery" que fica AO LADO deste arquivo.
# (funciona em qualquer computador ou na EC2 sem alterar nada)
PASTA_SQL = Path(__file__).resolve().parent / "sql_bigquery"
if os.environ.get("PASTA_SQL_BIGQUERY"):          # opcional: outra pasta
    PASTA_SQL = Path(os.environ["PASTA_SQL_BIGQUERY"])

PASTA_LOG = PASTA_SQL.parent / "logs"

# Acesso ao BigQuery: usa o MESMO acesso que o seu Python de carga ja usa
# (login do gcloud / GOOGLE_APPLICATION_CREDENTIALS). Nao precisa criar nada.
# So se existir um arquivo com este nome ao lado do script, ele e usado.
ARQUIVO_CREDENCIAL = Path(__file__).parent / "credencial_bigquery.json"

# Antes de comecar, confere se o raw foi carregado HOJE (senao para tudo)
CONFERIR_RAW_DO_DIA = True
TABELAS_RAW_OBRIGATORIAS = [
    "raw.recebidas_atualizavel",
    "raw.areceber",
]

# quantos arquivos ao mesmo tempo (BigQuery aguenta bem; na EC2 pode subir
# com a variavel de ambiente PARALELO_SQL)
PARALELO = int(os.environ.get("PARALELO_SQL", "10"))
TENTATIVAS = 2                    # tentativas em erro temporario do Google
ESPERA_ENTRE_TENTATIVAS = 60      # segundos
TEMPO_MAXIMO_CONSULTA = 30 * 60   # segundos


# ==========================================================
# LOG
# ==========================================================

PASTA_LOG.mkdir(parents=True, exist_ok=True)
hoje = dt.date.today()
arquivo_log = PASTA_LOG / f"pipeline_{hoje:%Y-%m-%d}.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.FileHandler(arquivo_log, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("pipeline")


# ==========================================================
# LEITURA DOS ARQUIVOS E ORDEM (dependencias)
# ==========================================================

RE_COMENT_LINHA = re.compile(r"--[^\n]*")
RE_COMENT_BLOCO = re.compile(r"/\*.*?\*/", re.S)
RE_TEXTO = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")
RE_ALVO = re.compile(
    r"(?is)^\s*(?:CREATE\s+(?:OR\s+REPLACE\s+)?(?:TEMP(?:ORARY)?\s+)?(?:TABLE|VIEW)"
    r"(?:\s+IF\s+NOT\s+EXISTS)?|INSERT\s+(?:INTO\s+)?|MERGE\s+(?:INTO\s+)?)\s+`?([\w\-.]+)`?"
)
RE_FONTE = re.compile(r"(?i)\b(?:FROM|JOIN)\s+`([\w\-.]+)`")


def normalizar(nome: str) -> str:
    """'dadosfinanceiro-501613.raw.x' e 'raw.x' viram 'raw.x' (minusculo)."""
    partes = nome.strip("`").lower().split(".")
    return ".".join(partes[-2:]) if len(partes) >= 2 else partes[0]


def analisar(arquivo: Path):
    """Retorna (tabelas criadas, tabelas lidas) de um .sql."""
    sql = arquivo.read_text(encoding="utf-8-sig")
    limpo = RE_COMENT_BLOCO.sub(" ", RE_COMENT_LINHA.sub(" ", sql))
    limpo = RE_TEXTO.sub("''", limpo)

    cria, le = set(), set()
    for comando in limpo.split(";"):
        m = RE_ALVO.match(comando)
        if not m:
            continue          # SELECTs soltos (conferencias) nao contam como dependencia
        alvo = normalizar(m.group(1))
        if "." in alvo:                 # tabela temporaria (sem dataset) nao conta
            cria.add(alvo)
        le.update(normalizar(x) for x in RE_FONTE.findall(comando))
    return cria, le - cria


def montar_ordem(arquivos):
    """Calcula dependencias e etapas (etapa 1 = nao depende de ninguem)."""
    info = {a.name: analisar(a) for a in arquivos}

    quem_cria = {}
    for nome, (cria, _) in info.items():
        for t in cria:
            quem_cria.setdefault(t, set()).add(nome)

    deps = {}
    for nome, (_, le) in info.items():
        d = set()
        for t in le:
            d |= quem_cria.get(t, set())
        d.discard(nome)
        deps[nome] = d

    # dois arquivos que gravam a MESMA tabela nao podem rodar juntos:
    # o segundo (ordem alfabetica) espera o primeiro
    for t, escritores in quem_cria.items():
        ordem = sorted(escritores, key=str.lower)
        for anterior, seguinte in zip(ordem, ordem[1:]):
            deps[seguinte].add(anterior)

    nivel, visitando = {}, set()

    def calc(n):
        if n in nivel:
            return nivel[n]
        if n in visitando:          # dependencia circular
            return 0
        visitando.add(n)
        nv = 1 + max((calc(d) for d in deps[n]), default=0)
        visitando.discard(n)
        nivel[n] = nv
        return nv

    for n in deps:
        calc(n)
    for n in deps:                  # remove a aresta que fecha um ciclo
        ciclo = {d for d in deps[n] if nivel[d] >= nivel[n]}
        if ciclo:
            log.warning(f"Dependencia circular ignorada: {n} <-> {', '.join(sorted(ciclo))}")
            deps[n] -= ciclo

    return info, deps, nivel


def duracoes_anteriores() -> dict:
    """Tempo (s) de cada SQL nas ultimas execucoes (logs pipeline_*.log)."""
    # valores medidos em 22/10/2026 (usados ate existir log novo)
    tempos = {
        "Saldo Devedor.sql": 485,
        "recebiveis_diario_previsto.sql": 70,
        "looker_recebiveis_diario_previsto.sql": 458,
        "HistoricoInadimplencia.sql": 72,
        "A receber.sql": 22,
        "27_db_pagas_obras_transformacoes.sql": 20,
        "Recebidas.sql": 12,
    }
    re_ok = re.compile(r"\|\s+OK (.+?) \((\d+)s,")
    for log_antigo in sorted(PASTA_LOG.glob("pipeline_*.log"))[-10:]:
        try:
            for linha in log_antigo.read_text(encoding="utf-8", errors="ignore").splitlines():
                m = re_ok.search(linha)
                if m:
                    tempos[m.group(1).strip()] = int(m.group(2))
        except OSError:
            pass
    return tempos


def caminho_critico(deps: dict, tempos: dict) -> dict:
    """Para cada arquivo: tempo dele + o maior caminho de quem depende dele.
    Quem tem o caminho mais longo pela frente comeca primeiro."""
    filhos = {n: set() for n in deps}
    for n, ds in deps.items():
        for d in ds:
            filhos.setdefault(d, set()).add(n)
    memo = {}

    def cp(n, pilha=()):
        if n in memo:
            return memo[n]
        if n in pilha:
            return 0
        valor = tempos.get(n, 10) + max((cp(f, pilha + (n,)) for f in filhos.get(n, ())), default=0)
        memo[n] = valor
        return valor

    return {n: cp(n) for n in deps}


# ==========================================================
# BIGQUERY
# ==========================================================

def criar_cliente() -> bigquery.Client:
    if ARQUIVO_CREDENCIAL.exists():
        return bigquery.Client.from_service_account_json(
            str(ARQUIVO_CREDENCIAL), project=PROJECT_ID, location=LOCATION
        )
    return bigquery.Client(project=PROJECT_ID, location=LOCATION)


def conferir_raw(cliente) -> bool:
    ok = True
    for nome in TABELAS_RAW_OBRIGATORIAS:
        try:
            t = cliente.get_table(f"{PROJECT_ID}.{nome}")
        except gexc.NotFound:
            log.error(f"RAW nao encontrada: {nome}")
            ok = False
            continue
        quando = t.modified.astimezone()
        if quando.date() < hoje:
            log.error(f"RAW desatualizada: {nome} (ultima carga {quando:%d/%m/%Y %H:%M})")
            ok = False
        else:
            log.info(f"RAW ok: {nome} ({t.num_rows:,} linhas, carga {quando:%d/%m %H:%M})")
    return ok


def _msg_erro(e) -> str:
    erros = getattr(e, "errors", None)
    if erros:
        return "; ".join(str(x.get("message", x)) for x in erros)[:600]
    return str(e)[:600]


def rodar_arquivo(cliente, arquivo: Path):
    """Executa o .sql inteiro como script. Retorna (ok, segundos, mensagem)."""
    sql = arquivo.read_text(encoding="utf-8-sig")
    inicio = time.time()
    ultimo = ""
    for tentativa in range(1, TENTATIVAS + 1):
        try:
            job = cliente.query(sql, location=LOCATION)
            job.result(timeout=TEMPO_MAXIMO_CONSULTA)
            gb = (job.total_bytes_processed or 0) / 1024 ** 3
            return True, time.time() - inicio, f"{gb:.2f} GB"
        except (gexc.BadRequest, gexc.NotFound, gexc.Forbidden) as e:
            return False, time.time() - inicio, _msg_erro(e)   # erro de SQL: nao repete
        except Exception as e:
            ultimo = _msg_erro(e)
            if tentativa < TENTATIVAS:
                log.warning(f"   {arquivo.name}: falha temporaria ({ultimo}). "
                            f"Nova tentativa em {ESPERA_ENTRE_TENTATIVAS}s")
                time.sleep(ESPERA_ENTRE_TENTATIVAS)
    return False, time.time() - inicio, ultimo


# ==========================================================
# PRINCIPAL
# ==========================================================

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--simular", action="store_true", help="so mostra a ordem")
    p.add_argument("--so", default=None, help="roda so este arquivo (nome exato)")
    p.add_argument("--sem-conferir-raw", action="store_true")
    p.add_argument("--a-partir-de", nargs="+", default=None, metavar="ARQUIVO",
                   help="roda so estes arquivos e TUDO que depende deles")
    args = p.parse_args()

    log.info("=" * 70)
    log.info(f"Pasta dos SQLs: {PASTA_SQL}")
    if not PASTA_SQL.exists():
        log.error("Pasta dos SQLs nao encontrada.")
        return 1

    arquivos = sorted(PASTA_SQL.glob("*.sql"), key=lambda a: a.name.lower())
    if args.so:
        arquivos = [a for a in arquivos if a.name == args.so]
        if not arquivos:
            log.error(f"Arquivo nao encontrado: {args.so}")
            return 1
    if not arquivos:
        log.error("Nenhum .sql na pasta.")
        return 1

    info, deps, nivel = montar_ordem(arquivos)
    por_nome = {a.name: a for a in arquivos}

    if args.a_partir_de:
        faltando = [n for n in args.a_partir_de if n not in por_nome]
        if faltando:
            log.error(f"Arquivo(s) nao encontrado(s): {', '.join(faltando)}")
            return 1
        filhos = {}
        for n, ds in deps.items():
            for d in ds:
                filhos.setdefault(d, set()).add(n)
        escolhidos, fila = set(args.a_partir_de), list(args.a_partir_de)
        while fila:
            for f in filhos.get(fila.pop(), ()):
                if f not in escolhidos:
                    escolhidos.add(f)
                    fila.append(f)
        por_nome = {n: a for n, a in por_nome.items() if n in escolhidos}
        deps = {n: deps[n] & escolhidos for n in escolhidos}   # o resto ja esta pronto
        nivel = {n: nivel[n] for n in escolhidos}
        log.info(f"Modo --a-partir-de: {', '.join(args.a_partir_de)} "
                 f"+ dependentes = {len(escolhidos)} arquivo(s)")
    log.info(f"{len(por_nome)} arquivo(s) serao executados")

    if args.simular:
        for nv in sorted(set(nivel.values())):
            log.info(f"--- Etapa {nv} (rodam em paralelo) ---")
            for n in sorted((k for k, v in nivel.items() if v == nv), key=str.lower):
                cria = ", ".join(sorted(info[n][0])) or "(nao cria tabela)"
                espera = ", ".join(sorted(deps[n])) or "-"
                log.info(f"   {n}")
                log.info(f"        cria  : {cria}")
                log.info(f"        espera: {espera}")
        return 0

    cliente = criar_cliente()

    if CONFERIR_RAW_DO_DIA and not args.sem_conferir_raw and not args.so:
        if not conferir_raw(cliente):
            log.error("PARADO: raw nao foi carregado hoje. Rode a carga e tente de novo "
                      "(ou use --sem-conferir-raw).")
            return 1

    prioridade = caminho_critico(deps, duracoes_anteriores())
    log.info(f"Rodando ate {PARALELO} SQLs ao mesmo tempo "
             f"(prioridade para o caminho mais longo)")

    inicio_geral = time.time()
    pendentes = set(por_nome)
    concluidos, falharam, pulados = set(), [], []
    rodando = {}

    with ThreadPoolExecutor(max_workers=PARALELO) as ex:
        while pendentes or rodando:
            # quem depende de algo que deu erro nao roda
            for n in sorted(pendentes):
                ruins = deps[n] & (set(falharam) | set(pulados))
                if ruins:
                    pendentes.discard(n)
                    pulados.append(n)
                    log.error(f"  NAO RODOU {n} (depende de: {', '.join(sorted(ruins))})")

            prontos = sorted((n for n in pendentes if deps[n] <= concluidos),
                             key=lambda n: (-prioridade.get(n, 0), n.lower()))
            for n in prontos:
                if len(rodando) >= PARALELO:
                    break
                pendentes.discard(n)
                log.info(f"> {n}")
                rodando[ex.submit(rodar_arquivo, cliente, por_nome[n])] = n

            if not rodando:
                if pendentes:
                    log.error(f"Sem como continuar: {', '.join(sorted(pendentes))}")
                    falharam.extend(sorted(pendentes))
                    pendentes.clear()
                break

            feitos, _ = wait(rodando, return_when=FIRST_COMPLETED)
            for fut in feitos:
                n = rodando.pop(fut)
                ok, seg, msg = fut.result()
                if ok:
                    concluidos.add(n)
                    log.info(f"  OK {n} ({seg:.0f}s, {msg})")
                else:
                    falharam.append(n)
                    log.error(f"  ERRO {n} ({seg:.0f}s): {msg}")

    minutos = (time.time() - inicio_geral) / 60
    log.info("-" * 70)
    log.info(f"Executados com sucesso: {len(concluidos)} de {len(por_nome)}")
    if falharam or pulados:
        if falharam:
            log.error(f"Com erro ({len(falharam)}): {', '.join(falharam)}")
        if pulados:
            log.error(f"Nao rodaram por dependerem de erro ({len(pulados)}): {', '.join(pulados)}")
        log.error(f"FIM COM ERRO ({minutos:.1f} min). Log: {arquivo_log}")
        return 1
    log.info(f"FIM OK ({minutos:.1f} min). No Looker, use 'Atualizar dados' se o cache segurar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
