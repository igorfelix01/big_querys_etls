@echo off
chcp 65001 >nul
set "ALVO=%~dp0ATUALIZAR_TUDO.bat"
set "PLAN=%~dp0ATUALIZAR_PLANILHAS_60_DIAS.bat"
schtasks /Create /SC DAILY /ST 05:00 /TN "Atualizacao Completa BigQuery" /TR "\"%ALVO%\"" /F
schtasks /Create /SC WEEKLY /D SUN /ST 06:00 /TN "Atualizacao Planilhas BigQuery" /TR "\"%PLAN%\" auto" /F
echo.
echo Pronto:
echo   - ATUALIZAR_TUDO roda todo dia as 05:00
echo   - ATUALIZAR_PLANILHAS_60_DIAS roda todo domingo as 06:00
echo     (assim as tabelas de planilha nunca passam de 60 dias)
pause
