-- ####################################################################
-- ANALYTICS.CLIENTE
-- Tabela usada pelo gerar_dashboard.py (dashboard de inadimplencia,
-- pasta "Contratos e Inadimplencia") para os filtros.
--
-- 1 linha por contrato (ChaveGeral), com:
--   costCenterId, groupCompanyName, subJudicie,
--   documentIdentificationId, Companhia
--
-- Origem: analytics.saldo_devedor (a mesma do HistoricoInadimplencia).
--   Se o contrato tem varias linhas, fica a mais recente
--   (A Receber primeiro, depois o maior vencimento).
-- Companhia: costCenterId -> dim_nome_companhias.enterpriseId -> companyName
--   (igual a ligacao de empresa do BI). Se nao achar, usa o companyName
--   do proprio saldo_devedor.
--
-- Depende de: analytics.saldo_devedor, analytics.dim_nome_companhias
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.analytics.Cliente`
AS

WITH

nome_companhias AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName
  ) = 1
),

contratos AS (
  SELECT
    ChaveGeral,
    SAFE_CAST(costCenterId AS INT64)   AS costCenterId,
    groupCompanyName,
    subJudicie,
    documentIdentificationId,
    companyName
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`
  WHERE ChaveGeral IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ChaveGeral
    ORDER BY IF(OrigemBase = 'A Receber', 0, 1), dueDate DESC
  ) = 1
)

SELECT
  c.ChaveGeral,
  c.costCenterId,
  c.groupCompanyName,
  c.subJudicie,
  c.documentIdentificationId,
  COALESCE(nc.companyName, c.companyName) AS Companhia
FROM contratos c
LEFT JOIN nome_companhias nc
  ON nc.enterpriseId = c.costCenterId;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- CONFERENCIA: 1 linha por contrato (as duas contagens iguais)
-- ####################################################################
-- SELECT
--   COUNT(*)                   AS linhas,
--   COUNT(DISTINCT ChaveGeral) AS contratos,
--   COUNTIF(Companhia IS NULL) AS sem_companhia
-- FROM `dadosfinanceiro-501613.analytics.Cliente`;