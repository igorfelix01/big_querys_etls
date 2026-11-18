# -*- coding: utf-8 -*-
"""
CONFERE NO BIGQUERY QUE OS SQLs OTIMIZADOS DAO O MESMO RESULTADO DOS ORIGINAIS

Rodar DEPOIS de uma atualizacao completa (com o raw do dia ja carregado):
    python conferir_igualdade.py --originais "C:\\...\\InserirDados\\considerarsomenteessessqls"

O que faz, para cada SQL original:
  1. roda o SQL ORIGINAL gravando as tabelas num dataset separado
     (dadosfinanceiro-501613.conferencia, apagado sozinho em 1 dia);
     as tabelas de entrada sao as de verdade (as mesmas que o otimizado usou);
  2. compara linha a linha com a tabela de verdade (feita pelo otimizado):
     quantidade de linhas + linhas que existem num e nao no outro.
  Nao altera nenhuma tabela de verdade.

Ficam de fora:
  - os SQLs em que a versao da automacao corrige a versao salva no BigQuery
    (lista VERSAO_DA_AUTOMACAO): a diferenca e esperada;
  - SQLs com SQL dinamico (EXECUTE IMMEDIATE / views).
Custo: le os mesmos dados de uma atualizacao (centavos de dolar).
"""
import argparse
import re
import sys
import time
from pathlib import Path

from google.cloud import bigquery

PROJECT = "dadosfinanceiro-501613"
LOCATION = "southamerica-east1"
DS_CONF = "conferencia"
PASTA = Path(__file__).resolve().parent

VERSAO_DA_AUTOMACAO = {
    "GerarClassificarRecebidas.sql", "GerarRenegociacoes.sql", "Nome_companhias.sql",
    "RiscoContratos.sql", "looker_renegociacao_base.sql", "obras_tabela_credores.sql",
    "db_perfomados.sql", "Saldo Devedor.sql", "Looker mapa estados.sql",
}

RE_ALVO = re.compile(r"(?is)\b(?:CREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE|VIEW)(?:\s+IF\s+NOT\s+EXISTS)?)\s+`"
                     + re.escape(PROJECT) + r"\.([\w]+)\.([\w]+)`")


def sem_comentarios(s):
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    return re.sub(r"--[^\n]*", " ", s)


def alvos(sql):
    return sorted({(d, t) for d, t in RE_ALVO.findall(sem_comentarios(sql))})


def reescrever(sql, tabs):
    for d, t in tabs:
        sql = re.sub(r"`" + re.escape(f"{PROJECT}.{d}.{t}") + r"`",
                     f"`{PROJECT}.{DS_CONF}.{d}__{t}`", sql, flags=re.I)
    return sql


def comparar(cli, d, t):
    real = f"`{PROJECT}.{d}.{t}`"
    conf = f"`{PROJECT}.{DS_CONF}.{d}__{t}`"
    q = f"""
    SELECT
      (SELECT COUNT(*) FROM {real}) AS n_real,
      (SELECT COUNT(*) FROM {conf}) AS n_orig,
      (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(x) j FROM {real} x
                             EXCEPT DISTINCT SELECT TO_JSON_STRING(y) FROM {conf} y)) AS so_real,
      (SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(y) j FROM {conf} y
                             EXCEPT DISTINCT SELECT TO_JSON_STRING(x) FROM {real} x)) AS so_orig
    """
    return list(cli.query(q, location=LOCATION).result())[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--originais", required=True, help="pasta com os SQLs originais")
    ap.add_argument("--so", nargs="*", help="so estes arquivos")
    a = ap.parse_args()

    cli = bigquery.Client(project=PROJECT, location=LOCATION)
    ds = bigquery.Dataset(f"{PROJECT}.{DS_CONF}")
    ds.location = LOCATION
    ds.default_table_expiration_ms = 24 * 3600 * 1000
    cli.create_dataset(ds, exists_ok=True)

    pacote = {}
    for f in (PASTA / "sql_bigquery").glob("*.sql"):
        for x in alvos(f.read_text(encoding="utf-8-sig")):
            pacote[x] = f.name

    ok, dif, pulados = [], [], []
    for f in sorted(Path(a.originais).glob("*.sql")):
        if a.so and f.name not in a.so:
            continue
        sql = f.read_text(encoding="utf-8-sig", errors="replace")
        tabs = alvos(sql)
        if not tabs:
            continue
        nome_pacote = pacote.get(tabs[0], f.name)
        if nome_pacote in VERSAO_DA_AUTOMACAO:
            pulados.append(f"{f.name} (versao da automacao corrige a salva)")
            continue
        if re.search(r"(?i)EXECUTE\s+IMMEDIATE|CREATE\s+(OR\s+REPLACE\s+)?VIEW", sem_comentarios(sql)):
            pulados.append(f"{f.name} (SQL dinamico/views)")
            continue
        print(f"\n> {f.name}: rodando original no dataset {DS_CONF} ...", flush=True)
        t0 = time.time()
        try:
            cli.query(reescrever(sql, tabs), location=LOCATION).result()
        except Exception as e:
            print(f"  nao rodou: {str(e)[:300]}")
            pulados.append(f"{f.name} (original nao rodou)")
            continue
        for d, t in tabs:
            try:
                r = comparar(cli, d, t)
            except Exception as e:
                print(f"  {d}.{t}: erro ao comparar: {str(e)[:200]}")
                dif.append(f"{d}.{t}")
                continue
            igual = r.n_real == r.n_orig and r.so_real == 0 and r.so_orig == 0
            print(f"  {'IGUAL   ' if igual else 'DIFERENTE'} {d}.{t}: linhas {r.n_real}/{r.n_orig} "
                  f"| so no otimizado {r.so_real} | so no original {r.so_orig} ({time.time()-t0:.0f}s)")
            (ok if igual else dif).append(f"{d}.{t}")

    print("\n" + "=" * 80)
    print(f"IGUAIS: {len(ok)} tabelas")
    print(f"DIFERENTES: {len(dif)} {dif}")
    print("Fora da conferencia:")
    for p in pulados:
        print("  -", p)
    print("Obs.: tabelas com valores decimais (FLOAT) somados em ordem diferente podem")
    print("      mostrar diferenca so na ultima casa decimal; isso e do BigQuery, nao da logica.")
    sys.exit(0 if not dif else 1)


if __name__ == "__main__":
    main()
