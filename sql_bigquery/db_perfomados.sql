-- ####################################################################
-- TRUSTED.DB_PERFOMADOS / ANALYTICS.DIM_PERFOMADOS
-- Origem: raw.db_perfomados (planilha, carregada pelo db_perfomados.py
-- do InserirDados).
--
-- Se a raw.db_perfomados NAO existir (planilha nao carregada / apagada
-- pela validade de 60 dias), este arquivo NAO da erro:
--   - mantem a dim_perfomados que ja existe; ou
--   - cria uma dim_perfomados VAZIA (com as colunas certas).
-- Assim as renegociacoes continuam rodando; so o campo StatusPerf
-- (filtro "Status Projeto") fica vazio ate a planilha voltar.
-- ####################################################################

IF EXISTS (
  SELECT 1
  FROM `dadosfinanceiro-501613.raw.INFORMATION_SCHEMA.TABLES`
  WHERE table_name = 'db_perfomados'
) THEN

  EXECUTE IMMEDIATE """
    CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.db_perfomados` AS
    SELECT
      CAST(companyId AS INT64) AS companyId,
      CAST(enterpriseId AS INT64) AS enterpriseId,
      CAST(companyGroup AS STRING) AS companyGroup,
      CAST(companyName AS STRING) AS companyName,
      CAST(projectName AS STRING) AS projectName,
      CAST(enterpriseName AS STRING) AS enterpriseName,
      CAST(StatusPerf AS STRING) AS StatusPerf
    FROM `dadosfinanceiro-501613.raw.db_perfomados`
  """;

  EXECUTE IMMEDIATE """
    CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_perfomados` AS
    SELECT
      companyId,
      enterpriseId,
      companyGroup,
      companyName,
      projectName,
      enterpriseName,
      StatusPerf
    FROM `dadosfinanceiro-501613.trusted.db_perfomados`
  """;

END IF;

-- sem a planilha: garante que as tabelas existem (vazias), para quem le
-- delas nao quebrar
CREATE TABLE IF NOT EXISTS `dadosfinanceiro-501613.trusted.db_perfomados` (
  companyId INT64,
  enterpriseId INT64,
  companyGroup STRING,
  companyName STRING,
  projectName STRING,
  enterpriseName STRING,
  StatusPerf STRING
);

CREATE TABLE IF NOT EXISTS `dadosfinanceiro-501613.analytics.dim_perfomados` (
  companyId INT64,
  enterpriseId INT64,
  companyGroup STRING,
  companyName STRING,
  projectName STRING,
  enterpriseName STRING,
  StatusPerf STRING
);
