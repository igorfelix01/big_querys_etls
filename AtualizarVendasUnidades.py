"""
Carrega SO a raw.vendas_unidades (unidades/lotes de cada contrato de venda)
direto da API do Sienge (sales-contracts -> salesContractUnits).

Mesma regra do Vendas\\vendas.py, mas NAO mexe na raw.vendas
(a raw.vendas continua sendo carregada pelo AtualizarVendas.py da rotina diaria).

Colunas iguais as da tabela atual:
  id, main, name, participationPercentage, ChaveEspecifica,
  enterpriseId, receivableBillId

Colocar na pasta InserirDados\\AtualizacaoDiaria (usa o Credenciais.py de la).
"""

import sys
import time
from datetime import datetime

import requests
import pandas as pd
from google.cloud import bigquery

from Credenciais import obter_credenciais


PROJECT_ID = "dadosfinanceiro-501613"
LOCATION = "southamerica-east1"
TABELA = f"{PROJECT_ID}.raw.vendas_unidades"
SUBDOMINIOS = ["sej"]
LIMIT = 200

COLUNAS = [
    "id",
    "main",
    "name",
    "participationPercentage",
    "ChaveEspecifica",
    "enterpriseId",
    "receivableBillId",
]


def log(msg):
    print(f"{datetime.now():%Y-%m-%d %H:%M:%S} - {msg}", flush=True)


def get(url, sub, tentativas=4):
    for t in range(1, tentativas + 1):
        try:
            r = requests.get(url, headers={"Authorization": obter_credenciais(sub)}, timeout=180)
            if r.status_code == 200:
                return r.json()
            if r.status_code in (400, 429, 500, 502, 503, 504) and t < tentativas:
                log(f"HTTP {r.status_code}, tentando de novo em {10 * t}s")
                time.sleep(10 * t)
                continue
            raise RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
        except (requests.Timeout, requests.ConnectionError) as e:
            if t < tentativas:
                log(f"Falha de conexao ({type(e).__name__}), tentando de novo em {10 * t}s")
                time.sleep(10 * t)
                continue
            raise
    raise RuntimeError("sem resposta da API")


def baixar_contratos(sub):
    base = f"https://api.sienge.com.br/{sub}/public/api/v1/sales-contracts?"
    contratos, offset = [], 0
    while True:
        dados = get(f"{base}limit={LIMIT}&offset={offset}", sub)
        if "resultSetMetadata" not in dados:
            raise RuntimeError("Resposta da API sem resultSetMetadata")
        total = dados["resultSetMetadata"].get("count", 0)
        pagina = dados.get("results", []) or []
        if not pagina:
            break
        contratos.extend(pagina)
        log(f"{sub}: {len(contratos)}/{total} contratos")
        offset += LIMIT
        if offset >= total:
            break
    return contratos


def texto_bill(v):
    """receivableBillId como no vendas.py: inteiro, sem '.0'; vazio/0 = fora."""
    try:
        n = int(float(v))
    except (TypeError, ValueError):
        return None
    return None if n == 0 else str(n)


def main():
    linhas = []
    for sub in SUBDOMINIOS:
        for c in baixar_contratos(sub):
            bill = texto_bill(c.get("receivableBillId"))
            if bill is None:
                continue
            chave = f"{c.get('companyId')}-{bill}"
            for u in c.get("salesContractUnits") or []:
                if not isinstance(u, dict):
                    continue
                linhas.append({
                    "id": u.get("id"),
                    "main": u.get("main"),
                    "name": u.get("name"),
                    "participationPercentage": u.get("participationPercentage"),
                    "ChaveEspecifica": chave,
                    "enterpriseId": c.get("enterpriseId"),
                    "receivableBillId": bill,
                })

    if not linhas:
        raise RuntimeError("Nenhuma unidade retornada pela API - nada foi carregado")

    df = pd.DataFrame(linhas, columns=COLUNAS)
    for col in COLUNAS:
        df[col] = df[col].map(lambda v: None if v is None or (isinstance(v, float) and v != v) else str(v))
    log(f"Unidades para carregar: {len(df):,}".replace(",", "."))

    client = bigquery.Client(project=PROJECT_ID)
    job = client.load_table_from_dataframe(
        df,
        TABELA,
        job_config=bigquery.LoadJobConfig(
            schema=[bigquery.SchemaField(c, "STRING") for c in COLUNAS],
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        ),
        location=LOCATION,
    )
    job.result()
    log(f"OK: {TABELA} com {client.get_table(TABELA).num_rows:,} linhas".replace(",", "."))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log(f"ERRO: {e}")
        sys.exit(1)
