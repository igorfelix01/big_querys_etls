"""
raw.distratos_controle_operacoes  <-  MESMA planilha que o Power BI usa

O Power BI (consulta Base_Distratos_Operacoes) le:
  ...\\9. BI\\BI\\DISTRATOS - CONTROLE OPERAÇOES.xlsx  -> aba "Base da dados"

Este Python so COPIA a planilha para o raw (tudo como texto, sem tratamento):
  - cabecalho = LINHA 9 da planilha (o PQ promove o cabecalho, pula 7 linhas
    e promove de novo)
  - 33 primeiras colunas (Column1 .. Column33). Da 34 em diante o PQ remove.
  - nomes sem acento/espaco (lista COLUNAS abaixo)
  - datas do Excel viram texto AAAA-MM-DD; numeros viram texto com ponto decimal

TODO o tratamento (tipos, Empresa.1, companyId, enterpriseId, remover
Column32, remover linhas em branco) fica no SQL:
  distratos_controle_operacoes_transformacoes.sql

Nao grava nada nas pastas: le uma copia temporaria e carrega no BigQuery.
"""

import shutil
import tempfile
import time
from datetime import date, datetime
from pathlib import Path

import pandas as pd
from openpyxl import load_workbook
from google.cloud import bigquery

# =========================
# CONFIGURACOES
# =========================

PROJECT_ID = "dadosfinanceiro-501613"
TABELA_RAW = f"{PROJECT_ID}.raw.distratos_controle_operacoes"

ARQUIVO_EXCEL = Path(
    r"C:\Users\CarolinaSeikoBiadola\Bloko Capital\Financeiro - Documentos"
    r"\Financeiro - Bloko Investimentos\9. BI\BI\DISTRATOS - CONTROLE OPERAÇOES.xlsx"
)
ABA = "Base da dados"
LINHA_CABECALHO = 9

# (nome no Power BI, nome no BigQuery) - mesma ordem da planilha
COLUNAS = [
    ("Column1",                     "Column1"),
    ("Column2",                     "Column2"),
    ("MÊS CANCELAMENTO",            "MES_CANCELAMENTO"),
    ("Data",                        "Data"),
    ("Título",                      "Titulo"),
    ("Documento",                   "Documento"),
    ("EMPREENDIMENTO",              "EMPREENDIMENTO"),
    ("Unidades",                    "Unidades"),
    ("VGV",                         "VGV"),
    ("Valor histórico do contrato", "Valor_historico_contrato"),
    ("V. pago pelo cliente",        "V_pago_pelo_cliente"),
    ("TITULO GERADO",               "TITULO_GERADO"),
    ("VALOR DISTRATO",              "VALOR_DISTRATO"),
    ("titulo a devolver",           "titulo_a_devolver"),
    ("Não programado",              "Nao_programado"),
    ("Modo devolução",              "Modo_devolucao"),
    ("Número de parcelas",          "Numero_de_parcelas"),
    ("Double check",                "Double_check"),
    ("Valor da parcela",            "Valor_da_parcela"),
    ("Data ínicio",                 "Data_inicio"),
    ("COND",                        "COND"),
    ("IPTU",                        "IPTU"),
    ("Cliente",                     "Cliente"),
    ("OBSERVAÇÃO",                  "OBSERVACAO"),
    ("TIPO DE CANCELAMENTO",        "TIPO_DE_CANCELAMENTO"),
    ("EMPRESA",                     "EMPRESA"),
    ("Empresa",                     "Empresa_1"),        # = "Empresa.1" do PQ (o BigQuery nao
                                                         #   aceita EMPRESA e Empresa juntos)
    ("Valor da parcela_1",          "Valor_da_parcela_1"),
    ("Ativa desembolso",            "Ativa_desembolso"),
    ("Termina desembolso",          "Termina_desembolso"),
    ("Double check_2",              "Double_check_2"),
    ("Column32",                    "Column32"),         # removida no SQL
    ("Column33",                    "Column33"),         # o PQ mantem
]


# =========================
# LEITURA (copia temporaria: funciona com o Excel aberto / OneDrive)
# =========================

def copia_temporaria(arquivo, tentativas=5):
    destino = Path(tempfile.mkdtemp(prefix="distratos_")) / arquivo.name
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


def para_texto(v):
    """Celula do Excel -> texto (sem tratamento de regra)."""
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d")
    if isinstance(v, date):
        return v.strftime("%Y-%m-%d")
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, float):
        return str(int(v)) if v.is_integer() else repr(v)
    return str(v)


copia = None
if not ARQUIVO_EXCEL.exists():
    raise FileNotFoundError(f"Planilha nao encontrada: {ARQUIVO_EXCEL}")

print(f"Lendo: {ARQUIVO_EXCEL} (aba '{ABA}', cabecalho na linha {LINHA_CABECALHO})")
copia = copia_temporaria(ARQUIVO_EXCEL)
try:
    wb = load_workbook(copia, data_only=True, read_only=True)
    if ABA not in wb.sheetnames:
        raise ValueError(f"Aba '{ABA}' nao encontrada. Abas: {wb.sheetnames}")
    n = len(COLUNAS)
    linhas = list(wb[ABA].iter_rows(min_row=LINHA_CABECALHO, max_col=n, values_only=True))
    wb.close()
finally:
    shutil.rmtree(copia.parent, ignore_errors=True)

# confere o cabecalho com o do Power BI (so avisa)
cabecalho = [("" if c is None else str(c).strip()) for c in linhas[0]]
for i, (nome_bi, _) in enumerate(COLUNAS):
    if nome_bi.startswith("Column"):
        continue
    esperado = nome_bi.replace("_1", "").replace("_2", "")
    lido = cabecalho[i] if i < len(cabecalho) else ""
    if lido.lower() != esperado.lower():
        print(f"AVISO: coluna {i + 1} na planilha = '{lido}', no BI = '{nome_bi}'")

dados = [[para_texto(v) for v in (list(l) + [None] * (n - len(l)))] for l in linhas[1:]]
df = pd.DataFrame(dados, columns=[c[1] for c in COLUNAS], dtype="object")
print(f"Linhas lidas (com as em branco; o SQL remove): {len(df):,}".replace(",", "."))

# =========================
# CARGA NO BIGQUERY (tudo texto)
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
