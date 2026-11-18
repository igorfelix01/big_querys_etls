-- ####################################################################
-- ANALYTICS.DIM_NOME_COMPANHIAS  <-  raw.nome_companhias
--
-- raw.nome_companhias e carregada pelo nome_companhias.py (planilha
-- 9. BI\BI\Nome_Companhias.xlsx, tabela "Table1" - a MESMA do Power BI).
-- Antes este SQL lia trusted.nome_companhias, que nenhum processo
-- atualizava: empresas novas da planilha nao chegavam no Looker.
-- ####################################################################

CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_nome_companhias` AS
SELECT
  CAST(companyGroup   AS STRING) AS companyGroup,
  SAFE_CAST(companyId    AS INT64) AS companyId,
  CAST(companyName    AS STRING) AS companyName,
  CAST(projectName    AS STRING) AS projectName,
  SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
  CAST(enterpriseName AS STRING) AS enterpriseName
FROM `dadosfinanceiro-501613.raw.nome_companhias`;