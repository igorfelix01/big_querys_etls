"""
CONFERE SE O EC2 ESTA PRONTO PARA RODAR O atualizar_tudo.py

  python3 conferir_ec2.py            -> so confere
  python3 conferir_ec2.py --instalar -> confere e instala as bibliotecas
                                        que os scripts usam e estao faltando

O que ele olha:
  1. credencial do BigQuery (credencial_bigquery.json nesta pasta) e acesso
  2. pasta InserirDados e os scripts do Sienge / Obras
  3. bibliotecas que TODOS os .py usam (import ...) e nao estao instaladas
  4. Empreendimentos.xlsx (Obras)
  5. caminhos de Windows (C:\\...) escritos dentro dos scripts
Nao altera nenhum arquivo.
"""

import ast
import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

PASTA = Path(__file__).resolve().parent
BASE = PASTA if (PASTA / "InserirDados").exists() else PASTA.parent
INSERIR = BASE / "InserirDados"
PROJETO = "dadosfinanceiro-501613"
IGNORAR = {"Old", "old", "teste", "backup", "__pycache__", ".venv", "logs"}

# nome do import -> nome no pip
PIP = {
    "google.cloud.bigquery": "google-cloud-bigquery", "google.cloud": "google-cloud-bigquery",
    "google": "google-auth", "pandas_gbq": "pandas-gbq", "dateutil": "python-dateutil",
    "yaml": "pyyaml", "dotenv": "python-dotenv", "bs4": "beautifulsoup4",
    "sklearn": "scikit-learn", "PIL": "pillow", "win32com": None, "pythoncom": None,
    "pywintypes": None, "xlwings": None,
}
WINDOWS_ONLY = {"win32com", "pythoncom", "pywintypes", "xlwings", "winreg", "msvcrt"}

ok_geral = True


def titulo(t):
    print("\n" + "=" * 70 + f"\n{t}\n" + "=" * 70)


def falha(msg):
    global ok_geral
    ok_geral = False
    print(f"  [X] {msg}")


def certo(msg):
    print(f"  [ok] {msg}")


def scripts():
    for p in sorted(BASE.rglob("*.py")):
        if not (set(p.parts) & IGNORAR):
            yield p


def modulos_locais():
    """nomes de .py e pastas do projeto (import Credenciais etc.)"""
    nomes = set()
    for p in BASE.rglob("*"):
        if set(p.parts) & IGNORAR:
            continue
        if p.suffix == ".py":
            nomes.add(p.stem)
        elif p.is_dir():
            nomes.add(p.name)
    return nomes


def imports(p):
    try:
        arvore = ast.parse(p.read_text(encoding="utf-8", errors="ignore"))
    except SyntaxError:
        return set()
    achados = set()
    for n in ast.walk(arvore):
        if isinstance(n, ast.Import):
            achados |= {a.name for a in n.names}
        elif isinstance(n, ast.ImportFrom) and n.module and n.level == 0:
            achados.add(n.module)
    return achados


def existe(mod):
    try:
        return importlib.util.find_spec(mod) is not None
    except (ImportError, ValueError):
        return False


def main():
    instalar = "--instalar" in sys.argv

    # 1. credencial
    titulo("1. Credencial do BigQuery")
    cred = PASTA / "credencial_bigquery.json"
    if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
        certo(f"GOOGLE_APPLICATION_CREDENTIALS = {os.environ['GOOGLE_APPLICATION_CREDENTIALS']}")
    elif cred.exists():
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(cred)
        certo(f"achei {cred.name}")
        if os.name != "nt" and (cred.stat().st_mode & 0o077):
            print("      dica: proteja a chave ->  chmod 600 credencial_bigquery.json")
    else:
        falha(f"falta o credencial_bigquery.json em {PASTA}")
    try:
        from google.cloud import bigquery
        cli = bigquery.Client(project=PROJETO)
        t = cli.get_table(f"{PROJETO}.raw.areceber")
        certo(f"BigQuery OK (raw.areceber: {t.num_rows:,} linhas)")
    except Exception as e:
        falha(f"nao conectou no BigQuery: {str(e).splitlines()[0][:200]}")

    # 2. pastas e scripts
    titulo("2. Scripts do Sienge e de Obras")
    if INSERIR.exists():
        certo(f"pasta InserirDados: {INSERIR}")
    else:
        falha(f"nao achei a pasta InserirDados em {BASE} "
              "(copie a BigQuery_Financeiro inteira)")
    for nome in ["Atualizacao.py", "Obrasatt.py", "Credenciais.py",
                 "AtualizarVendasUnidades.py", "executar_pipeline.py"]:
        achado = next((p for p in scripts() if p.name == nome), None)
        certo(f"{nome}: {achado.relative_to(BASE)}") if achado else falha(f"nao achei {nome}")

    # 3. bibliotecas
    titulo("3. Bibliotecas usadas pelos scripts")
    locais = modulos_locais()
    faltando, so_windows = {}, {}
    for p in scripts():
        for mod in imports(p):
            raiz = mod.split(".")[0]
            if raiz in locais or raiz in sys.builtin_module_names:
                continue
            if raiz in WINDOWS_ONLY:
                so_windows.setdefault(raiz, set()).add(p.relative_to(BASE))
                continue
            alvo = mod if mod.startswith("google.") else raiz
            if not existe(alvo):
                faltando.setdefault(alvo, set()).add(p.relative_to(BASE))
    if not faltando:
        certo("todas instaladas")
    for mod, onde in sorted(faltando.items()):
        falha(f"falta '{mod}' (usado em: {', '.join(map(str, sorted(onde)[:3]))})")
    for mod, onde in sorted(so_windows.items()):
        print(f"  [!] '{mod}' so existe no Windows (Excel). Esses scripts nao rodam no EC2: "
              f"{', '.join(map(str, sorted(onde)[:3]))}")

    if faltando and instalar:
        pacotes = sorted({PIP.get(m, PIP.get(m.split('.')[0], m.split('.')[0]))
                          for m in faltando} - {None})
        print(f"\n  Instalando: {' '.join(pacotes)}")
        r = subprocess.run([sys.executable, "-m", "pip", "install", *pacotes])
        if r.returncode == 0:
            print("  Instalado. Rode de novo para conferir:  python3 conferir_ec2.py")
    elif faltando:
        print("\n  Para instalar o que falta:  python3 conferir_ec2.py --instalar")

    # 4. Empreendimentos.xlsx
    titulo("4. Planilha de Obras (Empreendimentos.xlsx)")
    achado = next((p for p in BASE.parent.rglob("Empreendimentos.xlsx")
                   if not (set(p.parts) & IGNORAR)), None)
    certo(str(achado)) if achado else falha(
        "nao achei Empreendimentos.xlsx (copie Bases_API/Obras/Empreendimentos.xlsx)")

    # 5. caminhos de Windows
    titulo("5. Caminhos de Windows dentro dos scripts")
    padrao = re.compile(r"""['"]([A-Za-z]:\\\\?[^'"]{3,})['"]""")
    achou = False
    for p in scripts():
        # pacote: os do pacote e as cargas do BI (puladas sozinhas no EC2)
        if p.parent == PASTA or "cargas_planilhas_BI" in p.parts:
            continue
        for i, linha in enumerate(p.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
            if linha.lstrip().startswith("#"):
                continue
            m = padrao.search(linha)
            if m:
                achou = True
                print(f"  [!] {p.relative_to(BASE)} linha {i}: {m.group(1)[:90]}")
    if not achou:
        certo("nenhum")
    else:
        print("      Esses caminhos nao existem no Linux: troque por caminho relativo "
              "ou pelo caminho do EC2.")

    titulo("RESULTADO")
    print("  PRONTO para rodar:  ./atualizar_tudo.sh" if ok_geral
          else "  Corrija os itens [X] acima e rode de novo.")
    sys.exit(0 if ok_geral else 1)


if __name__ == "__main__":
    main()
