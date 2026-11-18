CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.db_recebidas_totalizador` AS

WITH fonte AS (

  SELECT

    ChaveGeral,



    SAFE_CAST(companyId AS INT64) AS companyId,

    SAFE_CAST(billId AS INT64) AS billId,

    SAFE_CAST(clientId AS INT64) AS clientId,



    companyName,

    clientName,

    subdominio,



    SAFE_CAST(dueDate AS DATE) AS dueDate,

    SAFE_CAST(issueDate AS DATE) AS issueDate,

    SAFE_CAST(billDate AS DATE) AS billDate,

    SAFE_CAST(paymentDate AS DATE) AS paymentDate,

    SAFE_CAST(calculationDate AS DATE) AS calculationDate,



    documentIdentificationId,

    documentIdentificationName,

    documentNumber,

    installmentNumber,



    SAFE_CAST(REPLACE(CAST(originalAmount AS STRING), ',', '.') AS NUMERIC) AS originalAmount,

    SAFE_CAST(REPLACE(CAST(grossAmount AS STRING), ',', '.') AS NUMERIC) AS grossAmount,



    SAFE_CAST(REPLACE(CAST(monetaryCorrectionAmount AS STRING), ',', '.') AS NUMERIC) AS monetaryCorrectionAmount,

    SAFE_CAST(REPLACE(CAST(interestAmount AS STRING), ',', '.') AS NUMERIC) AS interestAmount,

    SAFE_CAST(REPLACE(CAST(fineAmount AS STRING), ',', '.') AS NUMERIC) AS fineAmount,

    SAFE_CAST(REPLACE(CAST(discountAmount AS STRING), ',', '.') AS NUMERIC) AS discountAmount,

    SAFE_CAST(REPLACE(CAST(taxAmount AS STRING), ',', '.') AS NUMERIC) AS taxAmount,



    SAFE_CAST(costCenterId AS INT64) AS costCenterId,

    costCenterName,



    SAFE_CAST(operationTypeId AS INT64) AS operationTypeId,

    operationTypeName

  FROM `dadosfinanceiro-501613.trusted.recebidas`

  WHERE ChaveGeral IS NOT NULL

),



base_filtrada AS (

  SELECT *

  FROM fonte

  WHERE operationTypeId = 2

),



agregado AS (

  SELECT

    ChaveGeral,



    MAX(companyId) AS companyId,

    MAX(billId) AS billId,

    MAX(clientId) AS clientId,



    MAX(companyName) AS companyName,

    MAX(clientName) AS clientName,

    MAX(subdominio) AS subdominio,



    MAX(costCenterId) AS costCenterId,

    MAX(costCenterName) AS costCenterName,



    MIN(paymentDate) AS PrimeiraDataRecebimento,

    MAX(paymentDate) AS UltimaDataRecebimento,



    MIN(dueDate) AS PrimeiraDataVencimento,

    MAX(dueDate) AS UltimaDataVencimento,



    MIN(issueDate) AS PrimeiraDataEmissao,

    MAX(issueDate) AS UltimaDataEmissao,



    MIN(billDate) AS PrimeiraDataTitulo,

    MAX(billDate) AS UltimaDataTitulo,



    COUNT(*) AS QuantidadePagamentos,



    SUM(originalAmount) AS ValorOriginalAgregado,



    -- Mantém o nome esperado pelo BI/consultas dependentes.

    -- Como netAmount/correctedNetAmount não existem na trusted.recebidas,

    -- usamos grossAmount, que é o valor disponível da recebida.

    SUM(grossAmount) AS ValorLiquidoAgregado,



    SUM(monetaryCorrectionAmount) AS CorrecaoMonetariaAgregada,

    SUM(interestAmount) AS JurosAgregado,

    SUM(fineAmount) AS MultaAgregada,

    SUM(discountAmount) AS DescontoAgregado,

    SUM(taxAmount) AS TaxaAgregada,



    MAX(

      CASE

        WHEN paymentDate IS NOT NULL AND dueDate IS NOT NULL

        THEN DATE_DIFF(paymentDate, dueDate, DAY)

        ELSE NULL

      END

    ) AS MaiorAtrasoPagamento,



    AVG(

      CASE

        WHEN paymentDate IS NOT NULL AND dueDate IS NOT NULL

        THEN DATE_DIFF(paymentDate, dueDate, DAY)

        ELSE NULL

      END

    ) AS MediaDiasPagamento,



    COUNTIF(paymentDate > dueDate) AS QuantidadePagamentosAtrasados,



    MAX(documentIdentificationId) AS documentIdentificationId,

    MAX(documentIdentificationName) AS documentIdentificationName,

    MAX(documentNumber) AS documentNumber

  FROM base_filtrada

  GROUP BY ChaveGeral

)



SELECT

  ChaveGeral,

  companyId,

  billId,

  clientId,

  companyName,

  clientName,

  subdominio,

  costCenterId,

  costCenterName,



  PrimeiraDataRecebimento,

  UltimaDataRecebimento,

  PrimeiraDataVencimento,

  UltimaDataVencimento,

  PrimeiraDataEmissao,

  UltimaDataEmissao,

  PrimeiraDataTitulo,

  UltimaDataTitulo,



  QuantidadePagamentos,

  QuantidadePagamentosAtrasados,



  ValorOriginalAgregado,

  ValorLiquidoAgregado,



  CorrecaoMonetariaAgregada,

  JurosAgregado,

  MultaAgregada,

  DescontoAgregado,

  TaxaAgregada,



  MaiorAtrasoPagamento,

  MediaDiasPagamento,



  documentIdentificationId,

  documentIdentificationName,

  documentNumber

FROM agregado;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_recebidas_totalizador` AS

SELECT *

FROM `dadosfinanceiro-501613.trusted.db_recebidas_totalizador`;