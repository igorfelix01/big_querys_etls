#!/usr/bin/env bash
# Rodar UMA vez no EC2 (Linux), dentro da pasta AtualizacaoCompleta:
#   bash instalar_ec2.sh
# (com GitHub: veja GUIA_GITHUB_EC2.txt - o atualizar_tudo.sh faz git pull antes de rodar)
# Funciona em Ubuntu (apt) e Amazon Linux (dnf/yum).
set -e
cd "$(dirname "$0")"

echo ">> Instalando Python..."
if command -v apt-get >/dev/null; then
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y python3 python3-venv python3-pip >/dev/null
elif command -v dnf >/dev/null; then
  sudo dnf install -y python3 python3-pip >/dev/null
else
  sudo yum install -y python3 python3-pip >/dev/null
fi

echo ">> Criando ambiente (.venv) e instalando bibliotecas..."
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r requirements.txt

chmod +x atualizar_tudo.sh
mkdir -p logs
[ -f credencial_bigquery.json ] && chmod 600 credencial_bigquery.json

echo ">> Instalando as bibliotecas que os scripts do InserirDados usam..."
python3 conferir_ec2.py --instalar || true

# todo dia 05:00 de Brasilia = 08:00 UTC (o EC2 fica em UTC)
LINHA="0 8 * * * $(pwd)/atualizar_tudo.sh >> $(pwd)/logs/cron.log 2>&1"
( crontab -l 2>/dev/null | grep -v atualizar_tudo.sh ; echo "$LINHA" ) | crontab -

echo ""
echo "Instalado e agendado: todo dia 05:00 (Brasilia)."
echo "Conferir de novo:  .venv/bin/python conferir_ec2.py"
echo "Rodar agora:       ./atualizar_tudo.sh"
echo "So os SQLs:        ./atualizar_tudo.sh --so-sql"
