@echo off
chcp 65001 >nul
cd /d "%~dp0"
python atualizar_tudo.py %*
if errorlevel 1 (
  echo.
  echo Alguma etapa falhou. Veja o log na pasta logs.
)
