CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.classificacao_bloko_niveis` AS

SELECT

  CAST(`Classificação Bloko` AS STRING) AS `Classificação Bloko`,

  CAST(`Tipo Classificação` AS STRING) AS `Tipo Classificação`,

  CAST(`Grupo Classificação` AS STRING) AS `Grupo Classificação`

FROM `dadosfinanceiro-501613.raw.classificacao_bloko_niveis`;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_classificacao_bloko_niveis` AS

SELECT

  `Classificação Bloko`,

  `Tipo Classificação`,

  `Grupo Classificação`

FROM `dadosfinanceiro-501613.trusted.classificacao_bloko_niveis`;