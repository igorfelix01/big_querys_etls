-- ####################################################################

-- ANALYTICS.FATO_PLAN_OBRAS  (a partir de trusted.db_plan_obras)

--

-- DataOrcamento = 1o dia do mes planejado (year, month, Day = 1)

-- Versao simples: sem particao, sem cluster e sem filtro

-- (a versao particionada criava a tabela vazia).

--

-- Depende de: trusted.db_plan_obras (planejamento_obras_transformacoes.sql)

-- ####################################################################



DROP TABLE IF EXISTS `dadosfinanceiro-501613.analytics.fato_plan_obras`;



CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_plan_obras` AS

SELECT

  subdominio,

  buildingId,

  buildingUnitId,

  id,

  presentationId,

  description,

  level,

  startDate,

  finishDate,

  duration,

  summary,

  location,

  unitOfMeasure,

  quantity,

  totalPrice,

  versionNumber,

  pricesByCategory,

  year,

  month,

  duration_1,

  plannedPercentage,

  sheetItemId,

  costRatio,

  companyGroup,

  companyName,

  enterpriseName,

  ChaveObras,

  ChaveObrasData,

  Orcado,

  Day,

  SAFE.DATE(SAFE_CAST(year AS INT64), SAFE_CAST(month AS INT64), SAFE_CAST(Day AS INT64)) AS DataOrcamento

FROM `dadosfinanceiro-501613.trusted.db_plan_obras`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA: tem que dar 21.045 linhas e orcado 42.535.496

-- ####################################################################

-- SELECT

--   COUNT(*)           AS linhas,

--   MIN(DataOrcamento) AS primeira_data,

--   MAX(DataOrcamento) AS ultima_data,

--   ROUND(SUM(Orcado)) AS orcado

-- FROM `dadosfinanceiro-501613.analytics.fato_plan_obras`;