DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.vendas_contratos_ativos`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.vendas_contratos_ativos`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY companyGroup

AS

WITH

nome_companhias AS (

  SELECT

    CAST(companyId AS STRING) AS companyId,

    companyGroup,

    companyName

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  WHERE companyId IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(companyId AS STRING) ORDER BY companyGroup) = 1

),

vendas AS (

  SELECT

    v.ChaveGeral,

    DATE_TRUNC(DATE(v.contractDate), MONTH) AS Mes,

    v.situation,

    CAST(v.value AS FLOAT64)                 AS value,

    -- DAX: Remanejos = IF(CONTAINSSTRING(cancellationReason, "remanejo"), "Remanejo", BLANK())

    IF(LOWER(CAST(v.cancellationReason AS STRING)) LIKE '%remanejo%',

       'Remanejo', NULL)                     AS Remanejos,

    SPLIT(v.ChaveGeral, '-')[SAFE_OFFSET(0)] AS companyId

  FROM `dadosfinanceiro-501613.analytics.fato_vendas` v

  WHERE v.contractDate IS NOT NULL

)

SELECT

  v.Mes,

  IFNULL(nc.companyGroup, 'Sem grupo') AS companyGroup,

  nc.companyName,



  -- Contagem de db_vendas[ChaveGeral] (nao distinta)

  COUNT(v.ChaveGeral) AS QtdContratos,



  -- Contagem de ContratosAtivos[ChaveGeral] (Emitido, distinto)

  COUNT(DISTINCT IF(v.situation = 'Emitido', v.ChaveGeral, NULL)) AS QtdContratosAtivos,



  -- VGV: Emitido e sem Remanejo

  ROUND(SUM(IF(

    v.situation = 'Emitido'

    AND NOT IFNULL(LOWER(v.Remanejos) LIKE '%remanejo%', FALSE),

    v.value, 0)), 2) AS VGV

FROM vendas v

LEFT JOIN nome_companhias nc

  ON nc.companyId = v.companyId

GROUP BY 1, 2, 3;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]




-- VALIDACAO

-- SELECT

--   Mes,

--   SUM(QtdContratos)       AS contratos,

--   SUM(QtdContratosAtivos) AS contratos_ativos,

--   ROUND(SUM(VGV), 2)      AS vgv

-- FROM `dadosfinanceiro-501613.looker_studio.vendas_contratos_ativos`

-- WHERE Mes >= '2025-08-01'

-- GROUP BY Mes

-- ORDER BY Mes;