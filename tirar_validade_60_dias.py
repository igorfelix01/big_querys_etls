"""
Tira a validade de 60 dias dos datasets do BigQuery
(raw, trusted, analytics, looker_studio) e das tabelas que ja existem.

Uso (no terminal do VS Code, na pasta deste arquivo):
    python tirar_validade_60_dias.py
"""

from google.cloud import bigquery

PROJECT_ID = "dadosfinanceiro-501613"
DATASETS = ["raw", "trusted", "analytics", "looker_studio"]

client = bigquery.Client(project=PROJECT_ID)

for nome in DATASETS:
    print(f"\n=== {nome}")
    try:
        ds = client.get_dataset(f"{PROJECT_ID}.{nome}")
    except Exception as e:
        print(f"  ERRO ao abrir o dataset: {e}")
        continue

    print(f"  antes: tabela {ds.default_table_expiration_ms} ms | "
          f"particao {ds.default_partition_expiration_ms} ms")

    # 1) validade padrao do dataset (vale para as tabelas novas)
    try:
        ds.default_table_expiration_ms = None
        ds.default_partition_expiration_ms = None
        ds = client.update_dataset(
            ds, ["default_table_expiration_ms", "default_partition_expiration_ms"]
        )
        print(f"  depois: tabela {ds.default_table_expiration_ms} | "
              f"particao {ds.default_partition_expiration_ms}  -> OK")
    except Exception as e:
        print(f"  ERRO ao mudar o dataset: {e}")
        print("  (se falar em sandbox/billing: precisa ativar o faturamento do projeto)")
        continue

    # 2) validade das tabelas que ja existem
    alteradas = 0
    for item in client.list_tables(ds):
        try:
            t = client.get_table(item.reference)
            campos = []
            if t.expires is not None:
                t.expires = None
                campos.append("expires")
            if t.time_partitioning is not None and t.time_partitioning.expiration_ms:
                t.time_partitioning.expiration_ms = None
                campos.append("time_partitioning")
            if campos:
                client.update_table(t, campos)
                alteradas += 1
        except Exception as e:
            print(f"  ERRO na tabela {item.table_id}: {e}")
    print(f"  tabelas sem validade agora: {alteradas}")

print("\nPronto.")
