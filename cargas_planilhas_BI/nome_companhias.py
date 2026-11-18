"""
raw.nome_companhias  <-  MESMA planilha que o Power BI usa

O Power BI (consultas NomeCompanhias e EmpreendimentosVendas) le:
  ...\\9. BI\\BI\\Nome_Companhias.xlsx   -> tabela do Excel "Table1"

Antes este script lia OUTRA copia (Bases_API\\BigQuery_Financeiro\\bases_Excel\\
Nome_Companhias.xlsx), que esta desatualizada (sem as empresas 386 e 399, por
exemplo). Agora le a mesma do BI, entao BigQuery e BI ficam com as mesmas
empresas/grupos.
"""

import shutil
import tempfile
import time
from pathlib import Path

import pandas as pd
from openpyxl import load_workbook
from google.cloud import bigquery

# =========================
# CONFIGURACOES
# =========================

PROJECT_ID = "dadosfinanceiro-501613"

# mesma planilha do Power BI
ARQUIVO_EXCEL = Path(
    r"C:\Users\CarolinaSeikoBiadola\Bloko Capital\Financeiro - Documentos"
    r"\Financeiro - Bloko Investimentos\9. BI\BI\Nome_Companhias.xlsx"
)
NOME_TABELA_EXCEL = "Table1"

TABELA_RAW = f"{PROJECT_ID}.raw.nome_companhias"

COLUNAS = ["companyGroup", "companyId", "companyName",
           "projectName", "enterpriseId", "enterpriseName"]


# =========================
# LEITURA DA TABELA "Table1" (igual ao Power BI)
# =========================

def copia_temporaria(arquivo, tentativas=5):
    """
    Copia a planilha para uma pasta temporaria e le a copia.
    Assim funciona mesmo com o arquivo aberto no Excel ou sincronizando
    no OneDrive/SharePoint. A copia e apagada no final.
    """
    destino = Path(tempfile.mkdtemp(prefix="nome_companhias_")) / arquivo.name
    for t in range(1, tentativas + 1):
        try:
            shutil.copyfile(arquivo, destino)
            return destino
        except PermissionError:
            if t == tentativas:
                raise PermissionError(
                    f"Sem permissao para ler {arquivo}. Feche a planilha no Excel e, "
                    "no Explorador de Arquivos, clique com o botao direito nela -> "
                    "'Sempre manter neste dispositivo'. Depois rode de novo."
                )
            print(f"Arquivo ocupado, tentando de novo em {5 * t}s...")
            time.sleep(5 * t)


def ler_tabela_excel(arquivo, nome_tabela):
    copia = copia_temporaria(arquivo)
    try:
        return _ler(copia, nome_tabela)
    finally:
        shutil.rmtree(copia.parent, ignore_errors=True)


def _ler(arquivo, nome_tabela):
    wb = load_workbook(arquivo, data_only=True, read_only=False)
    for ws in wb.worksheets:
        if nome_tabela in ws.tables:
            intervalo = ws.tables[nome_tabela].ref          # ex.: "C3:H416"
            linhas = [[c.value for c in linha] for linha in ws[intervalo]]
            return pd.DataFrame(linhas[1:], columns=linhas[0])
    raise ValueError(f"Tabela '{nome_tabela}' nao encontrada em {arquivo}")


if not ARQUIVO_EXCEL.exists():
    raise FileNotFoundError(f"Planilha nao encontrada: {ARQUIVO_EXCEL}")

print(f"Lendo: {ARQUIVO_EXCEL} (tabela {NOME_TABELA_EXCEL})")
df = ler_tabela_excel(ARQUIVO_EXCEL, NOME_TABELA_EXCEL)
df.columns = [str(c).strip() for c in df.columns]

faltando = [c for c in COLUNAS if c not in df.columns]
if faltando:
    raise ValueError(f"Colunas nao encontradas na Table1: {faltando}")

df = df[COLUNAS].dropna(how="all")

# =========================
# TIPAGEM IGUAL AO POWER BI
# =========================

for c in ["companyGroup", "companyName", "projectName", "enterpriseName"]:
    df[c] = df[c].astype("string")

df["companyId"] = pd.to_numeric(df["companyId"], errors="coerce").astype("Int64")
df["enterpriseId"] = pd.to_numeric(df["enterpriseId"], errors="coerce").astype("Int64")

# =========================
# CARGA NO BIGQUERY
# =========================

client = bigquery.Client(project=PROJECT_ID)

schema = [
    bigquery.SchemaField("companyGroup", "STRING"),
    bigquery.SchemaField("companyId", "INT64"),
    bigquery.SchemaField("companyName", "STRING"),
    bigquery.SchemaField("projectName", "STRING"),
    bigquery.SchemaField("enterpriseId", "INT64"),
    bigquery.SchemaField("enterpriseName", "STRING"),
]

job = client.load_table_from_dataframe(
    df,
    TABELA_RAW,
    job_config=bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
    ),
)
job.result()

print("Carga concluida com sucesso.")
print(f"Tabela: {TABELA_RAW}")
print(f"Linhas carregadas: {len(df)}")
print("Empresas 386 / 399 presentes:",
      sorted(set(df["companyId"].dropna().astype(int)) & {386, 399}))
print(df.head())
