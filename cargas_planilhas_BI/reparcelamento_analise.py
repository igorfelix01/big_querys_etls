"""
raw.reparcelamento_analise  <-  MESMO arquivo que o Power BI usa

O Power BI (consulta Reparcelamento_Analise) le:
  ...\\9. BI\\BI\\Bases_API\\Extratos\\EXTRATO_GERAL_Reparcelamento_Analise.csv
  (separador ";", UTF-8, 44 colunas)

Antes este script lia um Extratos_combined.csv antigo (pasta bases_CSV), que
nao era atualizado: contratos renegociados de novo ficavam com a data velha
(ex.: 501-66667 aparecia em mai/2025 no BigQuery e em set/2026 no BI).
Agora le o mesmo CSV do BI, entao BigQuery e BI ficam iguais.

Nao grava nada nas pastas: le uma copia temporaria e carrega no BigQuery.
Todas as colunas sobem como texto; o SQL reparcelamento_analise.sql converte.
"""

import csv
import shutil
import tempfile
import time
from pathlib import Path

import pandas as pd
from google.cloud import bigquery

# =========================
# CONFIGURACOES
# =========================

PROJECT_ID = "dadosfinanceiro-501613"
TABELA_RAW = f"{PROJECT_ID}.raw.reparcelamento_analise"

# mesmo arquivo do Power BI
ARQUIVO_CSV = Path(
    r"C:\Users\CarolinaSeikoBiadola\Bloko Capital\Financeiro - Documentos"
    r"\Financeiro - Bloko Investimentos\9. BI\BI\Bases_API\Extratos"
    r"\EXTRATO_GERAL_Reparcelamento_Analise.csv"
)


# =========================
# LEITURA (copia temporaria, funciona com o arquivo aberto/sincronizando)
# =========================

def copia_temporaria(arquivo, tentativas=5):
    destino = Path(tempfile.mkdtemp(prefix="reparcelamento_")) / arquivo.name
    for t in range(1, tentativas + 1):
        try:
            shutil.copyfile(arquivo, destino)
            return destino
        except PermissionError:
            if t == tentativas:
                raise PermissionError(
                    f"Sem permissao para ler {arquivo}. Feche o arquivo e, no "
                    "Explorador de Arquivos, clique com o botao direito nele -> "
                    "'Sempre manter neste dispositivo'. Depois rode de novo."
                )
            print(f"Arquivo ocupado, tentando de novo em {5 * t}s...")
            time.sleep(5 * t)


if not ARQUIVO_CSV.exists():
    raise FileNotFoundError(f"Arquivo nao encontrado: {ARQUIVO_CSV}")

print(f"Lendo: {ARQUIVO_CSV}")
copia = copia_temporaria(ARQUIVO_CSV)
try:
    df = pd.read_csv(
        copia,
        sep=";",
        dtype=str,
        encoding="utf-8-sig",
        quoting=csv.QUOTE_NONE,      # igual ao Power BI (QuoteStyle.None)
        keep_default_na=False,
        low_memory=False,
    )
finally:
    shutil.rmtree(copia.parent, ignore_errors=True)

df.columns = [str(c).strip().strip('"') for c in df.columns]
df = df.apply(lambda s: s.str.strip().str.strip('"'))
df = df.replace({"": None})
df = df.dropna(how="all")

for obrigatoria in ["chave", "ultima_data_reparcelamento", "costCenter_id", "subdominio"]:
    if obrigatoria not in df.columns:
        raise ValueError(f"Coluna '{obrigatoria}' nao encontrada no CSV. "
                         f"Colunas: {list(df.columns)}")

print(f"Linhas lidas: {len(df):,}".replace(",", "."))
print(f"Contratos (chave): {df['chave'].nunique():,}".replace(",", "."))
print(f"Ultima data de reparcelamento: {df['ultima_data_reparcelamento'].dropna().max()}")

# =========================
# CARGA NO BIGQUERY (tudo texto; o SQL converte)
# =========================

client = bigquery.Client(project=PROJECT_ID)

job = client.load_table_from_dataframe(
    df,
    TABELA_RAW,
    job_config=bigquery.LoadJobConfig(
        schema=[bigquery.SchemaField(c, "STRING") for c in df.columns],
        write_disposition="WRITE_TRUNCATE",
    ),
)
job.result()

print("Carga concluida com sucesso.")
print(f"Tabela: {TABELA_RAW}")
print(f"Linhas carregadas: {len(df):,}".replace(",", "."))
