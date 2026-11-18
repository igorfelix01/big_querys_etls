-- ####################################################################

-- TRUSTED.DB_PLAN_OBRAS  (a partir de raw.planejamento_obras)

--

-- Abre as listas JSON do Sienge:

--   plannedExecutions -> 1 linha por mes planejado

--                        (year, month, duration_1, plannedPercentage)

--   costItems         -> 1 linha por item de custo (sheetItemId, costRatio)

--

-- Day    = 1 (DataOrcamento = 1o dia do mes planejado)

-- ChaveObras     = S<subdominio>O<buildingId>U<buildingUnitId>ID<id>   (PQ)

-- ChaveObrasData = ChaveObras + mes<month> + ano<year>                 (PQ)

-- Orcado = totalPrice*plannedPercentage*costRatio/10000                 (PQ)

-- companyGroup / companyName / enterpriseName: dim_nome_companhias

--   (buildingId = enterpriseId)

--

-- Depois dele roda o db_plan_obras.sql (analytics.fato_plan_obras).

-- ####################################################################



-- Le a lista JSON mesmo se o raw veio no formato do Python

-- ([{'year': 2016, ...}] com aspas simples, None/True/False/NaN).

CREATE TEMP FUNCTION lista_json(x STRING) AS (

  COALESCE(

    JSON_QUERY_ARRAY(x),

    JSON_QUERY_ARRAY(

      REGEXP_REPLACE(

        REGEXP_REPLACE(

          REGEXP_REPLACE(

            REGEXP_REPLACE(REPLACE(x, "'", '"'), r'\bNone\b', 'null'),

          r'\bTrue\b', 'true'),

        r'\bFalse\b', 'false'),

      r'\bNaN\b', 'null')

    )

  )

);



CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.db_plan_obras` AS



WITH



nome_companhias AS (

  SELECT

    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,

    companyGroup,

    companyName,

    enterpriseName

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  WHERE enterpriseId IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (

    PARTITION BY SAFE_CAST(enterpriseId AS INT64)

    ORDER BY companyGroup, companyName, enterpriseName

  ) = 1

),



base AS (

  SELECT

    NULLIF(TRIM(subdominio), '')                          AS subdominio,

    SAFE_CAST(SAFE_CAST(buildingId AS FLOAT64) AS INT64)     AS buildingId,

    SAFE_CAST(SAFE_CAST(buildingUnitId AS FLOAT64) AS INT64) AS buildingUnitId,

    id,

    presentationId,

    description,

    level,

    SAFE_CAST(SUBSTR(startDate, 1, 10)  AS DATE)          AS startDate,

    SAFE_CAST(SUBSTR(finishDate, 1, 10) AS DATE)          AS finishDate,

    SAFE_CAST(duration AS FLOAT64)                        AS duration,

    summary,

    location,

    unitOfMeasure,

    SAFE_CAST(quantity   AS FLOAT64)                      AS quantity,

    SAFE_CAST(totalPrice AS FLOAT64)                      AS totalPrice,

    versionNumber,

    pricesByCategory,

    plannedExecutions,

    costItems

  FROM `dadosfinanceiro-501613.raw.planejamento_obras`

),



-- 1 linha por mes planejado

execucoes AS (

  SELECT

    b.* EXCEPT (plannedExecutions, costItems),

    b.costItems,

    SAFE_CAST(JSON_VALUE(e, '$.year')  AS INT64)              AS year,

    SAFE_CAST(JSON_VALUE(e, '$.month') AS INT64)              AS month,

    SAFE_CAST(JSON_VALUE(e, '$.duration') AS FLOAT64)         AS duration_1,

    SAFE_CAST(JSON_VALUE(e, '$.plannedPercentage') AS FLOAT64) AS plannedPercentage

  FROM base b,

  UNNEST(lista_json(b.plannedExecutions)) AS e

),



-- 1 linha por item de custo

itens AS (

  SELECT

    x.* EXCEPT (costItems),

    JSON_VALUE(c, '$.sheetItemId')                         AS sheetItemId,

    SAFE_CAST(JSON_VALUE(c, '$.costRatio') AS FLOAT64)     AS costRatio

  FROM execucoes x,

  UNNEST(lista_json(x.costItems)) AS c

)



SELECT

  i.subdominio,

  i.buildingId,

  i.buildingUnitId,

  i.id,

  i.presentationId,

  i.description,

  i.level,

  i.startDate,

  i.finishDate,

  i.duration,

  i.summary,

  i.location,

  i.unitOfMeasure,

  i.quantity,

  i.totalPrice,

  i.versionNumber,

  i.pricesByCategory,

  i.year,

  i.month,

  i.duration_1,

  i.plannedPercentage,

  i.sheetItemId,

  i.costRatio,

  nc.companyGroup,

  nc.companyName,

  nc.enterpriseName,

  -- igual ao PQ: "S"&subdominio&"O"&buildingId&"U"&buildingUnitId&"ID"&id

  CONCAT('S', IFNULL(i.subdominio, ''), 'O', IFNULL(CAST(i.buildingId AS STRING), ''),

         'U', IFNULL(CAST(i.buildingUnitId AS STRING), ''), 'ID', IFNULL(CAST(i.id AS STRING), ''))  AS ChaveObras,

  -- ChaveObras & "mes" & month & "ano" & year

  CONCAT('S', IFNULL(i.subdominio, ''), 'O', IFNULL(CAST(i.buildingId AS STRING), ''),

         'U', IFNULL(CAST(i.buildingUnitId AS STRING), ''), 'ID', IFNULL(CAST(i.id AS STRING), ''),

         'mes', IFNULL(CAST(i.month AS STRING), ''), 'ano', IFNULL(CAST(i.year AS STRING), ''))  AS ChaveObrasData,

  i.totalPrice * i.plannedPercentage * i.costRatio / 10000          AS Orcado,

  1                                                                  AS Day

FROM itens i

LEFT JOIN nome_companhias nc

  ON nc.enterpriseId = i.buildingId;