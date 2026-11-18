@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ================================================================
echo  ATUALIZAR SO OS SQLs DAS RECEBIDAS (arruma o grafico mensal)
echo  Recebidas + tudo que depende delas (cerca de 50 SQLs)
echo  NAO rode enquanto a carga do Sienge estiver em andamento.
echo ================================================================
python executar_pipeline.py --sem-conferir-raw --a-partir-de Recebidas.sql GerarClassificarRecebidas.sql GerarRenegociacoes.sql
if errorlevel 1 (
  echo.
  echo Algum SQL falhou. Veja o log na pasta logs.
) else (
  echo.
  echo Pronto. No Looker: Atualizar dados.
)
pause
