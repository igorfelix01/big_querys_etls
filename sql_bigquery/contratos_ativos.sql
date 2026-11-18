CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.contratos_ativos`

AS



WITH vendas_base AS (



  SELECT



    SAFE_CAST(companyId AS INT64)

      AS companyId,



    SAFE_CAST(internalCompanyId AS INT64)

      AS internalCompanyId,



    SAFE_CAST(enterpriseId AS INT64)

      AS enterpriseId,



    SAFE_CAST(internalEnterpriseId AS INT64)

      AS internalEnterpriseId,



    SAFE_CAST(receivableBillId AS INT64)

      AS receivableBillId,



    SAFE_CAST(cancellationPayableBillId AS INT64)

      AS cancellationPayableBillId,





    CAST(companyName AS STRING)

      AS companyName,



    CAST(enterpriseName AS STRING)

      AS enterpriseName,



    CAST(number AS STRING)

      AS documentNumber,



    CAST(situation AS STRING)

      AS situation,



    CAST(correctionType AS STRING)

      AS correctionType,



    CAST(cancellationReason AS STRING)

      AS cancellationReason,



    CAST(subdominio AS STRING)

      AS subdominio,





    SAFE_CAST(

      REPLACE(

        CAST(value AS STRING),

        ',',

        '.'

      )

      AS FLOAT64

    ) AS value,





    SAFE_CAST(

      REPLACE(

        CAST(totalSellingValue AS STRING),

        ',',

        '.'

      )

      AS FLOAT64

    ) AS totalSellingValue,





    SAFE_CAST(

      REPLACE(

        CAST(totalCancellationAmount AS STRING),

        ',',

        '.'

      )

      AS FLOAT64

    ) AS totalCancellationAmount,





    SAFE_CAST(contractDate AS DATE)

      AS DataVenda,



    SAFE_CAST(issueDate AS DATE)

      AS issueDate,



    SAFE_CAST(cancellationDate AS DATE)

      AS cancellationDate,



    SAFE_CAST(creationDate AS DATE)

      AS creationDate,



    SAFE_CAST(lastUpdateDate AS DATE)

      AS lastUpdateDate,



    SAFE_CAST(financialInstitutionDate AS DATE)

      AS financialInstitutionDate,





    EXTRACT(

      MONTH

      FROM SAFE_CAST(contractDate AS DATE)

    ) AS saleMonth,





    EXTRACT(

      YEAR

      FROM SAFE_CAST(contractDate AS DATE)

    ) AS saleYear,





    CONCAT(

      CAST(enterpriseId AS STRING),

      '-',

      CAST(receivableBillId AS STRING)

    ) AS ChaveEmpreendimento,





    CONCAT(

      CAST(companyId AS STRING),

      '-',

      CAST(receivableBillId AS STRING)

    ) AS ChaveGeral





  FROM

    `dadosfinanceiro-501613.raw.vendas`



  WHERE

    situation = 'Emitido'



),





vendas_unidades AS (



  SELECT



    ChaveGeral,



    name



  FROM

    `dadosfinanceiro-501613.analytics.dim_vendas_unidades`



  QUALIFY

    ROW_NUMBER() OVER (



      PARTITION BY

        ChaveGeral



      ORDER BY

        ChaveLote



    ) = 1



),





-- ============================================================

-- A RECEBER

--

-- trusted.areceber JA ESTA TRATADA.

--

-- correctedBalanceAmount

-- virou ValorBruto.

--

-- interestRate JA FOI TRATADO NA ETAPA A RECEBER.

--

-- situacaoInicialAR JA FOI CALCULADA NA ETAPA A RECEBER.

-- ============================================================



a_receber_base AS (



  SELECT



    SAFE_CAST(companyId AS INT64)

      AS companyId,





    SAFE_CAST(billId AS INT64)

      AS billId,





    CONCAT(

      CAST(companyId AS STRING),

      '-',

      CAST(billId AS STRING)

    ) AS ChaveGeral,





    SAFE_CAST(

      REPLACE(

        CAST(originalAmount AS STRING),

        ',',

        '.'

      )

      AS FLOAT64

    ) AS originalAmountAR,





    SAFE_CAST(

      REPLACE(

        CAST(balanceAmount AS STRING),

        ',',

        '.'

      )

      AS FLOAT64

    ) AS balanceAmount,





    -- correctedBalanceAmount foi renomeado

    -- para ValorBruto em trusted.areceber

    SAFE_CAST(

      REPLACE(

        CAST(ValorBruto AS STRING),

        ',',

        '.'

      )

      AS FLOAT64

    ) AS correctedBalanceAmount,





    SAFE_CAST(dueDate AS DATE)

      AS dueDateAR,





    -- NAO DIVIDIR NOVAMENTE.

    -- interestRate ja foi tratado em trusted.areceber.

    SAFE_CAST(interestRate AS FLOAT64)

      AS interestRate,





    SAFE_CAST(

      ParcelaAR

      AS INT64

    ) AS ParcelaAR,





    SAFE_CAST(

      atrasoDias

      AS FLOAT64

    ) AS atrasoDias,





    CAST(

      situacaoInicialAR

      AS STRING

    ) AS situacaoInicialAR





  FROM

    `dadosfinanceiro-501613.trusted.areceber`



  WHERE

    billId IS NOT NULL



),





a_receber_tratado AS (



  SELECT



    *,



    CASE



      WHEN situacaoInicialAR = 'Adimplente'

      THEN 1



      WHEN situacaoInicialAR = 'Atrasado'

      THEN 2



      ELSE 3



    END AS Auxiliar_AR_Total



  FROM

    a_receber_base



),





db_a_receber_totalizador_bi AS (



  SELECT



    ChaveGeral,





    SUM(originalAmountAR)

      AS originalAmountAgregado,





    SUM(balanceAmount)

      AS balanceAmountAgregado,





    SUM(correctedBalanceAmount)

      AS correctedBalanceAmountAgregado,





    MAX(dueDateAR)

      AS UltimaDataVencimento,





    MIN(dueDateAR)

      AS PrimeiraDataVencimento,





    MIN(ParcelaAR)

      AS MinNuParcela,





    MAX(interestRate)

      AS TaxaPresente,





    MAX(atrasoDias)

      AS MaxAtrasoDias,





    MAX(Auxiliar_AR_Total)

      AS Max_Auxiliar_AR_Total,





    COUNT(*)

      AS QuantidadeParcelasAR,





    CASE



      WHEN SUM(correctedBalanceAmount) = 0

      THEN 'Quitado'



      WHEN MAX(Auxiliar_AR_Total) = 1

      THEN 'Adimplente'



      WHEN MAX(Auxiliar_AR_Total) = 2

      THEN 'Atrasado'



      ELSE 'Inadimplente'



    END AS SituacaoContrato





  FROM

    a_receber_tratado



  GROUP BY

    ChaveGeral



),





db_recebidas_totalizador_bi AS (



  SELECT



    ChaveGeral,





    SUM(

      SAFE_CAST(

        REPLACE(

          CAST(ValorBruto AS STRING),

          ',',

          '.'

        )

        AS FLOAT64

      )

    ) AS ValorLiquidoAgregado,





    MIN(

      SAFE_CAST(paymentDate AS DATE)

    ) AS PrimeiraDataPagamento,





    MIN(

      SAFE_CAST(dueDate AS DATE)

    ) AS PrimeiraDataVencimento,





    MAX(

      SAFE_CAST(paymentDate AS DATE)

    ) AS UltimaDataPagamento,





    MAX(

      SAFE_CAST(dueDate AS DATE)

    ) AS UltimaDataVencimento,





    COUNT(*)

      AS QuantidadePagamentos





  FROM

    `dadosfinanceiro-501613.trusted.recebidas`



  GROUP BY

    ChaveGeral



),





com_vendas_unidades AS (



  SELECT



    v.*,



    vu.name



  FROM

    vendas_base AS v



  LEFT JOIN

    vendas_unidades AS vu



    ON v.ChaveGeral =

       vu.ChaveGeral



),





com_a_receber AS (



  SELECT



    v.*,





    ar.originalAmountAgregado,



    ar.balanceAmountAgregado,



    ar.correctedBalanceAmountAgregado,





    ar.UltimaDataVencimento

      AS UltimaDataVencimentoAR,





    ar.PrimeiraDataVencimento

      AS PrimeiraDataVencimentoAR,





    ar.MinNuParcela,



    ar.TaxaPresente,



    ar.MaxAtrasoDias,



    ar.Max_Auxiliar_AR_Total,



    ar.QuantidadeParcelasAR,



    ar.SituacaoContrato





  FROM

    com_vendas_unidades AS v



  LEFT JOIN

    db_a_receber_totalizador_bi AS ar



    ON v.ChaveGeral =

       ar.ChaveGeral



),





com_recebidas AS (



  SELECT



    ar.*,





    r.ValorLiquidoAgregado,



    r.PrimeiraDataPagamento,



    r.PrimeiraDataVencimento,



    r.UltimaDataPagamento,



    r.UltimaDataVencimento,



    r.QuantidadePagamentos





  FROM

    com_a_receber AS ar



  LEFT JOIN

    db_recebidas_totalizador_bi AS r



    ON ar.ChaveGeral =

       r.ChaveGeral



),





situacao_tratada AS (



  SELECT



    * REPLACE (



      COALESCE(

        SituacaoContrato,

        '-'

      ) AS SituacaoContrato



    )



  FROM

    com_recebidas



),





removido_duplicado AS (



  SELECT

    *



  FROM

    situacao_tratada



  QUALIFY

    ROW_NUMBER() OVER (



      PARTITION BY

        ChaveGeral



      ORDER BY

        ChaveGeral



    ) = 1



),





com_clientes AS (



  SELECT



    ca.*,



    vc.names



  FROM

    removido_duplicado AS ca



  LEFT JOIN

    `dadosfinanceiro-501613.analytics.dim_vendas_clientes`

      AS vc



    ON ca.ChaveGeral =

       vc.ChaveGeral



)





SELECT



  ChaveGeral,



  ChaveEmpreendimento,





  companyId,



  enterpriseId,



  DataVenda,



  documentNumber,



  value,





  receivableBillId

    AS billId,





  correctionType,



  saleMonth,



  saleYear,





  originalAmountAgregado,



  balanceAmountAgregado,



  correctedBalanceAmountAgregado,





  PrimeiraDataVencimentoAR,



  UltimaDataVencimentoAR,





  MinNuParcela,



  TaxaPresente,



  MaxAtrasoDias,



  Max_Auxiliar_AR_Total,





  PrimeiraDataPagamento,



  PrimeiraDataVencimento,



  UltimaDataPagamento,



  UltimaDataVencimento,





  ValorLiquidoAgregado,



  QuantidadePagamentos,



  QuantidadeParcelasAR,





  SituacaoContrato,





  names,



  name,





  internalCompanyId,



  internalEnterpriseId,



  cancellationPayableBillId,



  companyName,



  enterpriseName,



  situation,



  cancellationReason,



  totalSellingValue,



  totalCancellationAmount,



  issueDate,



  cancellationDate,



  creationDate,



  lastUpdateDate,



  financialInstitutionDate,



  subdominio





FROM

  com_clientes

;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.fato_contratos_ativos`

AS



SELECT

  *



FROM

  `dadosfinanceiro-501613.trusted.contratos_ativos`

;