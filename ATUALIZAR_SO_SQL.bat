@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ================================================================
echo  ATUALIZAR SO OS SQLs (BigQuery) - nao baixa nada do Sienge
echo  Usa o raw que ja esta no BigQuery e recalcula todas as tabelas
echo ================================================================
python atualizar_tudo.py --so-sql
if errorlevel 1 (
  echo.
  echo Algum SQL falhou. Veja o log na pasta logs.
) else (
  echo.
  echo Pronto. No Looker: Atualizar dados.
)
pause
