@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ================================================================
echo  PLANILHAS (tabelas que o BigQuery apaga com 60 dias) + SQLs
echo  db_perfomados, situacoes, classificacao, contas bancarias,
echo  cobranca 3P, nome companhias, reparcelamento, distratos...
echo ================================================================
python atualizar_tudo.py --so-planilhas
if errorlevel 1 (
  echo.
  echo Alguma etapa falhou. Veja o log na pasta logs.
) else (
  echo.
  echo Pronto. No Looker: Atualizar dados.
)
if /i not "%~1"=="auto" pause
