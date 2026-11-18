#!/usr/bin/env bash
# Linux / EC2
cd "$(dirname "$0")"

# 1) pega a versao mais nova do GitHub (se esta pasta for um clone do git)
if [ -d .git ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] git pull (versao mais nova do GitHub)..."
  ANTES=$(git rev-parse HEAD 2>/dev/null)
  if git pull --ff-only; then
    DEPOIS=$(git rev-parse HEAD 2>/dev/null)
    if [ "$ANTES" != "$DEPOIS" ]; then
      echo "Atualizado: $ANTES -> $DEPOIS"
      git log --oneline "$ANTES..$DEPOIS" | head -20
      # bibliotecas novas no requirements.txt
      if git diff --name-only "$ANTES" "$DEPOIS" | grep -q requirements.txt && [ -d .venv ]; then
        .venv/bin/pip install -q -r requirements.txt
      fi
    else
      echo "Ja estava na versao mais nova."
    fi
  else
    echo "AVISO: git pull falhou - rodando com a versao que ja esta no EC2."
  fi
fi

# 2) roda a atualizacao
if [ -d .venv ]; then source .venv/bin/activate; fi
python3 atualizar_tudo.py "$@"
