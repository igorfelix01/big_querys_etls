-- ####################################################################

-- RECEBIDAS

--

-- FONTES:

-- dadosfinanceiro-501613.raw.recebidas_atualizavel  (dados_atualizaveis.csv)

-- dadosfinanceiro-501613.raw.recebidas_historico    (dados_historicos.csv)

--

-- FIEL AO POWER QUERY: db_recebidas (= db_recebidas_BI)

--

-- Observacao de nomes:

--   paymentTerm.id / paymentTerm.descrition do PQ viram

--   paymentTerm_id / paymentTerm_descrition (BigQuery nao aceita ponto)

-- ####################################################################





CREATE TEMP FUNCTION br_num(valor STRING) AS (

  CASE

    WHEN valor IS NULL OR TRIM(valor) = '' THEN NULL



    WHEN REGEXP_CONTAINS(TRIM(valor), r',') THEN

      SAFE_CAST(

        REPLACE(

          REPLACE(TRIM(valor), '.', ''),

          ',',

          '.'

        ) AS NUMERIC

      )



    ELSE

      SAFE_CAST(

        TRIM(valor)

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





-- Datas: aceita DATE, TIMESTAMP, '2024-10-15', '2024-10-15 00:00:00',

-- '2024-10-15T00:00:00' e '15/10/2024'. (SAFE_CAST direto de texto com

-- hora vira NULL -> os pagamentos ficavam sem data e sumiam do Looker)

CREATE TEMP FUNCTION br_data(valor STRING) AS (

  COALESCE(

    SAFE_CAST(SUBSTR(TRIM(valor), 1, 10) AS DATE),

    SAFE.PARSE_DATE('%d/%m/%Y', SUBSTR(TRIM(valor), 1, 10))

  )

);





-- ============================================================

-- TRAVA DE SEGURANCA: se o raw das recebidas estiver incompleto (carga do

-- Sienge em andamento ou pela metade), PARA aqui e nao sobrescreve a

-- fato_recebidas com dados faltando. (Em 11/11/2026 a fato foi montada

-- durante a recarga do raw e ficou sem 2024.)

-- ============================================================

ASSERT (

  SELECT COUNTIF(SUBSTR(CAST(paymentDate AS STRING), 1, 4) < '2025')

  FROM `dadosfinanceiro-501613.raw.recebidas_historico`

) > 100000

AS 'raw.recebidas_historico incompleto (sem pagamentos antes de 2025): a carga do Sienge esta em andamento ou falhou. Rode de novo depois que ela terminar.';



ASSERT (

  SELECT COUNT(*) FROM `dadosfinanceiro-501613.raw.recebidas_atualizavel`

) > 0

AS 'raw.recebidas_atualizavel vazia: a carga do Sienge esta em andamento ou falhou.';





-- ============================================================

-- TRUSTED.RECEBIDAS

-- ============================================================



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.recebidas` AS



WITH





-- ============================================================

-- 1. DADOS ATUALIZAVEIS

--

-- PQ: remove projectId, projectName, holdingId, holdingName,

--     subsidiaryId, subsidiaryName, businessTypeId,

--     businessTypeName (nao entram no SELECT)

--     + Changed Type da consulta db_recebidas

-- ============================================================



recebidas_atualizavel AS (



  SELECT



    CAST(

      ChaveEspecifica AS STRING

    ) AS ChaveEspecifica,



    CAST(

      subdominio AS STRING

    ) AS subdominio,



    br_int(

      CAST(companyId AS STRING)

    ) AS companyId,



    CAST(

      companyName AS STRING

    ) AS companyName,



    br_int(

      CAST(businessAreaId AS STRING)

    ) AS businessAreaId,



    CAST(

      businessAreaName AS STRING

    ) AS businessAreaName,



    br_int(

      CAST(groupCompanyId AS STRING)

    ) AS groupCompanyId,



    CAST(

      groupCompanyName AS STRING

    ) AS groupCompanyName,



    br_int(

      CAST(clientId AS STRING)

    ) AS clientId,



    CAST(

      clientName AS STRING

    ) AS clientName,



    br_int(

      CAST(billId AS STRING)

    ) AS billId,



    br_int(

      CAST(installmentId AS STRING)

    ) AS installmentId,



    CAST(

      documentIdentificationId AS STRING

    ) AS documentIdentificationId,



    CAST(

      documentIdentificationName AS STRING

    ) AS documentIdentificationName,



    CAST(

      documentNumber AS STRING

    ) AS documentNumber,



    CAST(

      documentForecast AS STRING

    ) AS documentForecast,



    CAST(

      originId AS STRING

    ) AS originId,



    br_num(

      CAST(originalAmount AS STRING)

    ) AS originalAmount,



    br_num(

      CAST(discountAmount AS STRING)

    ) AS discountAmount,



    br_num(

      CAST(taxAmount AS STRING)

    ) AS taxAmount,



    br_num(

      CAST(indexerId AS STRING)

    ) AS indexerId,



    CAST(

      indexerName AS STRING

    ) AS indexerName,



    br_data(CAST(dueDate AS STRING)) AS dueDate,



    br_data(CAST(issueDate AS STRING)) AS issueDate,



    br_data(CAST(billDate AS STRING)) AS billDate,



    br_data(CAST(installmentBaseDate AS STRING)) AS installmentBaseDate,



    br_num(

      CAST(balanceAmount AS STRING)

    ) AS balanceAmount,



    br_num(

      CAST(correctedBalanceAmount AS STRING)

    ) AS correctedBalanceAmount,



    CAST(

      periodicityType AS STRING

    ) AS periodicityType,



    br_num(

      CAST(embeddedInterestAmount AS STRING)

    ) AS embeddedInterestAmount,



    CAST(

      interestType AS STRING

    ) AS interestType,



    br_num(

      CAST(interestRate AS STRING)

    ) AS interestRate,



    CAST(

      correctionType AS STRING

    ) AS correctionType,



    br_data(CAST(interestBaseDate AS STRING)) AS interestBaseDate,



    CAST(

      defaulterSituation AS STRING

    ) AS defaulterSituation,



    CAST(

      subJudicie AS STRING

    ) AS subJudicie,



    CAST(

      mainUnit AS STRING

    ) AS mainUnit,



    -- PQ usa a coluna installmentNumber, que NAO existe no raw.

    -- Reconstruida a partir da ChaveEspecifica (tudo apos o 2o '-').

    -- Conferir com a consulta DIAGNOSTICO INSTALLMENTNUMBER no fim.

    REGEXP_EXTRACT(

      CAST(ChaveEspecifica AS STRING),

      r'^[^-]+-[^-]+-(.*)$'

    ) AS installmentNumber,



    CAST(

      paymentTerm_id AS STRING

    ) AS paymentTerm_id,



    CAST(

      paymentTerm_descrition AS STRING

    ) AS paymentTerm_descrition,



    br_int(

      CAST(costCenterId AS STRING)

    ) AS costCenterId,



    CAST(

      costCenterName AS STRING

    ) AS costCenterName,



    br_int(

      CAST(financialCategoryId AS STRING)

    ) AS financialCategoryId,



    CAST(

      financialCategoryName AS STRING

    ) AS financialCategoryName,



    CAST(

      financialCategoryReducer AS STRING

    ) AS financialCategoryReducer,



    CAST(

      financialCategoryType AS STRING

    ) AS financialCategoryType,



    -- PQ db_recebidas: type number

    br_num(

      CAST(financialCategoryRate AS STRING)

    ) AS financialCategoryRate,



    br_int(

      CAST(operationTypeId AS STRING)

    ) AS operationTypeId,



    CAST(

      operationTypeName AS STRING

    ) AS operationTypeName,



    br_num(

      CAST(grossAmount AS STRING)

    ) AS grossAmount,



    br_num(

      CAST(monetaryCorrectionAmount AS STRING)

    ) AS monetaryCorrectionAmount,



    br_num(

      CAST(interestAmount AS STRING)

    ) AS interestAmount,



    br_num(

      CAST(fineAmount AS STRING)

    ) AS fineAmount,



    br_num(

      CAST(discountAmount_recepts AS STRING)

    ) AS discountAmount_recepts,



    br_num(

      CAST(taxAmount_recepts AS STRING)

    ) AS taxAmount_recepts,



    br_num(

      CAST(netAmount AS STRING)

    ) AS netAmount,



    br_num(

      CAST(additionAmount AS STRING)

    ) AS additionAmount,



    br_num(

      CAST(insuranceAmount AS STRING)

    ) AS insuranceAmount,



    br_num(

      CAST(dueAdmAmount AS STRING)

    ) AS dueAdmAmount,



    br_data(CAST(calculationDate AS STRING)) AS calculationDate,



    br_data(CAST(paymentDate AS STRING)) AS paymentDate,



    br_int(

      CAST(accountCompanyId AS STRING)

    ) AS accountCompanyId,



    CAST(

      accountNumber AS STRING

    ) AS accountNumber,



    CAST(

      accountType AS STRING

    ) AS accountType,



    br_int(

      CAST(sequencialNumber AS STRING)

    ) AS sequencialNumber,



    br_int(

      CAST(indexerId_recepts AS STRING)

    ) AS indexerId_recepts,



    br_int(

      CAST(

        embeddedInterestAmount_recepts

        AS STRING

      )

    ) AS embeddedInterestAmount_recepts,



    br_int(

      CAST(proRata AS STRING)

    ) AS proRata



  FROM

    `dadosfinanceiro-501613.raw.recebidas_atualizavel`

),





-- ============================================================

-- 2. DADOS HISTORICOS

--

-- PQ: consulta Dados_Historicos_Recebimentos

--     mesma remocao de colunas; tipos iguais, EXCETO:

--     financialCategoryRate = Int64.Type (arredonda para inteiro)

-- ============================================================



recebidas_historico AS (



  SELECT



    CAST(

      ChaveEspecifica AS STRING

    ) AS ChaveEspecifica,



    CAST(

      subdominio AS STRING

    ) AS subdominio,



    br_int(

      CAST(companyId AS STRING)

    ) AS companyId,



    CAST(

      companyName AS STRING

    ) AS companyName,



    br_int(

      CAST(businessAreaId AS STRING)

    ) AS businessAreaId,



    CAST(

      businessAreaName AS STRING

    ) AS businessAreaName,



    br_int(

      CAST(groupCompanyId AS STRING)

    ) AS groupCompanyId,



    CAST(

      groupCompanyName AS STRING

    ) AS groupCompanyName,



    br_int(

      CAST(clientId AS STRING)

    ) AS clientId,



    CAST(

      clientName AS STRING

    ) AS clientName,



    br_int(

      CAST(billId AS STRING)

    ) AS billId,



    br_int(

      CAST(installmentId AS STRING)

    ) AS installmentId,



    CAST(

      documentIdentificationId AS STRING

    ) AS documentIdentificationId,



    CAST(

      documentIdentificationName AS STRING

    ) AS documentIdentificationName,



    CAST(

      documentNumber AS STRING

    ) AS documentNumber,



    CAST(

      documentForecast AS STRING

    ) AS documentForecast,



    CAST(

      originId AS STRING

    ) AS originId,



    br_num(

      CAST(originalAmount AS STRING)

    ) AS originalAmount,



    br_num(

      CAST(discountAmount AS STRING)

    ) AS discountAmount,



    br_num(

      CAST(taxAmount AS STRING)

    ) AS taxAmount,



    br_num(

      CAST(indexerId AS STRING)

    ) AS indexerId,



    CAST(

      indexerName AS STRING

    ) AS indexerName,



    br_data(CAST(dueDate AS STRING)) AS dueDate,



    br_data(CAST(issueDate AS STRING)) AS issueDate,



    br_data(CAST(billDate AS STRING)) AS billDate,



    br_data(CAST(installmentBaseDate AS STRING)) AS installmentBaseDate,



    br_num(

      CAST(balanceAmount AS STRING)

    ) AS balanceAmount,



    br_num(

      CAST(correctedBalanceAmount AS STRING)

    ) AS correctedBalanceAmount,



    CAST(

      periodicityType AS STRING

    ) AS periodicityType,



    br_num(

      CAST(embeddedInterestAmount AS STRING)

    ) AS embeddedInterestAmount,



    CAST(

      interestType AS STRING

    ) AS interestType,



    br_num(

      CAST(interestRate AS STRING)

    ) AS interestRate,



    CAST(

      correctionType AS STRING

    ) AS correctionType,



    br_data(CAST(interestBaseDate AS STRING)) AS interestBaseDate,



    CAST(

      defaulterSituation AS STRING

    ) AS defaulterSituation,



    CAST(

      subJudicie AS STRING

    ) AS subJudicie,



    CAST(

      mainUnit AS STRING

    ) AS mainUnit,



    -- PQ usa a coluna installmentNumber, que NAO existe no raw.

    -- Reconstruida a partir da ChaveEspecifica (tudo apos o 2o '-').

    -- Conferir com a consulta DIAGNOSTICO INSTALLMENTNUMBER no fim.

    REGEXP_EXTRACT(

      CAST(ChaveEspecifica AS STRING),

      r'^[^-]+-[^-]+-(.*)$'

    ) AS installmentNumber,



    CAST(

      paymentTerm_id AS STRING

    ) AS paymentTerm_id,



    CAST(

      paymentTerm_descrition AS STRING

    ) AS paymentTerm_descrition,



    br_int(

      CAST(costCenterId AS STRING)

    ) AS costCenterId,



    CAST(

      costCenterName AS STRING

    ) AS costCenterName,



    br_int(

      CAST(financialCategoryId AS STRING)

    ) AS financialCategoryId,



    CAST(

      financialCategoryName AS STRING

    ) AS financialCategoryName,



    CAST(

      financialCategoryReducer AS STRING

    ) AS financialCategoryReducer,



    CAST(

      financialCategoryType AS STRING

    ) AS financialCategoryType,



    -- PQ Dados_Historicos_Recebimentos: Int64.Type

    -- (arredonda; volta para NUMERIC para o UNION)

    CAST(

      br_int(

        CAST(financialCategoryRate AS STRING)

      ) AS NUMERIC

    ) AS financialCategoryRate,



    br_int(

      CAST(operationTypeId AS STRING)

    ) AS operationTypeId,



    CAST(

      operationTypeName AS STRING

    ) AS operationTypeName,



    br_num(

      CAST(grossAmount AS STRING)

    ) AS grossAmount,



    br_num(

      CAST(monetaryCorrectionAmount AS STRING)

    ) AS monetaryCorrectionAmount,



    br_num(

      CAST(interestAmount AS STRING)

    ) AS interestAmount,



    br_num(

      CAST(fineAmount AS STRING)

    ) AS fineAmount,



    br_num(

      CAST(discountAmount_recepts AS STRING)

    ) AS discountAmount_recepts,



    br_num(

      CAST(taxAmount_recepts AS STRING)

    ) AS taxAmount_recepts,



    br_num(

      CAST(netAmount AS STRING)

    ) AS netAmount,



    br_num(

      CAST(additionAmount AS STRING)

    ) AS additionAmount,



    br_num(

      CAST(insuranceAmount AS STRING)

    ) AS insuranceAmount,



    br_num(

      CAST(dueAdmAmount AS STRING)

    ) AS dueAdmAmount,



    br_data(CAST(calculationDate AS STRING)) AS calculationDate,



    br_data(CAST(paymentDate AS STRING)) AS paymentDate,



    br_int(

      CAST(accountCompanyId AS STRING)

    ) AS accountCompanyId,



    CAST(

      accountNumber AS STRING

    ) AS accountNumber,



    CAST(

      accountType AS STRING

    ) AS accountType,



    br_int(

      CAST(sequencialNumber AS STRING)

    ) AS sequencialNumber,



    br_int(

      CAST(indexerId_recepts AS STRING)

    ) AS indexerId_recepts,



    br_int(

      CAST(

        embeddedInterestAmount_recepts

        AS STRING

      )

    ) AS embeddedInterestAmount_recepts,



    br_int(

      CAST(proRata AS STRING)

    ) AS proRata



  FROM

    `dadosfinanceiro-501613.raw.recebidas_historico`

),





-- ============================================================

-- 3. APPEND (Table.Combine)

-- as duas CTEs tem as mesmas colunas na mesma ordem

-- ============================================================



base_unificada_bruta AS (



  SELECT *, 1 AS prioridade_origem

  FROM recebidas_atualizavel



  UNION ALL



  SELECT *, 2 AS prioridade_origem

  FROM recebidas_historico

),





-- ============================================================

-- 3b. SEM BAIXAS REPETIDAS

-- A carga do Sienge pode gravar o mesmo periodo duas vezes no raw

-- (em 11/11/2026 o historico ficou com 2025 a ago/2026 em dobro) ou

-- repetir a baixa no historico e no atualizavel. Fica 1 linha por baixa

-- (mesma parcela, vencimento, pagamento, operacao, valor, conta e

-- numero sequencial), dando preferencia ao atualizavel.

-- ============================================================



base_unificada AS (



  SELECT * EXCEPT (prioridade_origem)

  FROM base_unificada_bruta

  QUALIFY ROW_NUMBER() OVER (

    PARTITION BY

      ChaveEspecifica, installmentId, dueDate, paymentDate, operationTypeId,

      netAmount, accountNumber, sequencialNumber

    ORDER BY prioridade_origem

  ) = 1

),





-- ============================================================

-- 4. FILTRO OPERATION TYPE

-- ============================================================



filtrado AS (



  SELECT *

  FROM base_unificada



  WHERE operationTypeId = 2

),





-- ============================================================

-- 5. ANO / MES

-- ============================================================



com_datas AS (



  SELECT

    *,



    EXTRACT(

      YEAR FROM paymentDate

    ) AS paymentYear,



    EXTRACT(

      YEAR FROM dueDate

    ) AS dueYear,



    EXTRACT(

      MONTH FROM paymentDate

    ) AS paymentMonth,



    EXTRACT(

      MONTH FROM dueDate

    ) AS dueMonth



  FROM filtrado

),





-- ============================================================

-- 6. PARCELAS

--

-- PQ: Text.BeforeDelimiter / Text.AfterDelimiter "/"

--     tipo = number (nao Int64) -> NUMERIC

-- ============================================================



com_parcelas AS (



  SELECT

    *,



    SAFE_CAST(

      SPLIT(

        installmentNumber,

        '/'

      )[SAFE_OFFSET(0)]

      AS NUMERIC

    ) AS ParcelaRecebida,



    SAFE_CAST(

      SPLIT(

        installmentNumber,

        '/'

      )[SAFE_OFFSET(1)]

      AS NUMERIC

    ) AS TotalParcelas



  FROM com_datas

),





-- ============================================================

-- 7. CHAVE GERAL

-- companyId-billId  (ARRAY_TO_STRING ignora NULL = Text.Combine)

-- ============================================================



com_chave AS (



  SELECT

    *,



    ARRAY_TO_STRING(

      [

        CAST(companyId AS STRING),

        CAST(billId AS STRING)

      ],

      '-'

    ) AS ChaveGeral



  FROM com_parcelas

),





-- ============================================================

-- 8. NET AMOUNT -> VALOR BRUTO

-- ============================================================



renomeado AS (



  SELECT

    * EXCEPT (

      netAmount

    ),



    netAmount AS ValorBruto



  FROM com_chave

),





-- ============================================================

-- 9. CONTAS BANCARIAS

--

-- PQ: LEFT JOIN em accountNumber.

-- No BigQuery o accountNumber do raw e da dimensao chegam com

-- espacos / espaco especial (CHR 160) que nao existem no BI.

-- A limpeza abaixo e necessaria para o resultado bater com o BI

-- (join exato deixava Conta NULL e zerava o Efeito Caixa).

-- ============================================================



com_conta AS (



  SELECT

    r.*,

    cb.Conta



  FROM renomeado r



  LEFT JOIN

    `dadosfinanceiro-501613.analytics.dim_contas_bancarias` cb



    ON

      REPLACE(

        TRIM(

          CAST(r.accountNumber AS STRING)

        ),

        CHR(160),

        ''

      )

      =

      REPLACE(

        TRIM(

          CAST(cb.accountNumber AS STRING)

        ),

        CHR(160),

        ''

      )

),





-- ============================================================

-- 10. CHAVE EMPREENDIMENTO / LOTE

-- companyId-costCenterId-mainUnit

-- ============================================================



final AS (



  SELECT

    *,



    ARRAY_TO_STRING(

      [

        CAST(companyId AS STRING),

        CAST(costCenterId AS STRING),

        CAST(mainUnit AS STRING)

      ],

      '-'

    ) AS ChaveEmpreendimentoLote



  FROM com_conta

)



SELECT *

FROM final;





-- ============================================================

-- ANALYTICS

-- ============================================================



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.fato_recebidas`



CLUSTER BY

  Conta,

  documentIdentificationId,

  companyId,

  ChaveGeral



AS



SELECT *

FROM

  `dadosfinanceiro-501613.trusted.recebidas`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO

-- ####################################################################



-- totais gerais

-- SELECT



--   COUNT(*) AS total_trusted,



--   COUNTIF(paymentDate IS NULL)       AS paymentDate_nulo,

--   COUNTIF(dueDate IS NULL)           AS dueDate_nulo,

--   COUNTIF(installmentNumber IS NULL) AS installmentNumber_nulo,

--   COUNTIF(ParcelaRecebida IS NULL)   AS parcela_nao_convertida,

--   COUNTIF(Conta IS NULL)             AS sem_conta_bancaria,



--   MIN(paymentDate) AS primeiro_pagamento,

--   MAX(paymentDate) AS ultimo_pagamento,



--   SUM(ValorBruto)  AS soma_ValorBruto



-- FROM

--   `dadosfinanceiro-501613.trusted.recebidas`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- linhas por origem antes do filtro (confere o append)

-- SELECT

--   'atualizavel' AS origem,

--   COUNT(*)      AS linhas

-- FROM

--   `dadosfinanceiro-501613.raw.recebidas_atualizavel`



-- UNION ALL



-- SELECT

--   'historico',

--   COUNT(*)

-- FROM

--   `dadosfinanceiro-501613.raw.recebidas_historico`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- accountNumber duplicado na dimensao (multiplica linhas no join)

-- SELECT

--   accountNumber,

--   COUNT(*) AS qtd

-- FROM

--   `dadosfinanceiro-501613.analytics.dim_contas_bancarias`

-- GROUP BY

--   accountNumber

-- HAVING

--   COUNT(*) > 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- contas sem match: se aparecer diferenca so por espaco/zero a

-- esquerda, o problema esta na carga da dimensao, nao no join

-- SELECT

--   accountNumber,

--   COUNT(*) AS linhas

-- FROM

--   `dadosfinanceiro-501613.trusted.recebidas`

-- WHERE

--   Conta IS NULL

-- GROUP BY

--   accountNumber

-- ORDER BY

--   linhas DESC

-- LIMIT 50;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- DIAGNOSTICO INSTALLMENTNUMBER

-- ####################################################################



-- 1) colunas reais do raw (procurar algo como installment / parcela)

-- SELECT

--   table_name,

--   column_name,

--   data_type

-- FROM

--   `dadosfinanceiro-501613.raw.INFORMATION_SCHEMA.COLUMNS`

-- WHERE

--   table_name IN ('recebidas_atualizavel', 'recebidas_historico')

--   AND (

--     LOWER(column_name) LIKE '%installment%'

--     OR LOWER(column_name) LIKE '%parcela%'

--     OR LOWER(column_name) LIKE '%chave%'

--   )

-- ORDER BY

--   table_name,

--   column_name;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- 2) installmentNumber reconstruido deve ter o formato 'N/TOTAL'

-- SELECT

--   COUNT(*) AS total,

--   COUNTIF(installmentNumber IS NULL) AS nulo,

--   COUNTIF(NOT REGEXP_CONTAINS(installmentNumber, r'^\d+/\d+$')) AS fora_do_formato

-- FROM

--   `dadosfinanceiro-501613.trusted.recebidas`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- 3) amostra para conferencia visual

-- SELECT

--   ChaveEspecifica,

--   installmentNumber,

--   ParcelaRecebida,

--   TotalParcelas

-- FROM

--   `dadosfinanceiro-501613.trusted.recebidas`

-- LIMIT 20;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA: baixas repetidas no raw (mesma chave mais de 1 vez), por ano

-- ####################################################################

-- SELECT

--   SUBSTR(CAST(paymentDate AS STRING), 1, 4) AS ano,

--   COUNT(*)                                  AS linhas_raw,

--   COUNT(DISTINCT TO_JSON_STRING(STRUCT(ChaveEspecifica, installmentId, dueDate, paymentDate,

--         operationTypeId, netAmount, accountNumber, sequencialNumber))) AS baixas_unicas

-- FROM `dadosfinanceiro-501613.raw.recebidas_historico`

-- WHERE SUBSTR(CAST(paymentDate AS STRING), 1, 4) >= '2024'

-- GROUP BY 1

-- ORDER BY 1;