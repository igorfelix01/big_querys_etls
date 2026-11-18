CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.db_a_receber_totalizador`

AS

WITH

base AS (

  SELECT

    ChaveGeral,

    groupCompanyName,

    subJudicie,

    originalAmount,

    balanceAmount,

    ValorBruto AS correctedBalanceAmount,

    dueDate,

    ParcelaAR,

    TotalParcelas,

    interestRate / 100 AS TaxaTotalizador,

    DATE_DIFF(CURRENT_DATE('America/Sao_Paulo'), dueDate, DAY) AS atrasoDias,

    -((EXTRACT(YEAR  FROM CURRENT_DATE('America/Sao_Paulo')) - EXTRACT(YEAR  FROM dueDate)) * 12

      + (EXTRACT(MONTH FROM CURRENT_DATE('America/Sao_Paulo')) - EXTRACT(MONTH FROM dueDate)))

      AS MesCapitalizacao

  FROM `dadosfinanceiro-501613.analytics.fato_areceber`

  WHERE ChaveGeral IS NOT NULL

),

parcelas AS (

  SELECT

    *,

    CASE

      WHEN MesCapitalizacao IS NULL THEN NULL

      WHEN MesCapitalizacao <= 0    THEN originalAmount

      WHEN TaxaTotalizador IS NULL  THEN NULL

      WHEN TaxaTotalizador <> 0

        THEN originalAmount / POW(1 + CAST(TaxaTotalizador AS FLOAT64), MesCapitalizacao)

      ELSE originalAmount

    END AS ValorPresente,

    CASE

      WHEN atrasoDias IS NULL THEN NULL

      WHEN atrasoDias <= 30   THEN 1

      WHEN atrasoDias <= 90   THEN 2

      ELSE 3

    END AS Auxiliar_AR_Total

  FROM base

),

agrupado AS (

  SELECT

    ChaveGeral,

    MAX(groupCompanyName)        AS groupCompanyName,

    SUM(originalAmount)          AS originalAmountAgregado,

    SUM(balanceAmount)           AS balanceAmountAgregado,

    SUM(correctedBalanceAmount)  AS correctedBalanceAmountAgregado,

    SUM(ValorPresente)           AS ValorPresenteAgregado,

    MAX(dueDate)                 AS UltimaDataVencimento,

    MIN(dueDate)                 AS PrimeiraDataVencimento,

    MIN(ParcelaAR)               AS MinNuParcela,

    MAX(TotalParcelas)           AS TotalParcelas,

    MAX(TaxaTotalizador)         AS TaxaPresente,

    MAX(atrasoDias)              AS MaxAtrasoDias,

    MAX(Auxiliar_AR_Total)       AS Max_Auxiliar_AR_Total,

    COUNT(*)                     AS QuantidadeParcelasAR,

    MAX(subJudicie)              AS SubJudice

  FROM parcelas

  GROUP BY ChaveGeral

)

SELECT

  *,

  CASE Max_Auxiliar_AR_Total

    WHEN 1 THEN 'Adimplente'

    WHEN 2 THEN 'Atrasado'

    WHEN 3 THEN 'Inadimplente'

  END AS SituacaoContrato

FROM agrupado;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.fato_a_receber_totalizador`

AS

SELECT *

FROM `dadosfinanceiro-501613.trusted.db_a_receber_totalizador`;