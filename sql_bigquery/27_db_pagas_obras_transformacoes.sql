-- ####################################################################

-- TRUSTED.DB_PAGAS_OBRAS / ANALYTICS.FATO_PAGAS_OBRAS

--

-- Leitura TOLERANTE do raw.pagas_obras: cada coluna e lida pelo nome via

-- JSON (coluna que nao existe vem NULL em vez de dar erro).

-- Numeros aceitam '1234.56', '1234,56' e '1.234,56'.

--

-- valor_a_pagar, valor_a_pagos e DESCONSIDERAR_PREVISAO NAO vem no raw

-- (o obras_analises.py nao gera). Recriadas aqui com a MESMA regra do

-- notebook Pagas\TESTE_OBRAS.ipynb (celulas 12 e 13), que gerava o CSV do BI:

--   valor_a_pagar = correctedBalanceAmount * rate/100 (rate vazio -> sem %)

--   valor_a_pagos = netAmount * rate/100              (rate vazio -> sem %)

--   DESCONSIDERAR_PREVISAO = True quando documentIdentificationId em

--     PRC/PAF/PCT e dueDate >= 1o dia do mes seguinte a HOJE

-- Se um dia o raw trouxer essas colunas, o valor do raw tem prioridade.

--

-- Previsoes (PPC/PCT/PRC/PAF) fora, conferido com os numeros do BI.

-- Regras do Power Query: DESCONSIDERAR_PREVISAO = False, Valor_Pago,

-- ChavePagasObras, paymentDate1, buildingUnitId = 2.

-- ####################################################################



CREATE TEMP FUNCTION txt(j STRING, c STRING) AS (

  NULLIF(TRIM(JSON_VALUE(j, CONCAT('$."', c, '"'))), '')

);

CREATE TEMP FUNCTION num(j STRING, c STRING) AS (

  SAFE_CAST(

    CASE

      WHEN STRPOS(txt(j, c), ',') > 0

        THEN REPLACE(REPLACE(txt(j, c), '.', ''), ',', '.')

      ELSE txt(j, c)

    END AS NUMERIC)

);

CREATE TEMP FUNCTION inteiro(j STRING, c STRING) AS (

  SAFE_CAST(num(j, c) AS INT64)

);

CREATE TEMP FUNCTION data(j STRING, c STRING) AS (

  COALESCE(SAFE_CAST(SUBSTR(txt(j, c), 1, 10) AS DATE),

           SAFE.PARSE_DATE('%d/%m/%Y', SUBSTR(txt(j, c), 1, 10)))

);





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.db_pagas_obras` AS



WITH



bruto AS (

  SELECT TO_JSON_STRING(r) AS j

  FROM `dadosfinanceiro-501613.raw.pagas_obras` r

),



fonte AS (

  SELECT

    inteiro(j, 'companyId')                AS companyId,

    txt(j, 'companyName')                  AS companyName,

    inteiro(j, 'businessAreaId')           AS businessAreaId,

    txt(j, 'businessAreaName')             AS businessAreaName,

    txt(j, 'projectId')                    AS projectId,

    txt(j, 'projectName')                  AS projectName,

    inteiro(j, 'groupCompanyId')           AS groupCompanyId,

    txt(j, 'groupCompanyName')             AS groupCompanyName,

    inteiro(j, 'holdingId')                AS holdingId,

    txt(j, 'holdingName')                  AS holdingName,

    inteiro(j, 'subsidiaryId')             AS subsidiaryId,

    txt(j, 'subsidiaryName')               AS subsidiaryName,

    inteiro(j, 'businessTypeId')           AS businessTypeId,

    txt(j, 'businessTypeName')             AS businessTypeName,

    inteiro(j, 'creditorId')               AS creditorId,

    txt(j, 'creditorName')                 AS creditorName,

    inteiro(j, 'billId')                   AS billId,

    inteiro(j, 'installmentId')            AS installmentId,

    txt(j, 'documentIdentificationId')     AS documentIdentificationId,

    txt(j, 'documentIdentificationName')   AS documentIdentificationName,

    txt(j, 'documentNumber')               AS documentNumber,

    txt(j, 'forecastDocument')             AS forecastDocument,

    txt(j, 'consistencyStatus')            AS consistencyStatus,

    txt(j, 'originId')                     AS originId,



    num(j, 'originalAmount')               AS originalAmount,

    num(j, 'discountAmount_x')             AS discountAmount_x,

    num(j, 'taxAmount_x')                  AS taxAmount_x,



    inteiro(j, 'indexerId')                AS indexerId,

    txt(j, 'indexerName')                  AS indexerName,

    data(j, 'dueDate')                     AS dueDate,

    data(j, 'issueDate')                   AS issueDate,

    data(j, 'installmentBaseDate')         AS installmentBaseDate,



    num(j, 'balanceAmount')                AS balanceAmount,

    num(j, 'correctedBalanceAmount')       AS correctedBalanceAmount,



    txt(j, 'authorizationStatus')          AS authorizationStatus,

    data(j, 'billDate')                    AS billDate,

    txt(j, 'registeredUserId')             AS registeredUserId,

    txt(j, 'registeredBy')                 AS registeredBy,

    SAFE_CAST(txt(j, 'registeredDate') AS TIMESTAMP) AS registeredDate,

    txt(j, 'payments')                     AS payments,

    txt(j, 'subdominio')                   AS subdominio,



    inteiro(j, 'buildingId')               AS buildingId,

    inteiro(j, 'buildingUnitId')           AS buildingUnitId,

    txt(j, 'buildingName')                 AS buildingName,

    txt(j, 'buildingUnitName')             AS buildingUnitName,

    inteiro(j, 'costEstimationSheetId')    AS costEstimationSheetId,

    txt(j, 'costEstimationSheetName')      AS costEstimationSheetName,



    num(j, 'rate')                         AS rate,

    txt(j, 'chave_referencia')             AS chave_referencia,



    inteiro(j, 'operationTypeId')          AS operationTypeId,

    txt(j, 'operationTypeName')            AS operationTypeName,



    num(j, 'grossAmount')                  AS grossAmount,

    num(j, 'monetaryCorrectionAmount')     AS monetaryCorrectionAmount,

    num(j, 'interestAmount')               AS interestAmount,

    num(j, 'fineAmount')                   AS fineAmount,

    num(j, 'discountAmount_y')             AS discountAmount_y,

    num(j, 'taxAmount_y')                  AS taxAmount_y,

    num(j, 'netAmount')                    AS netAmount,



    data(j, 'calculationDate')             AS calculationDate,

    data(j, 'paymentDate')                 AS paymentDate,



    num(j, 'correctedNetAmount')           AS correctedNetAmount,

    num(j, 'valor_a_pagar')                AS valor_a_pagar_raw,

    num(j, 'valor_a_pagos')                AS valor_a_pagos_raw,



    txt(j, 'DESCONSIDERAR_PREVISAO')       AS DESCONSIDERAR_PREVISAO_raw

  FROM bruto

),



-- regra do notebook TESTE_OBRAS.ipynb (celulas 12 e 13)

com_colunas_notebook AS (

  SELECT

    * EXCEPT (valor_a_pagar_raw, valor_a_pagos_raw, DESCONSIDERAR_PREVISAO_raw),

    COALESCE(valor_a_pagar_raw,

             IF(rate IS NULL, correctedBalanceAmount, correctedBalanceAmount * (rate / 100)))

      AS valor_a_pagar,

    COALESCE(valor_a_pagos_raw,

             IF(rate IS NULL, netAmount, netAmount * (rate / 100)))

      AS valor_a_pagos,

    COALESCE(DESCONSIDERAR_PREVISAO_raw,

             IF(UPPER(TRIM(IFNULL(documentIdentificationId, ''))) IN ('PRC', 'PAF', 'PCT')

                AND dueDate IS NOT NULL

                AND dueDate >= DATE_ADD(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH),

                                        INTERVAL 1 MONTH),

                'True', 'False'))

      AS DESCONSIDERAR_PREVISAO

  FROM fonte

),



filtrado_previsao AS (

  SELECT *

  FROM com_colunas_notebook

  -- aceita False / false / FALSE / 0

  WHERE LOWER(IFNULL(DESCONSIDERAR_PREVISAO, '')) IN ('false', '0')

    -- Previsoes financeiras (PPC, PCT, PRC, PAF) ficam FORA, igual ao BI:

    -- o pago delas e so Substituicao/Cancelamento e o saldo aberto delas

    -- nao entra no A Pagar (conferido: ago/25 A Pagar BI 971,30;

    -- set/24 Vista Bela Pagos BI 1.249.133,22)

    AND UPPER(TRIM(IFNULL(documentIdentificationId, ''))) NOT IN ('PPC', 'PCT', 'PRC', 'PAF')

),



com_valor_pago AS (

  SELECT

    *,

    netAmount * (rate / 100) AS Valor_Pago

  FROM filtrado_previsao

),



com_chave AS (

  SELECT

    *,

    CONCAT(

      CAST(subdominio AS STRING), '-',

      CAST(buildingId AS STRING), '-',

      CAST(buildingUnitId AS STRING), '-',

      CAST(costEstimationSheetId AS STRING)

    ) AS ChavePagasObras

  FROM com_valor_pago

),



com_payment_date_1 AS (

  SELECT

    *,

    -- PQ: if [valor_a_pagos] <> null then [paymentDate] else [dueDate]

    IF(valor_a_pagos IS NOT NULL, paymentDate, dueDate) AS paymentDate1

  FROM com_chave

)



SELECT *

FROM com_payment_date_1

WHERE buildingUnitId = 2;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_pagas_obras` AS

SELECT *

FROM `dadosfinanceiro-501613.trusted.db_pagas_obras`;