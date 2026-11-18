-- ####################################################################

-- TRUSTED.REPARCELAMENTO_ANALISE  +  ANALYTICS.FATO_REPARCELAMENTO_ANALISE

-- Correcao: as datas vinham VAZIAS (SAFE_CAST nao entendia o formato do

-- raw, ex.: '2025-05-14T00:00:00', '14/05/2025' ou numero em milissegundos).

-- Agora a funcao para_data() aceita todos esses formatos.

-- ####################################################################



CREATE TEMP FUNCTION para_data(v STRING) AS (

  COALESCE(

    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(TRIM(v), 1, 10)),

    SAFE.PARSE_DATE('%d/%m/%Y', SUBSTR(TRIM(v), 1, 10)),

    IF(REGEXP_CONTAINS(TRIM(v), r'^\d{13}$'),

       DATE(TIMESTAMP_MILLIS(SAFE_CAST(TRIM(v) AS INT64))), NULL),

    IF(REGEXP_CONTAINS(TRIM(v), r'^\d{10}$'),

       DATE(TIMESTAMP_SECONDS(SAFE_CAST(TRIM(v) AS INT64))), NULL),

    IF(REGEXP_CONTAINS(TRIM(v), r'^\d{16}$'),

       DATE(TIMESTAMP_MICROS(SAFE_CAST(TRIM(v) AS INT64))), NULL)

  )

);



CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.reparcelamento_analise` AS

WITH fonte AS (

  SELECT

    SAFE_CAST(billReceivableId AS INT64) AS billReceivableId,

    SAFE_CAST(company_id AS INT64) AS company_id,

    company_name,

    SAFE_CAST(costCenter_id AS INT64) AS costCenter_id,

    costCenter_name,

    SAFE_CAST(customer_id AS INT64) AS customer_id,

    customer_name,

    customer_document,

    para_data(CAST(emissionDate AS STRING)) AS emissionDate,

    para_data(CAST(lastRenegotiationDate AS STRING)) AS lastRenegotiationDate,

    para_data(CAST(correctionDate AS STRING)) AS correctionDate,

    document,

    SAFE_CAST(privateArea AS INT64) AS privateArea,

    para_data(CAST(oldestInstallmentDate AS STRING)) AS oldestInstallmentDate,

    revokedBillReceivableDate,

    SAFE_CAST(unit_id AS INT64) AS unit_id,

    unit_name,

    SAFE_CAST(installment_id AS INT64) AS installment_id,

    SAFE_CAST(annualCorrection AS BOOL) AS annualCorrection,

    SAFE_CAST(sentToScripturalCharge AS BOOL) AS sentToScripturalCharge,

    paymentTerms_id,

    paymentTerms_description,

    para_data(CAST(baseDate AS STRING)) AS baseDate,

    SAFE_CAST(originalValue AS INT64) AS originalValue,

    para_data(CAST(dueDate AS STRING)) AS dueDate,

    SAFE_CAST(indexerId AS INT64) AS indexerId,

    para_data(CAST(calculationDate AS STRING)) AS calculationDate,

    SAFE_CAST(currentBalance AS INT64) AS currentBalance,

    SAFE_CAST(currentBalanceWithAddition AS INT64) AS currentBalanceWithAddition,

    SAFE_CAST(generatedBillet AS BOOL) AS generatedBillet,

    SAFE_CAST(installmentSituation AS INT64) AS installmentSituation,

    installmentNumber,

    SAFE_CAST(receipt_days AS INT64) AS receipt_days,

    para_data(CAST(receipt_date AS STRING)) AS receipt_date,

    SAFE_CAST(receipt_value AS INT64) AS receipt_value,

    SAFE_CAST(receipt_extra AS INT64) AS receipt_extra,

    SAFE_CAST(receipt_discount AS INT64) AS receipt_discount,

    SAFE_CAST(receipt_netReceipt AS INT64) AS receipt_netReceipt,

    receipt_type,

    REPLACE(chave, '_', '-') AS ChaveGeral,

    manteve_adimplencia,

    tem_reparcelamento,

    para_data(CAST(ultima_data_reparcelamento AS STRING)) AS ultima_data_reparcelamento,

    status_pagamento,

    subdominio,

    CONCAT(subdominio, '-', CAST(customer_id AS STRING)) AS ChaveClientes

  FROM `dadosfinanceiro-501613.raw.reparcelamento_analise`

),



com_clientes AS (

  SELECT

    f.*,

    c.Telefone,

    c.CPF,

    c.CNPJ,

    c.Email

  FROM fonte f

  LEFT JOIN `dadosfinanceiro-501613.analytics.dim_clientes` c

    ON f.ChaveClientes = c.ChaveClientes

),



agrupado AS (

  SELECT

    ChaveGeral,

    MAX(ultima_data_reparcelamento) AS UltimaDataReparcelamento,

    MAX(costCenter_id) AS enterpriseId,

    MAX(ChaveClientes) AS ChaveClientes,

    MAX(customer_name) AS NomeCliente,

    MAX(Telefone) AS Telefone,

    MAX(CPF) AS CPF,

    MAX(CNPJ) AS CNPJ,

    MAX(Email) AS Email,

    MAX(unit_name) AS Unidade,

    MAX(company_id) AS companyId,

    'Sim' AS Reparcelamento

  FROM com_clientes

  GROUP BY ChaveGeral

),



com_cobranca AS (

  SELECT

    a.*,

    c.nuUnidadePrincipal AS Cobranca

  FROM agrupado a

  LEFT JOIN `dadosfinanceiro-501613.analytics.fato_cobranca3p` c

    ON a.ChaveGeral = c.Chave_recebidos

)



SELECT

  ChaveGeral,

  UltimaDataReparcelamento,

  enterpriseId,

  ChaveClientes,

  NomeCliente,

  Telefone,

  CPF,

  CNPJ,

  Email,

  Unidade,

  companyId,

  Reparcelamento,

  Cobranca

FROM com_cobranca

WHERE Cobranca IS NULL;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise` AS

SELECT *

FROM `dadosfinanceiro-501613.trusted.reparcelamento_analise`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA: a data do reparcelamento tem que vir preenchida

-- (se 'sem_data' continuar = total, me mande o 'exemplo_raw')

-- ####################################################################

-- SELECT

--   (SELECT COUNT(*) FROM `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise`) AS total,

--   (SELECT COUNTIF(UltimaDataReparcelamento IS NULL)

--      FROM `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise`)             AS sem_data,

--   (SELECT MIN(UltimaDataReparcelamento)

--      FROM `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise`)             AS data_min,

--   (SELECT MAX(UltimaDataReparcelamento)

--      FROM `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise`)             AS data_max,

--   (SELECT STRING_AGG(DISTINCT CAST(ultima_data_reparcelamento AS STRING), ' | ' LIMIT 5)

--      FROM `dadosfinanceiro-501613.raw.reparcelamento_analise`)                        AS exemplo_raw;