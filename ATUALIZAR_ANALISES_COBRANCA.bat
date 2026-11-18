@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ================================================================
echo  ATUALIZAR SO AS ANALISES NOVAS
echo  rolagem, regularizacao, renegociacao, concentracao, projecao de caixa
echo ================================================================
python atualizar_analises_cobranca.py
if errorlevel 1 (
  echo.
  echo Algum SQL falhou. Veja o log na pasta logs.
) else (
  echo.
  echo Pronto. No Looker: Atualizar dados.
)
pause
