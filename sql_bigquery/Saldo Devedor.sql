-- ####################################################################
-- SALDO DEVEDOR
--
-- FONTES:
-- dadosfinanceiro-501613.raw.areceber          (dados_recebidos.csv)
-- dadosfinanceiro-501613.analytics.fato_recebidas   (= db_recebidas)
-- dadosfinanceiro-501613.analytics.fato_vendas      (= db_vendas)
-- dadosfinanceiro-501613.analytics.dim_unidades     (= db_unidades)
--
-- FIEL AO POWER QUERY: SaldoDevedor (= saldo_devedor_Bi)
--   A Receber:
--     - interestRate / 10000
--     - situacaoInicialAR: <=31 Adimplente / <=90 Atrasado / Inadimplente
--     - correctedBalanceAmount -> ValorBruto (coluna correctedBalanceAmount
--       fica NULL nas linhas A Receber)
--     - dueDate -> paymentDate (dueDate fica NULL e depois recebe
--       paymentDate pelo actualDueDate)
--     - OrigemBase = 'A Receber'
--   Recebidas: OrigemBase = NULL (no PQ so o A Receber recebe OrigemBase)
--   Append por NOME de coluna (Table.Combine): coluna ausente = NULL
--   Remove: paymentYear, paymentMonth, dueYear, dueMonth, businessAreaId,
--           businessAreaName, groupCompanyId, installmentId,
--           documentForecast, originId, defaulterSituation,
--           sequencialNumber
--   dueDate = COALESCE(dueDate, paymentDate); anos/meses recalculados
--   LEFT JOIN vendas e unidades SEM deduplicar (igual PQ)
--   percentual NULL -> 1
-- ####################################################################


CREATE TEMP FUNCTION br_num(valor STRING) AS (
  CASE
    WHEN valor IS NULL
      OR TRIM(valor) = ''
    THEN NULL

    WHEN REGEXP_CONTAINS(
      TRIM(valor),
      r','
    )
    THEN SAFE_CAST(
      REPLACE(
        REPLACE(
          REPLACE(
            TRIM(valor),
            '.',
            ''
          ),
          ',',
          '.'
        ),
        ' ',
        ''
      )
      AS NUMERIC
    )

    ELSE SAFE_CAST(
      REPLACE(
        TRIM(valor),
        ' ',
        ''
      )
      AS NUMERIC
    )
  END
);


CREATE TEMP FUNCTION br_int(valor STRING) AS (
  SAFE_CAST(
    br_num(valor)
    AS INT64
  )
);


DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.analytics.saldo_devedor`;


CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.analytics.saldo_devedor`
AS

WITH


-- ====================================================================
-- 1. A RECEBER - LINHA EM JSON
-- (tolera coluna ausente / diferenca de maiusculas no raw)
-- ====================================================================

raw_a_receber AS (

  SELECT
    -- JSON nativo: o texto e lido UMA vez por linha (antes, cada um dos
    -- ~80 JSON_VALUE relia a linha inteira em texto -> muito mais lento)
    TO_JSON(t, stringify_wide_numbers => TRUE) AS linha_json

  FROM
    `dadosfinanceiro-501613.raw.areceber` AS t

),


-- ====================================================================
-- 2. A RECEBER - EXTRAI OS 47 CAMPOS COMO TEXTO (uma vez so)
--
-- PQ: remove projectId, projectName, holdingId, holdingName,
--     subsidiaryId, subsidiaryName, businessTypeId, businessTypeName
--     (nao sao extraidos)
-- ====================================================================

a_receber_txt AS (

  SELECT
    COALESCE(JSON_VALUE(linha_json, '$.ChaveEspecifica'),            JSON_VALUE(linha_json, '$.chaveespecifica'))            AS ChaveEspecifica,
    COALESCE(JSON_VALUE(linha_json, '$.subdominio'),                 JSON_VALUE(linha_json, '$.subDominio'))                 AS subdominio,
    COALESCE(JSON_VALUE(linha_json, '$.companyId'),                  JSON_VALUE(linha_json, '$.companyid'))                  AS companyId,
    COALESCE(JSON_VALUE(linha_json, '$.companyName'),                JSON_VALUE(linha_json, '$.companyname'))                AS companyName,
    COALESCE(JSON_VALUE(linha_json, '$.groupCompanyName'),           JSON_VALUE(linha_json, '$.groupcompanyname'))           AS groupCompanyName,
    COALESCE(JSON_VALUE(linha_json, '$.clientId'),                   JSON_VALUE(linha_json, '$.clientid'))                   AS clientId,
    COALESCE(JSON_VALUE(linha_json, '$.clientName'),                 JSON_VALUE(linha_json, '$.clientname'))                 AS clientName,
    COALESCE(JSON_VALUE(linha_json, '$.billId'),                     JSON_VALUE(linha_json, '$.billid'))                     AS billId,
    COALESCE(JSON_VALUE(linha_json, '$.documentIdentificationId'),   JSON_VALUE(linha_json, '$.documentidentificationid'))   AS documentIdentificationId,
    COALESCE(JSON_VALUE(linha_json, '$.documentIdentificationName'), JSON_VALUE(linha_json, '$.documentidentificationname')) AS documentIdentificationName,
    COALESCE(JSON_VALUE(linha_json, '$.documentNumber'),             JSON_VALUE(linha_json, '$.documentnumber'))             AS documentNumber,
    COALESCE(JSON_VALUE(linha_json, '$.originalAmount'),             JSON_VALUE(linha_json, '$.originalamount'))             AS originalAmount,
    COALESCE(JSON_VALUE(linha_json, '$.discountAmount'),             JSON_VALUE(linha_json, '$.discountamount'))             AS discountAmount,
    COALESCE(JSON_VALUE(linha_json, '$.taxAmount'),                  JSON_VALUE(linha_json, '$.taxamount'))                  AS taxAmount,
    COALESCE(JSON_VALUE(linha_json, '$.indexerId'),                  JSON_VALUE(linha_json, '$.indexerid'))                  AS indexerId,
    COALESCE(JSON_VALUE(linha_json, '$.indexerName'),                JSON_VALUE(linha_json, '$.indexername'))                AS indexerName,
    COALESCE(JSON_VALUE(linha_json, '$.dueDate'),                    JSON_VALUE(linha_json, '$.duedate'))                    AS dueDate,
    COALESCE(JSON_VALUE(linha_json, '$.issueDate'),                  JSON_VALUE(linha_json, '$.issuedate'))                  AS issueDate,
    COALESCE(JSON_VALUE(linha_json, '$.billDate'),                   JSON_VALUE(linha_json, '$.billdate'))                   AS billDate,
    COALESCE(JSON_VALUE(linha_json, '$.installmentBaseDate'),        JSON_VALUE(linha_json, '$.installmentbasedate'))        AS installmentBaseDate,
    COALESCE(JSON_VALUE(linha_json, '$.balanceAmount'),              JSON_VALUE(linha_json, '$.balanceamount'))              AS balanceAmount,
    COALESCE(JSON_VALUE(linha_json, '$.correctedBalanceAmount'),     JSON_VALUE(linha_json, '$.correctedbalanceamount'))     AS correctedBalanceAmount,
    COALESCE(JSON_VALUE(linha_json, '$.periodicityType'),            JSON_VALUE(linha_json, '$.periodicitytype'))            AS periodicityType,
    COALESCE(JSON_VALUE(linha_json, '$.embeddedInterestAmount'),     JSON_VALUE(linha_json, '$.embeddedinterestamount'))     AS embeddedInterestAmount,
    COALESCE(JSON_VALUE(linha_json, '$.interestType'),               JSON_VALUE(linha_json, '$.interesttype'))               AS interestType,
    COALESCE(JSON_VALUE(linha_json, '$.interestRate'),               JSON_VALUE(linha_json, '$.interestrate'))               AS interestRate,
    COALESCE(JSON_VALUE(linha_json, '$.correctionType'),             JSON_VALUE(linha_json, '$.correctiontype'))             AS correctionType,
    COALESCE(JSON_VALUE(linha_json, '$.interestBaseDate'),           JSON_VALUE(linha_json, '$.interestbasedate'))           AS interestBaseDate,
    COALESCE(JSON_VALUE(linha_json, '$.subJudicie'),                 JSON_VALUE(linha_json, '$.subjudicie'))                 AS subJudicie,
    COALESCE(JSON_VALUE(linha_json, '$.mainUnit'),                   JSON_VALUE(linha_json, '$.mainunit'))                   AS mainUnit,
    COALESCE(JSON_VALUE(linha_json, '$.installmentNumber'),          JSON_VALUE(linha_json, '$.installmentnumber'))          AS installmentNumber,
    COALESCE(JSON_VALUE(linha_json, '$.paymentTerm_id'),             JSON_VALUE(linha_json, '$.paymentterm_id'))             AS paymentTerm_id,
    COALESCE(JSON_VALUE(linha_json, '$.paymentTerm_descrition'),     JSON_VALUE(linha_json, '$.paymentterm_descrition'))     AS paymentTerm_descrition,
    COALESCE(JSON_VALUE(linha_json, '$.costCenterId'),               JSON_VALUE(linha_json, '$.costcenterid'))               AS costCenterId,
    COALESCE(JSON_VALUE(linha_json, '$.costCenterName'),             JSON_VALUE(linha_json, '$.costcentername'))             AS costCenterName,
    COALESCE(JSON_VALUE(linha_json, '$.financialCategoryId'),        JSON_VALUE(linha_json, '$.financialcategoryid'))        AS financialCategoryId,
    COALESCE(JSON_VALUE(linha_json, '$.financialCategoryName'),      JSON_VALUE(linha_json, '$.financialcategoryname'))      AS financialCategoryName,
    COALESCE(JSON_VALUE(linha_json, '$.financialCategoryReducer'),   JSON_VALUE(linha_json, '$.financialcategoryreducer'))   AS financialCategoryReducer,
    COALESCE(JSON_VALUE(linha_json, '$.financialCategoryType'),      JSON_VALUE(linha_json, '$.financialcategorytype'))      AS financialCategoryType,
    COALESCE(JSON_VALUE(linha_json, '$.financialCategoryRate'),      JSON_VALUE(linha_json, '$.financialcategoryrate'))      AS financialCategoryRate

    -- businessAreaId, businessAreaName, groupCompanyId, installmentId,
    -- documentForecast, originId, defaulterSituation: removidos no PQ
    -- depois do append -> nao precisam ser extraidos

  FROM
    raw_a_receber

),


-- ====================================================================
-- 3. A RECEBER - TIPAGEM (Changed Type do PQ)
-- ====================================================================

a_receber_tipado AS (

  SELECT
    CAST(ChaveEspecifica AS STRING)          AS ChaveEspecifica,
    CAST(subdominio AS STRING)               AS subdominio,
    br_int(companyId)                        AS companyId,
    CAST(companyName AS STRING)              AS companyName,
    CAST(groupCompanyName AS STRING)         AS groupCompanyName,
    br_int(clientId)                         AS clientId,
    CAST(clientName AS STRING)               AS clientName,
    billId                                   AS billId_raw,
    br_int(billId)                           AS billId,
    CAST(documentIdentificationId AS STRING) AS documentIdentificationId,
    CAST(documentIdentificationName AS STRING) AS documentIdentificationName,
    CAST(documentNumber AS STRING)           AS documentNumber,
    br_num(originalAmount)                   AS originalAmount,
    br_num(discountAmount)                   AS discountAmount,
    br_num(taxAmount)                        AS taxAmount,
    br_num(indexerId)                        AS indexerId,
    CAST(indexerName AS STRING)              AS indexerName,
    SAFE_CAST(dueDate AS DATE)               AS dueDate,
    SAFE_CAST(issueDate AS DATE)             AS issueDate,
    SAFE_CAST(billDate AS DATE)              AS billDate,
    SAFE_CAST(installmentBaseDate AS DATE)   AS installmentBaseDate,
    br_num(balanceAmount)                    AS balanceAmount,
    br_num(correctedBalanceAmount)           AS correctedBalanceAmount,
    CAST(periodicityType AS STRING)          AS periodicityType,
    br_num(embeddedInterestAmount)           AS embeddedInterestAmount,
    CAST(interestType AS STRING)             AS interestType,
    br_num(interestRate)                     AS interestRate,
    CAST(correctionType AS STRING)           AS correctionType,
    SAFE_CAST(interestBaseDate AS DATE)      AS interestBaseDate,
    CAST(subJudicie AS STRING)               AS subJudicie,
    CAST(mainUnit AS STRING)                 AS mainUnit,
    CAST(installmentNumber AS STRING)        AS installmentNumber,
    CAST(paymentTerm_id AS STRING)           AS paymentTerm_id,
    CAST(paymentTerm_descrition AS STRING)   AS paymentTerm_descrition,
    br_int(costCenterId)                     AS costCenterId,
    CAST(costCenterName AS STRING)           AS costCenterName,
    br_int(financialCategoryId)              AS financialCategoryId,
    CAST(financialCategoryName AS STRING)    AS financialCategoryName,
    CAST(financialCategoryReducer AS STRING) AS financialCategoryReducer,
    CAST(financialCategoryType AS STRING)    AS financialCategoryType,
    br_num(financialCategoryRate)            AS financialCategoryRate

  FROM
    a_receber_txt

),


-- ====================================================================
-- 4. A RECEBER - REMOVER ERROS DE BILLID
-- remove so billId preenchido que nao converteu
-- (billId vazio vira null no PQ e a linha fica)
-- ====================================================================

a_receber_sem_erro AS (

  SELECT
    * EXCEPT (billId_raw)

  FROM
    a_receber_tipado

  WHERE
    NOT (
      billId_raw IS NOT NULL
      AND TRIM(billId_raw) <> ''
      AND billId IS NULL
    )

),


-- ====================================================================
-- 5. A RECEBER - TRANSFORMACOES DO SALDODEVEDOR
--    e colunas na estrutura do append
-- ====================================================================

a_receber_origem AS (

  SELECT

    subdominio,
    companyId,
    companyName,
    groupCompanyName,
    clientId,
    clientName,
    billId,
    documentIdentificationId,
    documentIdentificationName,
    documentNumber,

    CAST(NULL AS INT64)   AS operationTypeId,
    CAST(NULL AS STRING)  AS operationTypeName,

    issueDate,
    billDate,

    -- PQ: dueDate renomeado para paymentDate
    dueDate               AS paymentDate,
    CAST(NULL AS DATE)    AS dueDate,

    installmentBaseDate,
    interestBaseDate,
    CAST(NULL AS DATE)    AS calculationDate,

    originalAmount,
    discountAmount,
    taxAmount,
    balanceAmount,

    -- PQ: correctedBalanceAmount renomeado para ValorBruto
    CAST(NULL AS NUMERIC) AS correctedBalanceAmount,
    embeddedInterestAmount,
    correctedBalanceAmount AS ValorBruto,

    CAST(NULL AS NUMERIC) AS grossAmount,
    CAST(NULL AS NUMERIC) AS monetaryCorrectionAmount,
    CAST(NULL AS NUMERIC) AS interestAmount,
    CAST(NULL AS NUMERIC) AS fineAmount,
    CAST(NULL AS NUMERIC) AS discountAmount_recepts,
    CAST(NULL AS NUMERIC) AS taxAmount_recepts,
    CAST(NULL AS NUMERIC) AS additionAmount,
    CAST(NULL AS NUMERIC) AS insuranceAmount,
    CAST(NULL AS NUMERIC) AS dueAdmAmount,

    -- PQ SaldoDevedor: / 10000
    interestRate / 10000  AS interestRate,

    interestType,
    correctionType,
    periodicityType,
    indexerId,
    indexerName,

    CAST(NULL AS INT64)   AS indexerId_recepts,
    CAST(NULL AS INT64)   AS embeddedInterestAmount_recepts,
    CAST(NULL AS INT64)   AS proRata,

    paymentTerm_id,
    paymentTerm_descrition,
    installmentNumber,

    CAST(NULL AS NUMERIC) AS ParcelaRecebida,
    CAST(NULL AS NUMERIC) AS TotalParcelas,

    costCenterId,
    costCenterName,
    financialCategoryId,
    financialCategoryName,
    financialCategoryReducer,
    financialCategoryType,
    financialCategoryRate,

    subJudicie,
    mainUnit,

    CAST(NULL AS INT64)   AS accountCompanyId,
    CAST(NULL AS STRING)  AS accountNumber,
    CAST(NULL AS STRING)  AS accountType,
    CAST(NULL AS STRING)  AS Conta,

    ChaveEspecifica,

    ARRAY_TO_STRING(
      [
        CAST(companyId AS STRING),
        CAST(billId AS STRING)
      ],
      '-'
    ) AS ChaveGeral,

    ARRAY_TO_STRING(
      [
        CAST(companyId AS STRING),
        CAST(costCenterId AS STRING),
        mainUnit
      ],
      '-'
    ) AS ChaveEmpreendimentoLote,

    DATE_DIFF(
      CURRENT_DATE('America/Sao_Paulo'),
      dueDate,
      DAY
    ) AS atrasoDias,

    -- PQ SaldoDevedor: <= 31 / <= 90
    CASE
      WHEN dueDate IS NULL
      THEN NULL

      WHEN DATE_DIFF(
        CURRENT_DATE('America/Sao_Paulo'),
        dueDate,
        DAY
      ) <= 31
      THEN 'Adimplente'

      WHEN DATE_DIFF(
        CURRENT_DATE('America/Sao_Paulo'),
        dueDate,
        DAY
      ) <= 90
      THEN 'Atrasado'

      ELSE 'Inadimplente'
    END AS situacaoInicialAR,

    'A Receber' AS OrigemBase

  FROM
    a_receber_sem_erro

),


-- ====================================================================
-- 6. RECEBIDAS (db_recebidas) NA MESMA ESTRUTURA
-- colunas removidas no PQ nao entram
-- ====================================================================

recebidas_origem AS (

  SELECT

    subdominio,
    companyId,
    companyName,
    groupCompanyName,
    clientId,
    clientName,
    billId,
    documentIdentificationId,
    documentIdentificationName,
    documentNumber,

    operationTypeId,
    operationTypeName,

    issueDate,
    billDate,

    paymentDate,
    dueDate,

    installmentBaseDate,
    interestBaseDate,
    calculationDate,

    originalAmount,
    discountAmount,
    taxAmount,
    balanceAmount,

    correctedBalanceAmount,
    embeddedInterestAmount,
    ValorBruto,

    grossAmount,
    monetaryCorrectionAmount,
    interestAmount,
    fineAmount,
    discountAmount_recepts,
    taxAmount_recepts,
    additionAmount,
    insuranceAmount,
    dueAdmAmount,

    interestRate,

    interestType,
    correctionType,
    periodicityType,
    indexerId,
    indexerName,

    indexerId_recepts,
    embeddedInterestAmount_recepts,
    proRata,

    paymentTerm_id,
    paymentTerm_descrition,
    installmentNumber,

    CAST(ParcelaRecebida AS NUMERIC) AS ParcelaRecebida,
    CAST(TotalParcelas AS NUMERIC)   AS TotalParcelas,

    costCenterId,
    costCenterName,
    financialCategoryId,
    financialCategoryName,
    financialCategoryReducer,
    financialCategoryType,
    CAST(financialCategoryRate AS NUMERIC) AS financialCategoryRate,

    subJudicie,
    mainUnit,

    accountCompanyId,
    accountNumber,
    accountType,
    Conta,

    ChaveEspecifica,
    ChaveGeral,
    ChaveEmpreendimentoLote,

    CAST(NULL AS INT64)  AS atrasoDias,
    CAST(NULL AS STRING) AS situacaoInicialAR,

    -- PQ: OrigemBase so existe no A Receber -> NULL aqui
    CAST(NULL AS STRING) AS OrigemBase

  FROM
    `dadosfinanceiro-501613.analytics.fato_recebidas`

),


-- ====================================================================
-- 7. APPEND A RECEBER + RECEBIDAS
-- ====================================================================

saldo_base AS (

  SELECT * FROM a_receber_origem

  UNION ALL

  SELECT * FROM recebidas_origem

),


-- ====================================================================
-- 8. actualDueDate + ANOS/MESES + CHAVE CLIENTES
--
-- PQ: dueDate = if dueDate = null then paymentDate else dueDate
--     paymentYear/Month de paymentDate; dueYear/Month de dueDate
--     ChaveClientes = subdominio-clientId
-- ====================================================================

saldo_ajustado AS (

  SELECT
    * EXCEPT (dueDate),

    COALESCE(dueDate, paymentDate) AS dueDate,

    EXTRACT(YEAR  FROM paymentDate)                    AS paymentYear,
    EXTRACT(MONTH FROM paymentDate)                    AS paymentMonth,
    EXTRACT(YEAR  FROM COALESCE(dueDate, paymentDate)) AS dueYear,
    EXTRACT(MONTH FROM COALESCE(dueDate, paymentDate)) AS dueMonth,

    ARRAY_TO_STRING(
      [
        subdominio,
        CAST(clientId AS STRING)
      ],
      '-'
    ) AS ChaveClientes

  FROM
    saldo_base

),


-- ====================================================================
-- 9. MERGE VENDAS (LEFT JOIN db_vendas on ChaveGeral, sem deduplicar)
-- ====================================================================

saldo_com_vendas AS (

  SELECT

    s.*,

    v.receivableBillId,
    v.cancellationPayableBillId,
    v.contractDate,
    v.value,
    v.totalSellingValue,
    v.cancellationDate

  FROM
    saldo_ajustado AS s

  LEFT JOIN
    `dadosfinanceiro-501613.analytics.fato_vendas` AS v

    ON s.ChaveGeral = v.ChaveGeral

),


-- ====================================================================
-- 10. MERGE UNIDADES (LEFT JOIN db_unidades, sem deduplicar)
--     percentual NULL -> 1
-- ====================================================================

saldo_com_unidades AS (

  SELECT

    sv.*,

    u.situationId,

    IFNULL(
      SAFE_CAST(u.percentual AS NUMERIC),
      NUMERIC '1'
    ) AS percentual

  FROM
    saldo_com_vendas AS sv

  LEFT JOIN
    `dadosfinanceiro-501613.analytics.dim_unidades` AS u

    ON sv.ChaveEmpreendimentoLote = u.ChaveEmpreendimentoLote

)


-- ====================================================================
-- 11. RESULTADO FINAL
-- ====================================================================

SELECT

  subdominio,

  companyId,
  companyName,

  groupCompanyName,

  clientId,
  clientName,

  billId,

  documentIdentificationId,
  documentIdentificationName,
  documentNumber,

  operationTypeId,
  operationTypeName,

  issueDate,
  billDate,

  paymentDate,
  dueDate,

  installmentBaseDate,
  interestBaseDate,
  calculationDate,

  grossAmount,
  monetaryCorrectionAmount,
  interestAmount,
  fineAmount,
  discountAmount,
  taxAmount,
  discountAmount_recepts,
  taxAmount_recepts,
  additionAmount,
  insuranceAmount,
  dueAdmAmount,

  ValorBruto,

  originalAmount,
  balanceAmount,
  correctedBalanceAmount,
  embeddedInterestAmount,

  interestRate,
  interestType,
  correctionType,
  periodicityType,

  indexerId,
  indexerName,
  indexerId_recepts,
  embeddedInterestAmount_recepts,
  proRata,

  paymentTerm_id,
  paymentTerm_descrition,

  installmentNumber,
  ParcelaRecebida,
  TotalParcelas,

  accountCompanyId,
  accountNumber,
  accountType,
  Conta,

  costCenterId,
  costCenterName,

  financialCategoryId,
  financialCategoryName,
  financialCategoryReducer,
  financialCategoryType,
  financialCategoryRate,

  subJudicie,

  mainUnit,

  ChaveGeral,
  ChaveEmpreendimentoLote,
  ChaveClientes,
  ChaveEspecifica,

  paymentYear,
  paymentMonth,

  dueYear,
  dueMonth,

  atrasoDias,
  situacaoInicialAR,

  OrigemBase,

  receivableBillId,
  cancellationPayableBillId,

  contractDate,

  value,
  totalSellingValue,

  cancellationDate,

  -- PQ: Date.Day(paymentDate) (dia do mes, apesar do nome)
  EXTRACT(
    DAY
    FROM paymentDate
  ) AS NumeroDiaDaSemana,

  situationId,

  percentual,

  ValorBruto * percentual AS ValorBloko,

  ValorBruto - (ValorBruto * percentual) AS ValorParceiro,

  -- PQ: contractDate nulo gera erro -> NULL
  CASE
    WHEN contractDate IS NULL
    THEN NULL

    WHEN EXTRACT(YEAR FROM contractDate) <= 2015
    THEN '<= 2015'

    WHEN EXTRACT(YEAR FROM contractDate) <= 2019
    THEN '2016 - 2019'

    WHEN EXTRACT(YEAR FROM contractDate) <= 2022
    THEN '2020 - 2022'

    ELSE CAST(
      EXTRACT(YEAR FROM contractDate)
      AS STRING
    )
  END AS anoPeriodoVenda

FROM
  saldo_com_unidades;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- VALIDACAO
-- ####################################################################

-- totais por origem (OrigemBase NULL = Recebidas)
-- SELECT

--   IFNULL(OrigemBase, '(Recebidas)') AS origem,

--   COUNT(*)                          AS linhas,
--   SUM(ValorBruto)                   AS soma_ValorBruto,
--   SUM(ValorBloko)                   AS soma_ValorBloko,
--   SUM(ValorParceiro)                AS soma_ValorParceiro,
--   COUNTIF(dueDate IS NULL)          AS dueDate_nulo,
--   COUNTIF(contractDate IS NULL)     AS sem_venda,
--   COUNTIF(situationId IS NULL)      AS sem_unidade

-- FROM
--   `dadosfinanceiro-501613.analytics.saldo_devedor`

-- GROUP BY
--   origem;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- linhas esperadas antes dos joins x depois
-- (diferenca = duplicacao por ChaveGeral repetida em fato_vendas
--  ou ChaveEmpreendimentoLote repetida em dim_unidades, igual PQ)
-- SELECT

--   (SELECT COUNT(*) FROM `dadosfinanceiro-501613.raw.areceber`)
--   + (SELECT COUNT(*) FROM `dadosfinanceiro-501613.analytics.fato_recebidas`)
--     AS linhas_antes_joins,

--   (SELECT COUNT(*) FROM `dadosfinanceiro-501613.analytics.saldo_devedor`)
--     AS linhas_saldo_devedor;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- chaves duplicadas nas tabelas de join
-- SELECT 'fato_vendas' AS tabela, ChaveGeral AS chave, COUNT(*) AS qtd
-- FROM `dadosfinanceiro-501613.analytics.fato_vendas`
-- GROUP BY ChaveGeral
-- HAVING COUNT(*) > 1

-- UNION ALL

-- SELECT 'dim_unidades', ChaveEmpreendimentoLote, COUNT(*)
-- FROM `dadosfinanceiro-501613.analytics.dim_unidades`
-- GROUP BY ChaveEmpreendimentoLote
-- HAVING COUNT(*) > 1

-- ORDER BY qtd DESC
-- LIMIT 100;