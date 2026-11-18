-- ####################################################################
-- LOOKER_STUDIO.OBRAS_TABELA_CREDORES
-- Tabela de credores: Pagos / A Pagar por obra, credor, titulo e item.
-- Depende de: analytics.fato_pagas_obras (27_db_pagas_obras_transformacoes.sql)
-- ####################################################################

DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.obras_tabela_credores`;

CREATE OR REPLACE TABLE `dadosfinanceiro-501613.looker_studio.obras_tabela_credores`
CLUSTER BY companyName, enterpriseName, Credor
AS
WITH nome_companhias AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup,
    companyName,
    enterpriseName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  -- mesma escolha de empresa do planejamento e do avanco financeiro
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName, enterpriseName
  ) = 1
),

base AS (
  SELECT
    p.subdominio,
    p.buildingId,
    p.buildingUnitId,

    nc.companyGroup,
    nc.companyName,
    nc.enterpriseName,

    p.creditorId,
    p.creditorName AS Credor,

    p.billId,
    p.installmentId,

    p.costEstimationSheetId,
    p.costEstimationSheetName AS Descricao,

    p.documentIdentificationId,
    p.documentIdentificationName,
    p.documentNumber,

    p.paymentDate1,
    p.dueDate,
    p.paymentDate,

    p.valor_a_pagos,
    p.valor_a_pagar,
    p.Valor_Pago

  FROM `dadosfinanceiro-501613.analytics.fato_pagas_obras` p
  LEFT JOIN nome_companhias nc
    ON SAFE_CAST(p.buildingId AS INT64) = nc.enterpriseId
)

SELECT
  subdominio,
  buildingId,
  buildingUnitId,

  companyGroup,
  companyName,
  enterpriseName,

  creditorId,
  Credor,

  billId,
  costEstimationSheetId,
  Descricao,

  documentIdentificationId,
  documentIdentificationName,
  documentNumber,

  MIN(dueDate) AS menor_dueDate,
  MAX(dueDate) AS maior_dueDate,
  MIN(paymentDate1) AS menor_paymentDate1,
  MAX(paymentDate1) AS maior_paymentDate1,

  ROUND(SUM(IFNULL(valor_a_pagar, 0)), 2) AS A_Pagar,
  ROUND(SUM(IFNULL(valor_a_pagos, 0)), 2) AS Pagos,
  ROUND(SUM(IFNULL(Valor_Pago, 0)), 2) AS Valor_Pago,

  ROUND(SUM(IFNULL(valor_a_pagar, 0) + IFNULL(valor_a_pagos, 0)), 2) AS Total_Pago_A_Pagar,

  COUNT(*) AS linhas

FROM base
GROUP BY
  subdominio,
  buildingId,
  buildingUnitId,
  companyGroup,
  companyName,
  enterpriseName,
  creditorId,
  Credor,
  billId,
  costEstimationSheetId,
  Descricao,
  documentIdentificationId,
  documentIdentificationName,
  documentNumber;