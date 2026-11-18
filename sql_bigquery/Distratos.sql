CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.distratos` AS

WITH vendas_base AS (

  SELECT

    SAFE_CAST(companyId AS INT64) AS companyId,

    SAFE_CAST(internalCompanyId AS INT64) AS internalCompanyId,

    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,

    SAFE_CAST(internalEnterpriseId AS INT64) AS internalEnterpriseId,

    SAFE_CAST(receivableBillId AS INT64) AS receivableBillId,

    SAFE_CAST(cancellationPayableBillId AS INT64) AS cancellationPayableBillId,



    CAST(companyName AS STRING) AS companyName,

    CAST(enterpriseName AS STRING) AS enterpriseName,

    CAST(number AS STRING) AS documentNumber,

    CAST(situation AS STRING) AS situation,

    CAST(correctionType AS STRING) AS correctionType,

    CAST(cancellationReason AS STRING) AS cancellationReason,

    CAST(subdominio AS STRING) AS subdominio,



    SAFE_CAST(REPLACE(CAST(value AS STRING), ',', '.') AS FLOAT64) AS value,

    SAFE_CAST(REPLACE(CAST(totalSellingValue AS STRING), ',', '.') AS FLOAT64) AS totalSellingValue,

    SAFE_CAST(REPLACE(CAST(totalCancellationAmount AS STRING), ',', '.') AS FLOAT64) AS totalCancellationAmount,



    SAFE_CAST(contractDate AS DATE) AS contractDate,

    SAFE_CAST(issueDate AS DATE) AS issueDate,

    SAFE_CAST(cancellationDate AS DATE) AS cancellationDate,

    SAFE_CAST(creationDate AS DATE) AS creationDate,

    SAFE_CAST(lastUpdateDate AS DATE) AS lastUpdateDate,

    SAFE_CAST(financialInstitutionDate AS DATE) AS financialInstitutionDate,



    CONCAT(

      CAST(companyId AS STRING),

      '-',

      CAST(receivableBillId AS STRING)

    ) AS ChaveGeral



  FROM `dadosfinanceiro-501613.raw.vendas`

),



com_clientes AS (

  SELECT

    v.*,

    vc.names

  FROM vendas_base v

  LEFT JOIN `dadosfinanceiro-501613.analytics.dim_vendas_clientes` vc

    ON v.ChaveGeral = vc.ChaveGeral

),



vendas_unidades AS (

  SELECT

    ChaveGeral,

    name

  FROM `dadosfinanceiro-501613.analytics.dim_vendas_unidades`

  QUALIFY ROW_NUMBER() OVER (

    PARTITION BY ChaveGeral

    ORDER BY ChaveLote

  ) = 1

),



com_unidades AS (

  SELECT

    c.*,

    vu.name,



    CONCAT(

      CAST(c.companyId AS STRING),

      '-',

      CAST(c.enterpriseId AS STRING),

      '-',

      CAST(vu.name AS STRING)

    ) AS ChaveLote



  FROM com_clientes c

  LEFT JOIN vendas_unidades vu

    ON c.ChaveGeral = vu.ChaveGeral

),



filtrado_cancelado AS (

  SELECT

    *,



    EXTRACT(MONTH FROM contractDate) AS Month,

    EXTRACT(YEAR FROM contractDate) AS Year,



    CONCAT(

      CAST(enterpriseId AS STRING),

      '-',

      CAST(receivableBillId AS STRING)

    ) AS ChaveEmpreendimento



  FROM com_unidades

  WHERE situation = 'Cancelado'

),



db_recebidas_totalizador_bi AS (

  SELECT

    ChaveGeral,



    SUM(SAFE_CAST(REPLACE(CAST(ValorBruto AS STRING), ',', '.') AS FLOAT64)) AS ValorLiquidoAgregado,



    MIN(SAFE_CAST(paymentDate AS DATE)) AS PrimeiraDataRecebimento,

    MIN(SAFE_CAST(dueDate AS DATE)) AS PrimeiraDataVencimento,

    MAX(SAFE_CAST(paymentDate AS DATE)) AS UltimaDataRecebimento,

    MAX(SAFE_CAST(dueDate AS DATE)) AS UltimaDataVencimento,



    COUNT(*) AS QuantidadePagamentos



  FROM `dadosfinanceiro-501613.trusted.recebidas`

  GROUP BY ChaveGeral

),



com_recebidas AS (

  SELECT

    f.*,



    r.ValorLiquidoAgregado,

    r.PrimeiraDataRecebimento,

    r.PrimeiraDataVencimento,

    r.UltimaDataRecebimento,

    r.UltimaDataVencimento,

    r.QuantidadePagamentos



  FROM filtrado_cancelado f

  LEFT JOIN db_recebidas_totalizador_bi r

    ON f.ChaveGeral = r.ChaveGeral

),



com_ano_periodo AS (

  SELECT

    *,



    CASE

      WHEN EXTRACT(YEAR FROM contractDate) <= 2015 THEN '<= 2015'

      WHEN EXTRACT(YEAR FROM contractDate) <= 2020 THEN '2016 - 2020'

      ELSE CAST(EXTRACT(YEAR FROM contractDate) AS STRING)

    END AS anoPeriodoVenda



  FROM com_recebidas

),



final AS (

  SELECT

    *,



    CONCAT(

      CAST(companyId AS STRING),

      '-',

      CAST(cancellationPayableBillId AS STRING)

    ) AS ChaveDistrato



  FROM com_ano_periodo

)



SELECT

  ChaveGeral,

  ChaveEmpreendimento,

  ChaveLote,

  ChaveDistrato,



  companyId,

  internalCompanyId,

  enterpriseId,

  internalEnterpriseId,

  receivableBillId,

  cancellationPayableBillId,



  companyName,

  enterpriseName,

  documentNumber,

  situation,

  correctionType,

  cancellationReason,

  subdominio,



  names,

  name,



  value,

  totalSellingValue,

  totalCancellationAmount,



  contractDate,

  issueDate,

  cancellationDate,

  creationDate,

  lastUpdateDate,

  financialInstitutionDate,



  Month,

  Year,

  anoPeriodoVenda,



  ValorLiquidoAgregado,

  PrimeiraDataRecebimento,

  PrimeiraDataVencimento,

  UltimaDataRecebimento,

  UltimaDataVencimento,

  QuantidadePagamentos



FROM final;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_distratos` AS

SELECT

  *

FROM `dadosfinanceiro-501613.trusted.distratos`;