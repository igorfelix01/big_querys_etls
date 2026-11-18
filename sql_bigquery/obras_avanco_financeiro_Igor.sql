-- ####################################################################

-- ANALYTICS.FATO_OBRAS_AVANCO_FINANCEIRO

--

-- Orcado (fato_plan_obras, mes do DataOrcamento)  x

-- Pago / A Pagar (fato_pagas_obras, mes do paymentDate1)

--

-- 1 linha por obra (subdominio + buildingId + buildingUnitId) x MES,

-- para TODOS os meses (do 1o mes da obra ate o ultimo mes da base),

-- mesmo sem movimento. Assim os acumulados continuam certos quando o

-- Looker soma varias obras no mesmo mes (igual ao acumulado do BI,

-- que soma desde o inicio ate o mes).

--

-- Mes sem movimento: Orcado/Pagos/A_Pagar ficam vazios (NULL) e os

-- acumulados repetem o ultimo valor.

--

-- SEM limite de periodo: filtro do Looker por MesReferencia.

-- Depende de: analytics.fato_plan_obras, analytics.fato_pagas_obras,

--             analytics.dim_nome_companhias

-- ####################################################################



DROP TABLE IF EXISTS `dadosfinanceiro-501613.analytics.fato_obras_avanco_financeiro`;-- [otimizacao] CTE 'base_mensal' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base_mensal AS
WITH
planejamento AS (

  SELECT

    DATE_TRUNC(DataOrcamento, MONTH)                  AS MesReferencia,

    subdominio,

    SAFE_CAST(buildingId AS INT64)                    AS buildingId,

    SAFE_CAST(buildingUnitId AS INT64)                AS buildingUnitId,

    SUM(CAST(Orcado AS FLOAT64))                      AS Orcado,

    CAST(NULL AS FLOAT64)                             AS Valor_Pago,

    CAST(NULL AS FLOAT64)                             AS Pagos,

    CAST(NULL AS FLOAT64)                             AS A_Pagar,

    CAST(NULL AS FLOAT64)                             AS Pago_A_Pagar

  FROM `dadosfinanceiro-501613.analytics.fato_plan_obras`

  WHERE DataOrcamento IS NOT NULL

  GROUP BY 1, 2, 3, 4

),

pagamento AS (

  SELECT

    DATE_TRUNC(paymentDate1, MONTH)                   AS MesReferencia,

    subdominio,

    SAFE_CAST(buildingId AS INT64)                    AS buildingId,

    SAFE_CAST(buildingUnitId AS INT64)                AS buildingUnitId,

    CAST(NULL AS FLOAT64)                             AS Orcado,

    SUM(CAST(Valor_Pago    AS FLOAT64))               AS Valor_Pago,

    SUM(CAST(valor_a_pagos AS FLOAT64))               AS Pagos,

    SUM(CAST(valor_a_pagar AS FLOAT64))               AS A_Pagar,

    SUM(IFNULL(CAST(valor_a_pagos AS FLOAT64), 0)

      + IFNULL(CAST(valor_a_pagar AS FLOAT64), 0))    AS Pago_A_Pagar

  FROM `dadosfinanceiro-501613.analytics.fato_pagas_obras`

  WHERE paymentDate1 IS NOT NULL

  GROUP BY 1, 2, 3, 4

),

base_unificada AS (

  SELECT * FROM planejamento

  UNION ALL

  SELECT * FROM pagamento

)
SELECT * FROM (


  SELECT

    MesReferencia,

    subdominio,

    buildingId,

    buildingUnitId,

    SUM(Orcado)        AS Orcado,

    SUM(Valor_Pago)    AS Valor_Pago,

    SUM(Pagos)         AS Pagos,

    SUM(A_Pagar)       AS A_Pagar,

    SUM(Pago_A_Pagar)  AS Pago_A_Pagar

  FROM base_unificada

  GROUP BY 1, 2, 3, 4


);





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_obras_avanco_financeiro` AS
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

ultimo_mes AS (

  SELECT MAX(MesReferencia) AS fim FROM base_mensal

),

grade AS (

  SELECT

    o.subdominio,

    o.buildingId,

    o.buildingUnitId,

    mes AS MesReferencia

  FROM (

    SELECT subdominio, buildingId, buildingUnitId, MIN(MesReferencia) AS inicio

    FROM base_mensal

    GROUP BY 1, 2, 3

  ) o

  CROSS JOIN ultimo_mes u

  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(o.inicio, u.fim, INTERVAL 1 MONTH)) AS mes

),

completa AS (

  SELECT

    g.MesReferencia,

    g.subdominio,

    g.buildingId,

    g.buildingUnitId,

    b.Orcado,

    b.Valor_Pago,

    b.Pagos,

    b.A_Pagar,

    b.Pago_A_Pagar

  FROM grade g

  LEFT JOIN base_mensal b

    ON  b.MesReferencia = g.MesReferencia

    AND b.subdominio IS NOT DISTINCT FROM g.subdominio

    AND b.buildingId IS NOT DISTINCT FROM g.buildingId

    AND b.buildingUnitId IS NOT DISTINCT FROM g.buildingUnitId

)
SELECT

  c.MesReferencia,

  EXTRACT(YEAR  FROM c.MesReferencia) AS Ano,

  EXTRACT(MONTH FROM c.MesReferencia) AS Mes,



  c.subdominio,

  c.buildingId,

  c.buildingUnitId,



  nc.companyGroup,

  nc.companyName,

  nc.enterpriseName,



  c.Orcado,

  c.Valor_Pago,

  c.Pagos,

  c.A_Pagar,

  c.Pago_A_Pagar,



  SUM(IFNULL(c.Orcado, 0)) OVER (

    PARTITION BY c.subdominio, c.buildingId, c.buildingUnitId

    ORDER BY c.MesReferencia

    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

  ) AS Acumulado_Orcado,



  SUM(IFNULL(c.Pago_A_Pagar, 0)) OVER (

    PARTITION BY c.subdominio, c.buildingId, c.buildingUnitId

    ORDER BY c.MesReferencia

    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

  ) AS Acumulado_Pago_A_Pagar



FROM completa c

LEFT JOIN nome_companhias nc

  ON nc.enterpriseId = c.buildingId;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA: acumulados de dez/2026 (somando todas as obras)

-- BI (com os filtros da pagina): Acum. Orcado 31.751.961,81

--                                Acum. Pago/A Pagar 49.962.738,43

--                                A Pagar dez/26 148.856,66

-- ####################################################################

-- SELECT

--   MesReferencia,

--   ROUND(SUM(A_Pagar), 2)                AS a_pagar,

--   ROUND(SUM(Acumulado_Orcado), 2)       AS acumulado_orcado,

--   ROUND(SUM(Acumulado_Pago_A_Pagar), 2) AS acumulado_pago_a_pagar

-- FROM `dadosfinanceiro-501613.analytics.fato_obras_avanco_financeiro`

-- WHERE MesReferencia = '2026-12-01'

-- GROUP BY MesReferencia;