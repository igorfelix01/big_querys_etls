# -*- coding: utf-8 -*-
"""
ATUALIZAR SO AS ANALISES NOVAS DE COBRANCA / CAIXA
==================================================
Roda somente estes SQLs (pasta sql_bigquery), um depois do outro:

  1. RiscoContratos.sql        risco de rolagem
  2. InadimRegularização.sql   inadimplentes que voltam a ficar em dia
  3. RenegociaçãoEficiencia.sql         as renegociacoes funcionam?
  4. concentração risco.sql            concentracao do risco
  5. ProjeçãoCaixa.sql                projecao de caixa
  6. looker_inadimplencia_ano_venda_mensal.sql  % inadimplente por ano de venda (mes a mes)

(alerta precoce e safra de vendas NAO entram aqui)

Uso:
    python atualizar_analises_cobranca.py

Usa as tabelas base que ja estao no BigQuery (HistoricoInadimplencia,
fato_titulos_totalizador, saldo_devedor...). Se alguma nao foi atualizada
hoje, ele avisa, mas roda mesmo assim. Para atualizar as bases antes,
rode o ATUALIZAR_SO_SQL.

Acesso: o mesmo dos outros scripts (login do gcloud ou o arquivo
credencial_bigquery.json ao lado deste arquivo).
Log: pasta logs\\analises_cobranca_AAAA-MM-DD.log
"""

import datetime as dt
import sys
import time
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

PROJECT_ID = "dadosfinanceiro-501613"
LOCATION = "southamerica-east1"
PASTA = Path(__file__).resolve().parent
PASTA_SQL = PASTA / "sql_bigquery"
ARQUIVO_CREDENCIAL = PASTA / "credencial_bigquery.json"

ARQUIVOS = [
    "RiscoContratos.sql",
    "InadimRegularização.sql",
    "RenegociaçãoEficiencia.sql",
    "concentração risco.sql",
    "ProjeçãoCaixa.sql",
    "looker_inadimplencia_ano_venda_mensal.sql",
]

# tabelas que esses SQLs leem (so para avisar se estao velhas)
TABELAS_BASE = [
    "analytics.HistoricoInadimplencia",
    "analytics.fato_titulos_totalizador",
    "analytics.saldo_devedor",
    "analytics.fato_recebidas",
    "analytics.fato_renegociacoes",
]

PASTA_LOG = PASTA / "logs"
PASTA_LOG.mkdir(exist_ok=True)
ARQUIVO_LOG = PASTA_LOG / f"analises_cobranca_{dt.date.today():%Y-%m-%d}.log"


def log(msg=""):
    linha = f"{dt.datetime.now():%H:%M:%S} | {msg}"
    print(linha, flush=True)
    with open(ARQUIVO_LOG, "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def criar_cliente():
    if ARQUIVO_CREDENCIAL.exists():
        return bigquery.Client.from_service_account_json(
            str(ARQUIVO_CREDENCIAL), project=PROJECT_ID, location=LOCATION)
    return bigquery.Client(project=PROJECT_ID, location=LOCATION)


def conferir_bases(cliente):
    hoje = dt.date.today()
    for nome in TABELAS_BASE:
        try:
            t = cliente.get_table(f"{PROJECT_ID}.{nome}")
            quando = t.modified.astimezone()
            aviso = "" if quando.date() >= hoje else "   <- NAO foi atualizada hoje"
            log(f"   {nome}: atualizada em {quando:%d/%m/%Y %H:%M}{aviso}")
        except gexc.NotFound:
            log(f"   {nome}: NAO EXISTE (rode antes o ATUALIZAR_SO_SQL)")


def rodar(cliente, arquivo: Path) -> bool:
    log("-" * 70)
    log(f"Rodando {arquivo.name} ...")
    inicio = time.time()
    try:
        job = cliente.query(arquivo.read_text(encoding="utf-8-sig"), location=LOCATION)
        linhas = list(job.result(timeout=60 * 60))   # resultado do ultimo SELECT
    except Exception as e:
        erros = getattr(e, "errors", None)
        msg = "; ".join(str(x.get("message", x)) for x in erros) if erros else str(e)
        log(f"ERRO em {arquivo.name}: {msg[:600]}")
        return False

    gb = (job.total_bytes_processed or 0) / 1024 ** 3
    log(f"OK {arquivo.name} ({time.time() - inicio:.0f}s, {gb:.2f} GB)")
    if linhas:
        log("Resultado rapido (ultima consulta do arquivo):")
        colunas = list(linhas[0].keys())
        log("   " + " | ".join(colunas))
        for r in linhas[:15]:
            log("   " + " | ".join("" if v is None else str(v) for v in r.values()))
    return True


def main() -> int:
    log("=" * 70)
    log("ATUALIZAR SO AS ANALISES NOVAS (sem alerta precoce e safra)")
    log("=" * 70)
    cliente = criar_cliente()
    log("Tabelas base:")
    conferir_bases(cliente)

    resultado = {}
    for nome in ARQUIVOS:
        arquivo = PASTA_SQL / nome
        if not arquivo.exists():
            log(f"ERRO: nao achei {arquivo}")
            resultado[nome] = False
            continue
        resultado[nome] = rodar(cliente, arquivo)

    log("=" * 70)
    for nome, ok in resultado.items():
        log(f"  {nome}: {'OK' if ok else 'FALHOU'}")
    log(f"Log: {ARQUIVO_LOG}")
    return 0 if all(resultado.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
