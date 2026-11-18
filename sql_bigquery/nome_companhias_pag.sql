CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.nome_companhias_pag` AS

SELECT

  CAST(companyGroup AS STRING) AS companyGroup,

  CAST(companyId AS INT64) AS companyId,

  CAST(companyName AS STRING) AS companyName,

  CAST(projectName AS STRING) AS projectName

FROM `dadosfinanceiro-501613.raw.nome_companhias_pag`;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_nome_companhias_pag` AS

SELECT

  companyGroup,

  companyId,

  companyName,

  projectName

FROM `dadosfinanceiro-501613.trusted.nome_companhias_pag`;