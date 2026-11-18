CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.situacoes`

AS



SELECT

  SAFE_CAST(situationId AS INT64) AS situationId,

  CAST(`Descrição` AS STRING) AS `Descrição`,

  CAST(`Classificação Unidades` AS STRING)

    AS `Classificação Unidades`,

  CAST(`Classificação Distratos` AS STRING)

    AS `Classificação Distratos`



FROM

  `dadosfinanceiro-501613.raw.situacoes`;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.dim_situacoes`

AS



SELECT

  situationId,

  `Descrição`,

  `Classificação Unidades`,

  `Classificação Distratos`



FROM

  `dadosfinanceiro-501613.trusted.situacoes`;