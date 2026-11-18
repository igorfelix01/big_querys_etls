-- ####################################################################

-- TRUSTED.DB_TITULOS_TOTALIZADOR  +  ANALYTICS.FATO_TITULOS_TOTALIZADOR

--

-- FIEL AO POWER QUERY: db_titulos_totalizador

--

-- Parte A Receber (dados_recebidos): igual db_a_receber

--   (interestRate / 100, situacaoInicialAR pela regra de mes/ano,

--    ValorPresente, ParcelaAR) -> reaproveita analytics.fato_areceber

--   renomes do PQ: originalAmount -> originalAmountAR, dueDate -> dueDateAR

--   (na fato_areceber o correctedBalanceAmount ja se chama ValorBruto)

-- + Append db_recebidas (analytics.fato_recebidas)

-- atrasoDias NULL -> 0 ; ChaveClientes = subdominio-clientId

-- GROUP BY ChaveGeral (somas / max / min do PQ)

-- LEFT JOIN db_vendas (ChaveGeral), db_unidades (ChaveEmpreendimentoLote),

--           db_clientes (ChaveClientes)

-- SituacaoContrato:

--   cancellationDate <> null      -> Distratado

--   SaldoDevedorComJuros = 0      -> Quitado

--   Max_Auxiliar_AR_Total = 1     -> Adimplente

--   Max_Auxiliar_AR_Total = 2     -> Atrasado

--   senao                         -> Inadimplente

-- anoPeriodoVenda: S/ Registro de Venda | <= 2015 | 2016 - 2020 | ano

-- StatusCobranca: MaxAtrasoDias >= 91 e subJudicie = N -> Cobranca;

--                 subJudicie = S -> Subjudice; senao CUB

-- Distinct por ChaveGeral

--

-- Mantem as MESMAS colunas da fato_titulos_totalizador anterior.

--

-- Depende de: analytics.fato_areceber, analytics.fato_recebidas,

--             analytics.fato_vendas, analytics.dim_unidades,

--             analytics.dim_clientes

-- ####################################################################





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.db_titulos_totalizador`

AS



WITH



-- ------------------------------------------------------------------

-- 1. A RECEBER (db_a_receber ja tratado)

-- ------------------------------------------------------------------

a_receber AS (

  SELECT

    ChaveGeral,

    CAST(NULL AS NUMERIC)                      AS ValorBruto,          -- so recebidas tem

    CAST(NULL AS NUMERIC)                      AS originalAmount,      -- renomeado p/ AR

    originalAmount                             AS originalAmountAR,

    balanceAmount,

    ValorBruto                                 AS correctedBalanceAmount,

    ValorPresente,

    dueDate                                    AS dueDateAR,

    CAST(NULL AS DATE)                         AS paymentDate,

    IFNULL(atrasoDias, 0)                      AS atrasoDias,

    CASE situacaoInicialAR

      WHEN 'Adimplente' THEN 1

      WHEN 'Atrasado'   THEN 2

      ELSE 3

    END                                        AS Auxiliar_AR_Total,



    CAST(subdominio AS STRING)                 AS subdominio,

    companyId,

    CAST(companyName AS STRING)                AS companyName,

    groupCompanyId,

    CAST(groupCompanyName AS STRING)           AS groupCompanyName,

    clientId,

    CAST(clientName AS STRING)                 AS clientName,

    billId,

    CAST(subJudicie AS STRING)                 AS subJudicie,

    CAST(documentIdentificationId AS STRING)   AS documentIdentificationId,

    CAST(documentIdentificationName AS STRING) AS documentIdentificationName,

    CAST(documentNumber AS STRING)             AS documentNumber,

    indexerId,

    CAST(indexerName AS STRING)                AS indexerName,

    CAST(periodicityType AS STRING)            AS periodicityType,

    CAST(interestType AS STRING)               AS interestType,

    interestRate,

    CAST(correctionType AS STRING)             AS correctionType,

    CAST(defaulterSituation AS STRING)         AS defaulterSituation,

    CAST(mainUnit AS STRING)                   AS mainUnit,

    costCenterId,

    CAST(costCenterName AS STRING)             AS costCenterName,

    ChaveEmpreendimentoLote

  FROM `dadosfinanceiro-501613.analytics.fato_areceber`

),



-- ------------------------------------------------------------------

-- 2. RECEBIDAS (db_recebidas)

-- ------------------------------------------------------------------

recebidas AS (

  SELECT

    ChaveGeral,

    ValorBruto,

    originalAmount,

    CAST(NULL AS NUMERIC)                      AS originalAmountAR,

    balanceAmount,

    correctedBalanceAmount,

    CAST(NULL AS NUMERIC)                      AS ValorPresente,

    CAST(NULL AS DATE)                         AS dueDateAR,

    paymentDate,

    0                                          AS atrasoDias,          -- null -> 0

    CAST(NULL AS INT64)                        AS Auxiliar_AR_Total,



    subdominio,

    companyId,

    companyName,

    groupCompanyId,

    groupCompanyName,

    clientId,

    clientName,

    billId,

    subJudicie,

    documentIdentificationId,

    documentIdentificationName,

    documentNumber,

    indexerId,

    indexerName,

    periodicityType,

    interestType,

    interestRate,

    correctionType,

    defaulterSituation,

    mainUnit,

    costCenterId,

    costCenterName,

    ChaveEmpreendimentoLote

  FROM `dadosfinanceiro-501613.analytics.fato_recebidas`

),



base AS (

  SELECT *,

    ARRAY_TO_STRING([subdominio, CAST(clientId AS STRING)], '-') AS ChaveClientes

  FROM (

    SELECT * FROM a_receber

    UNION ALL

    SELECT * FROM recebidas

  )

),



-- ------------------------------------------------------------------

-- 3. GROUP BY ChaveGeral

-- ------------------------------------------------------------------

agrupado AS (

  SELECT

    ChaveGeral,

    SUM(ValorBruto)              AS ValorLiquidoAgregado,

    SUM(originalAmount)          AS originalAmountAgregado,

    SUM(originalAmountAR)        AS SaldoDevedorSemJuros,

    SUM(balanceAmount)           AS balanceAmountAgregado,

    SUM(correctedBalanceAmount)  AS SaldoDevedorComJuros,

    SUM(ValorPresente)           AS ValorPresenteAgregado,

    MIN(dueDateAR)               AS PrimeiraDataVencimento,

    MAX(subdominio)              AS subdominio,

    MAX(companyId)               AS companyId,

    MAX(companyName)             AS companyName,

    MAX(groupCompanyId)          AS groupCompanyId,

    MAX(groupCompanyName)        AS groupCompanyName,

    MAX(clientId)                AS clientId,

    MAX(clientName)              AS clientName,

    MAX(billId)                  AS billId,

    MAX(subJudicie)              AS subJudicie,

    MAX(documentIdentificationId)   AS documentIdentificationId,

    MAX(documentIdentificationName) AS documentIdentificationName,

    MAX(documentNumber)          AS documentNumber,

    MAX(indexerId)               AS indexerId,

    MAX(indexerName)             AS indexerName,

    MAX(periodicityType)         AS periodicityType,

    MAX(interestType)            AS interestType,

    MAX(interestRate)            AS interestRate,

    MAX(correctionType)          AS correctionType,

    MAX(defaulterSituation)      AS defaulterSituation,

    MAX(mainUnit)                AS mainUnit,

    MAX(costCenterId)            AS costCenterId,

    MAX(costCenterName)          AS costCenterName,

    MAX(ChaveEmpreendimentoLote) AS ChaveEmpreendimentoLote,

    MAX(ChaveClientes)           AS ChaveClientes,

    MAX(Auxiliar_AR_Total)       AS Max_Auxiliar_AR_Total,

    MAX(atrasoDias)              AS MaxAtrasoDias,

    MAX(paymentDate)             AS DataUltimoPagamento

  FROM base

  GROUP BY ChaveGeral

),



-- ------------------------------------------------------------------

-- 4. JOINS (sem deduplicar, igual PQ; Distinct no final)

-- ------------------------------------------------------------------

com_joins AS (

  SELECT

    a.*,

    v.receivableBillId,

    v.cancellationPayableBillId,

    v.contractDate,

    v.value,

    v.totalSellingValue,

    v.cancellationDate,

    u.percentual,

    u.terrainValue,

    u.`Descrição`,

    u.`Classificação Unidades`,

    c.Telefone,

    c.CPF,

    c.CNPJ,

    c.Email

  FROM agrupado a

  LEFT JOIN `dadosfinanceiro-501613.analytics.fato_vendas`  v ON v.ChaveGeral = a.ChaveGeral

  LEFT JOIN `dadosfinanceiro-501613.analytics.dim_unidades` u ON u.ChaveEmpreendimentoLote = a.ChaveEmpreendimentoLote

  LEFT JOIN `dadosfinanceiro-501613.analytics.dim_clientes` c ON c.ChaveClientes = a.ChaveClientes

)



SELECT

  ChaveGeral,

  CAST(ValorLiquidoAgregado   AS FLOAT64) AS ValorLiquidoAgregado,

  CAST(originalAmountAgregado AS FLOAT64) AS originalAmountAgregado,

  CAST(SaldoDevedorSemJuros   AS FLOAT64) AS SaldoDevedorSemJuros,

  CAST(balanceAmountAgregado  AS FLOAT64) AS balanceAmountAgregado,

  CAST(SaldoDevedorComJuros   AS FLOAT64) AS SaldoDevedorComJuros,

  CAST(ValorPresenteAgregado  AS FLOAT64) AS ValorPresenteAgregado,

  PrimeiraDataVencimento,

  subdominio,

  companyId,

  companyName,

  groupCompanyId,

  groupCompanyName,

  clientId,

  clientName,

  billId,

  subJudicie,

  documentIdentificationId,

  documentIdentificationName,

  documentNumber,

  CAST(indexerId AS FLOAT64)    AS indexerId,

  indexerName,

  periodicityType,

  interestType,

  CAST(interestRate AS FLOAT64) AS interestRate,

  correctionType,

  defaulterSituation,

  mainUnit,

  costCenterId,

  costCenterName,

  ChaveEmpreendimentoLote,

  ChaveClientes,

  CAST(MaxAtrasoDias AS INT64) AS MaxAtrasoDias,

  DataUltimoPagamento,

  receivableBillId,

  cancellationPayableBillId,

  contractDate,

  CAST(value AS FLOAT64)             AS value,

  CAST(totalSellingValue AS FLOAT64) AS totalSellingValue,

  cancellationDate,

  percentual,

  terrainValue,

  `Descrição`,

  `Classificação Unidades`,

  Telefone,

  CPF,

  CNPJ,

  Email,



  CASE

    WHEN cancellationDate IS NOT NULL THEN 'Distratado'

    WHEN SaldoDevedorComJuros = 0     THEN 'Quitado'

    WHEN Max_Auxiliar_AR_Total = 1    THEN 'Adimplente'

    WHEN Max_Auxiliar_AR_Total = 2    THEN 'Atrasado'

    ELSE 'Inadimplente'

  END AS SituacaoContrato,



  CASE

    WHEN contractDate IS NULL                   THEN 'S/ Registro de Venda'

    WHEN EXTRACT(YEAR FROM contractDate) <= 2015 THEN '<= 2015'

    WHEN EXTRACT(YEAR FROM contractDate) <= 2020 THEN '2016 - 2020'

    ELSE CAST(EXTRACT(YEAR FROM contractDate) AS STRING)

  END AS anoPeriodoVenda,



  CASE

    WHEN MaxAtrasoDias >= 91 AND subJudicie = 'N' THEN 'Cobrança'

    WHEN subJudicie = 'S'                         THEN 'Subjudice'

    ELSE 'CUB'

  END AS `StatusCobrança`



FROM com_joins



-- PQ: Table.Distinct(..., {"ChaveGeral"})

QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral ORDER BY ChaveGeral) = 1;





-- ####################################################################

-- ANALYTICS

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

AS

SELECT *

FROM `dadosfinanceiro-501613.trusted.db_titulos_totalizador`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO

-- ####################################################################



-- 1) casamento com a tabela de contratos do Looker (deve ser ~100%)

-- SELECT

--   COUNT(DISTINCT c.ChaveGeral) AS contratos_tabela,

--   COUNT(DISTINCT t.ChaveGeral) AS contratos_com_match

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_tabela_contratos` c

-- LEFT JOIN `dadosfinanceiro-501613.analytics.fato_titulos_totalizador` t

--   ON t.ChaveGeral = c.ChaveGeral;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]




-- 2) contratos do print do BI

--    606-61464 Inadimplente 733,90 | 606-61434 Quitado 0,00 |

--    606-61248 Adimplente 9.565,83 | 606-62260 Inadimplente 3.777,74

-- SELECT ChaveGeral, SituacaoContrato, ROUND(SaldoDevedorComJuros, 2) AS em_aberto

-- FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

-- WHERE ChaveGeral IN ('606-62260', '606-61683', '606-61464', '606-61434',

--                      '606-61357', '606-61248', '606-61200')

-- ORDER BY ChaveGeral DESC;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]




-- 3) distribuicao da situacao

-- SELECT SituacaoContrato, COUNT(*) AS contratos

-- FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

-- GROUP BY 1

-- ORDER BY 2 DESC;