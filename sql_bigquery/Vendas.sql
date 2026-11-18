CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.vendas`

AS



WITH fonte AS (



  SELECT

    id,



    CAST(companyId AS INT64)

      AS companyId,



    CAST(internalCompanyId AS INT64)

      AS internalCompanyId,



    CAST(enterpriseId AS INT64)

      AS enterpriseId,



    CAST(internalEnterpriseId AS INT64)

      AS internalEnterpriseId,



    CAST(receivableBillId AS INT64)

      AS receivableBillId,



    CAST(externalId AS INT64)

      AS externalId,



    CAST(companyName AS STRING)

      AS companyName,



    CAST(enterpriseName AS STRING)

      AS enterpriseName,



    CASE

      WHEN cancellationPayableBillId IS NULL

        OR TRIM(CAST(cancellationPayableBillId AS STRING)) = ''

      THEN NULL



      ELSE CAST(

        CAST(

          cancellationPayableBillId

          AS NUMERIC

        )

        AS INT64

      )

    END AS cancellationPayableBillId,



    CAST(number AS STRING)

      AS documentNumber,



    CAST(correctionType AS STRING)

      AS correctionType,



    CAST(situation AS STRING)

      AS situation,



    CAST(discountType AS STRING)

      AS discountType,



    CAST(cancellationReason AS STRING)

      AS cancellationReason,



    CAST(discountPercentage AS STRING)

      AS discountPercentage,



    CAST(financialInstitutionNumber AS STRING)

      AS financialInstitutionNumber,



    CAST(interestType AS STRING)

      AS interestType,



    CAST(lateInterestCalculationType AS STRING)

      AS lateInterestCalculationType,



    CAST(dailyLateInterestValue AS STRING)

      AS dailyLateInterestValue,



    CAST(specialClause AS STRING)

      AS specialClause,



    CAST(linkedCommissions AS STRING)

      AS linkedCommissions,



    CAST(subdominio AS STRING)

      AS subdominio,



    CAST(ChaveEspecifica AS STRING)

      AS ChaveEspecifica,



    CAST(value AS FLOAT64)

      AS value,



    CAST(totalSellingValue AS FLOAT64)

      AS totalSellingValue,



    CAST(totalCancellationAmount AS FLOAT64)

      AS totalCancellationAmount,



    CAST(proRataIndexer AS FLOAT64)

      AS proRataIndexer,



    CAST(interestPercentage AS FLOAT64)

      AS interestPercentage,



    CAST(fineRate AS FLOAT64)

      AS fineRate,



    CAST(contractDate AS DATE)

      AS contractDate,



    CAST(issueDate AS DATE)

      AS issueDate,



    CAST(expectedDeliveryDate AS DATE)

      AS expectedDeliveryDate,



    CAST(accountingDate AS DATE)

      AS accountingDate,



    CAST(keysDeliveredAt AS DATE)

      AS keysDeliveredAt,



    CAST(cancellationDate AS DATE)

      AS cancellationDate,



    CAST(creationDate AS DATE)

      AS creationDate,



    CAST(lastUpdateDate AS DATE)

      AS lastUpdateDate,



    CAST(financialInstitutionDate AS DATE)

      AS financialInstitutionDate,



    CAST(registerPropertyDate AS DATE)

      AS registerPropertyDate,



    CAST(containsRemadeInstallments AS BOOL)

      AS containsRemadeInstallments



  FROM

    `dadosfinanceiro-501613.raw.vendas`

),



com_mes_ano AS (



  SELECT

    *,



    EXTRACT(

      MONTH FROM contractDate

    ) AS Month,



    EXTRACT(

      YEAR FROM contractDate

    ) AS Year



  FROM fonte

),



com_chave AS (



  SELECT

    *,



    CONCAT(

      CAST(companyId AS STRING),

      '-',

      CAST(receivableBillId AS STRING)

    ) AS ChaveGeral



  FROM com_mes_ano

),



sem_duplicidade AS (



  SELECT

    *



  FROM com_chave



  QUALIFY

    ROW_NUMBER() OVER (

      PARTITION BY ChaveGeral

      ORDER BY id DESC

    ) = 1

),



com_unidades AS (



  SELECT

    v.* EXCEPT(id),



    vu.name,

    vu.ChaveLote



  FROM sem_duplicidade v



  LEFT JOIN

    `dadosfinanceiro-501613.trusted.db_vendas_unidades` vu



    ON

      v.ChaveGeral =

      vu.ChaveGeral

),



com_nome_lote AS (



  SELECT

    *,



    ARRAY_TO_STRING(

      [

        CAST(companyId AS STRING),

        CAST(name AS STRING)

      ],

      '-'

    ) AS NomeLote



  FROM com_unidades

)



SELECT

  ChaveGeral,



  companyId,

  internalCompanyId,

  companyName,



  enterpriseId,

  internalEnterpriseId,

  enterpriseName,



  receivableBillId,

  cancellationPayableBillId,



  documentNumber,



  correctionType,

  situation,

  discountType,

  cancellationReason,

  discountPercentage,



  value,

  totalSellingValue,



  contractDate,

  issueDate,

  expectedDeliveryDate,

  accountingDate,

  keysDeliveredAt,

  cancellationDate,



  totalCancellationAmount,



  creationDate,

  lastUpdateDate,



  financialInstitutionDate,

  financialInstitutionNumber,



  proRataIndexer,

  interestPercentage,

  interestType,

  fineRate,



  lateInterestCalculationType,

  dailyLateInterestValue,



  containsRemadeInstallments,

  specialClause,



  externalId,

  linkedCommissions,



  subdominio,

  ChaveEspecifica,



  registerPropertyDate,



  Month,

  Year,



  name AS Unidade,

  ChaveLote,

  NomeLote



FROM com_nome_lote;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.fato_vendas`

AS



SELECT *

FROM

  `dadosfinanceiro-501613.trusted.vendas`;