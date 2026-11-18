-- ####################################################################

-- 15_areceber_transformacoes

--

-- FONTE:

-- dadosfinanceiro-501613.raw.areceber

--

-- FIEL AO POWER QUERY: db_a_receber (= db_a_receber_BI)

--   - interestRate / 100

--   - situacaoInicialAR pela regra de mes/ano do vencimento

--   - percentual NULL permanece NULL (Bloko/Parceiro ficam NULL)

--   - chaves concatenadas ignorando NULL (igual Text.Combine)

--   - celulas que dariam erro no PQ ficam NULL

-- ####################################################################





-- ====================================================================

-- FUNCOES AUXILIARES

-- ====================================================================



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

          TRIM(valor),

          '.',

          ''

        ),

        ',',

        '.'

      )

      AS NUMERIC

    )



    ELSE SAFE_CAST(

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





-- ####################################################################

-- TRUSTED.ARECEBER

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.areceber`

AS



WITH





-- ====================================================================

-- 1. REMOVER COLUNAS

-- ====================================================================



removed_columns AS (



  SELECT

    * EXCEPT (

      projectId,

      projectName,

      holdingId,

      holdingName,

      subsidiaryId,

      subsidiaryName,

      businessTypeId,

      businessTypeName

    )



  FROM

    `dadosfinanceiro-501613.raw.areceber`



),





-- ====================================================================

-- 2. ALTERAR TIPOS

--

-- billId_raw: valor original, usado apenas no passo 3 para

-- reproduzir Table.RemoveRowsWithErrors

-- ====================================================================



changed_type AS (



  SELECT



    * EXCEPT (

      companyId,

      businessAreaId,

      groupCompanyId,

      clientId,

      billId,

      installmentId,

      originalAmount,

      discountAmount,

      taxAmount,

      indexerId,

      dueDate,

      issueDate,

      billDate,

      installmentBaseDate,

      balanceAmount,

      correctedBalanceAmount,

      embeddedInterestAmount,

      interestRate,

      interestBaseDate,

      financialCategoryRate,

      costCenterId,

      financialCategoryId

    ),





    br_int(

      CAST(companyId AS STRING)

    ) AS companyId,





    br_int(

      CAST(businessAreaId AS STRING)

    ) AS businessAreaId,





    br_int(

      CAST(groupCompanyId AS STRING)

    ) AS groupCompanyId,





    br_int(

      CAST(clientId AS STRING)

    ) AS clientId,





    CAST(billId AS STRING)

      AS billId_raw,





    br_int(

      CAST(billId AS STRING)

    ) AS billId,





    br_int(

      CAST(installmentId AS STRING)

    ) AS installmentId,





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





    SAFE_CAST(

      dueDate

      AS DATE

    ) AS dueDate,





    SAFE_CAST(

      issueDate

      AS DATE

    ) AS issueDate,





    SAFE_CAST(

      billDate

      AS DATE

    ) AS billDate,





    SAFE_CAST(

      installmentBaseDate

      AS DATE

    ) AS installmentBaseDate,





    br_num(

      CAST(balanceAmount AS STRING)

    ) AS balanceAmount,





    br_num(

      CAST(

        correctedBalanceAmount

        AS STRING

      )

    ) AS correctedBalanceAmount,





    br_num(

      CAST(

        embeddedInterestAmount

        AS STRING

      )

    ) AS embeddedInterestAmount,





    br_num(

      CAST(interestRate AS STRING)

    ) AS interestRate,





    SAFE_CAST(

      interestBaseDate

      AS DATE

    ) AS interestBaseDate,





    br_num(

      CAST(

        financialCategoryRate

        AS STRING

      )

    ) AS financialCategoryRate,





    br_int(

      CAST(costCenterId AS STRING)

    ) AS costCenterId,





    br_int(

      CAST(

        financialCategoryId

        AS STRING

      )

    ) AS financialCategoryId





  FROM

    removed_columns



),





-- ====================================================================

-- 3. REMOVER ERROS DE BILLID

--

-- POWER QUERY:

-- Table.RemoveRowsWithErrors(... {"billId"})

--

-- Remove apenas linhas cujo billId tinha valor e NAO converteu.

-- billId vazio vira null no PQ e a linha permanece.

-- ====================================================================



removed_errors AS (



  SELECT

    * EXCEPT (

      billId_raw

    )



  FROM

    changed_type



  WHERE

    NOT (

      billId_raw IS NOT NULL

      AND TRIM(billId_raw) <> ''

      AND billId IS NULL

    )



),





-- ====================================================================

-- 4. INTEREST RATE

--

-- POWER QUERY (db_a_receber):

-- interestRate / 100

-- ====================================================================



divided_column AS (



  SELECT

    * EXCEPT (

      interestRate

    ),



    interestRate / 100

      AS interestRate



  FROM

    removed_errors



),





-- ====================================================================

-- 5. ATRASO DIAS

--

-- POWER QUERY:

-- Duration.Days(Date.From(DateTime.LocalNow()) - [dueDate])

-- ====================================================================



added_custom AS (



  SELECT

    *,



    DATE_DIFF(

      CURRENT_DATE(

        'America/Sao_Paulo'

      ),

      dueDate,

      DAY

    ) AS atrasoDias



  FROM

    divided_column



),





-- ====================================================================

-- 6. SITUACAO INICIAL

--

-- POWER QUERY (db_a_receber):

-- fimdoano(due) >  fimdoano(hoje)                      -> Adimplente

-- fimdoano(due) =  fimdoano(hoje)

--   AND fimdomes(due) >= fimdomes(hoje)                -> Adimplente

-- dias de atraso <= 90                                 -> Atrasado

-- senao                                                -> Inadimplente

--

-- (equivale a: vencimento no mes atual ou futuro = Adimplente)

-- dueDate nulo gera erro no PQ -> NULL aqui

-- ====================================================================



added_custom1 AS (



  SELECT

    *,



    CASE



      WHEN dueDate IS NULL

      THEN NULL





      WHEN EXTRACT(YEAR FROM dueDate)

         > EXTRACT(YEAR FROM CURRENT_DATE('America/Sao_Paulo'))

      THEN 'Adimplente'





      WHEN EXTRACT(YEAR FROM dueDate)

         = EXTRACT(YEAR FROM CURRENT_DATE('America/Sao_Paulo'))

       AND EXTRACT(MONTH FROM dueDate)

         >= EXTRACT(MONTH FROM CURRENT_DATE('America/Sao_Paulo'))

      THEN 'Adimplente'





      WHEN DATE_DIFF(

        CURRENT_DATE(

          'America/Sao_Paulo'

        ),

        dueDate,

        DAY

      ) <= 90

      THEN 'Atrasado'





      ELSE 'Inadimplente'



    END AS situacaoInicialAR



  FROM

    added_custom



),





-- ====================================================================

-- 7. TIPAGEM

-- ====================================================================



changed_type1 AS (



  SELECT



    * EXCEPT (

      atrasoDias,

      companyId,

      situacaoInicialAR

    ),





    SAFE_CAST(

      atrasoDias

      AS NUMERIC

    ) AS atrasoDias,





    SAFE_CAST(

      companyId

      AS INT64

    ) AS companyId,





    CAST(

      situacaoInicialAR

      AS STRING

    ) AS situacaoInicialAR





  FROM

    added_custom1



),





-- ====================================================================

-- 8. ANO VENCIMENTO

-- ====================================================================



inserted_year AS (



  SELECT

    *,



    EXTRACT(

      YEAR

      FROM dueDate

    ) AS dueYear



  FROM

    changed_type1



),





-- ====================================================================

-- 9. MES VENCIMENTO

-- ====================================================================



inserted_month AS (



  SELECT

    *,



    EXTRACT(

      MONTH

      FROM dueDate

    ) AS dueMonth



  FROM

    inserted_year



),





-- ====================================================================

-- 10. CHAVE GERAL

-- companyId-billId

--

-- ARRAY_TO_STRING ignora NULL, igual Text.Combine do PQ

-- ====================================================================



inserted_merged_column AS (



  SELECT

    *,



    ARRAY_TO_STRING(

      [

        CAST(companyId AS STRING),

        CAST(billId AS STRING)

      ],

      '-'

    ) AS ChaveGeral



  FROM

    inserted_month



),





-- ====================================================================

-- 11. CHAVE EMPREENDIMENTO LOTE

-- companyId-costCenterId-mainUnit

-- ====================================================================



inserted_merged_column1 AS (



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



  FROM

    inserted_merged_column



),





-- ====================================================================

-- 12. 1 MES CAPITALIZACAO

-- ====================================================================



added_custom2 AS (



  SELECT

    *,



    -(

      (

        EXTRACT(

          YEAR

          FROM CURRENT_DATE(

            'America/Sao_Paulo'

          )

        )

        -

        EXTRACT(

          YEAR

          FROM dueDate

        )

      ) * 12



      +



      (

        EXTRACT(

          MONTH

          FROM CURRENT_DATE(

            'America/Sao_Paulo'

          )

        )

        -

        EXTRACT(

          MONTH

          FROM dueDate

        )

      )

    ) AS `1MesCapitalizacao`



  FROM

    inserted_merged_column1



),





-- ====================================================================

-- 13. TIPAGEM 1 MES CAPITALIZACAO

-- ====================================================================



changed_type2 AS (



  SELECT



    * EXCEPT (

      `1MesCapitalizacao`

    ),



    SAFE_CAST(

      `1MesCapitalizacao`

      AS INT64

    ) AS `1MesCapitalizacao`



  FROM

    added_custom2



),





-- ====================================================================

-- 14. VALOR PRESENTE

--

-- POWER QUERY:

-- if [1MesCapitalizacao] <= 0 then [originalAmount]

-- else if rate <> 0 and periods <> 0

--      then FV / (1 + rate) ^ periods

--      else [originalAmount]

--

-- Comportamento de NULL igual ao PQ:

--   1MesCapitalizacao nulo -> erro no PQ -> NULL

--   interestRate nulo      -> (null <> 0) = true no PQ -> conta com

--                             null -> NULL

-- ====================================================================



added_custom3 AS (



  SELECT

    *,



    CASE



      WHEN `1MesCapitalizacao` IS NULL

      THEN NULL





      WHEN `1MesCapitalizacao` <= 0

      THEN originalAmount





      WHEN interestRate IS NULL

      THEN NULL





      WHEN interestRate <> 0

       AND `1MesCapitalizacao` <> 0

      THEN originalAmount

        /

        POW(

          1 + CAST(

            interestRate

            AS FLOAT64

          ),

          `1MesCapitalizacao`

        )





      ELSE originalAmount



    END AS ValorPresente



  FROM

    changed_type2



),





-- ====================================================================

-- 15. TIPAGEM VALOR PRESENTE

-- ====================================================================



changed_type3 AS (



  SELECT



    * EXCEPT (

      ValorPresente

    ),



    SAFE_CAST(

      ValorPresente

      AS NUMERIC

    ) AS ValorPresente



  FROM

    added_custom3



),





-- ====================================================================

-- 16. PARCELA AR

-- Text.BeforeDelimiter([installmentNumber], "/")

-- ====================================================================



added_custom4 AS (



  SELECT

    *,



    SPLIT(

      CAST(

        installmentNumber

        AS STRING

      ),

      '/'

    )[SAFE_OFFSET(0)] AS ParcelaAR



  FROM

    changed_type3



),





-- ====================================================================

-- 17. TOTAL PARCELAS

-- Text.AfterDelimiter([installmentNumber], "/")

-- ====================================================================



added_custom5 AS (



  SELECT

    *,



    SPLIT(

      CAST(

        installmentNumber

        AS STRING

      ),

      '/'

    )[SAFE_OFFSET(1)] AS TotalParcelas



  FROM

    added_custom4



),





-- ====================================================================

-- 18. TIPAGEM PARCELAS

-- ====================================================================



changed_type4 AS (



  SELECT



    * EXCEPT (

      ParcelaAR,

      TotalParcelas

    ),





    SAFE_CAST(

      ParcelaAR

      AS INT64

    ) AS ParcelaAR,





    SAFE_CAST(

      TotalParcelas

      AS INT64

    ) AS TotalParcelas





  FROM

    added_custom5



),





-- ====================================================================

-- 19. MERGE COM UNIDADES

-- LEFT JOIN db_unidades on ChaveEmpreendimentoLote

-- ====================================================================



merged_queries AS (



  SELECT

    a.*,



    u.situationId,



    u.percentual



  FROM

    changed_type4 AS a



  LEFT JOIN

    `dadosfinanceiro-501613.analytics.dim_unidades`

      AS u



    ON a.ChaveEmpreendimentoLote =

       u.ChaveEmpreendimentoLote



),





-- ====================================================================

-- 20. RENOMEAR CORRECTEDBALANCEAMOUNT PARA VALORBRUTO

-- ====================================================================



renamed_columns AS (



  SELECT



    * EXCEPT (

      correctedBalanceAmount

    ),



    correctedBalanceAmount

      AS ValorBruto



  FROM

    merged_queries



),





-- ====================================================================

-- 21. VALOR BLOKO

-- ValorBruto * percentual  (percentual NULL -> NULL, igual PQ)

-- ====================================================================



added_custom6 AS (



  SELECT

    *,



    ValorBruto

      * percentual

      AS ValorBloko



  FROM

    renamed_columns



),





-- ====================================================================

-- 22. VALOR PARCEIRO

-- ====================================================================



added_custom7 AS (



  SELECT

    *,



    ValorBruto

      - ValorBloko

      AS ValorParceiro



  FROM

    added_custom6



),





-- ====================================================================

-- 23. VALOR PRESENTE BLOKO

-- ====================================================================



added_custom8 AS (



  SELECT

    *,



    ValorPresente

      * percentual

      AS ValorPresenteBloko



  FROM

    added_custom7



),





-- ====================================================================

-- 24. VALOR PRESENTE PARCEIRO

-- ====================================================================



added_custom9 AS (



  SELECT

    *,



    ValorPresente

      - ValorPresenteBloko

      AS ValorPresenteParceiro



  FROM

    added_custom8



),





-- ====================================================================

-- 25. VALOR ORIGINAL BLOKO

-- ====================================================================



added_custom10 AS (



  SELECT

    *,



    originalAmount

      * percentual

      AS ValorOriginalBloko



  FROM

    added_custom9



),





-- ====================================================================

-- 26. VALOR ORIGINAL PARCEIRO

-- ====================================================================



added_custom11 AS (



  SELECT

    *,



    originalAmount

      - ValorOriginalBloko

      AS ValorOriginalParceiro



  FROM

    added_custom10



),





-- ====================================================================

-- 27. TIPAGEM DOS VALORES

-- ====================================================================



changed_type5 AS (



  SELECT



    * EXCEPT (

      ValorBloko,

      ValorParceiro,

      ValorPresenteBloko,

      ValorPresenteParceiro,

      ValorOriginalBloko,

      ValorOriginalParceiro

    ),





    SAFE_CAST(

      ValorBloko

      AS NUMERIC

    ) AS ValorBloko,





    SAFE_CAST(

      ValorParceiro

      AS NUMERIC

    ) AS ValorParceiro,





    SAFE_CAST(

      ValorPresenteBloko

      AS NUMERIC

    ) AS ValorPresenteBloko,





    SAFE_CAST(

      ValorPresenteParceiro

      AS NUMERIC

    ) AS ValorPresenteParceiro,





    SAFE_CAST(

      ValorOriginalBloko

      AS NUMERIC

    ) AS ValorOriginalBloko,





    SAFE_CAST(

      ValorOriginalParceiro

      AS NUMERIC

    ) AS ValorOriginalParceiro





  FROM

    added_custom11



),





-- ====================================================================

-- 28. REMOVER BUSINESSAREAID

-- ====================================================================



colunas_removidas AS (



  SELECT

    * EXCEPT (

      businessAreaId

    )



  FROM

    changed_type5



)





SELECT

  *



FROM

  colunas_removidas

;





-- ####################################################################

-- ANALYTICS.FATO_A_RECEBER

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.fato_areceber`

AS



SELECT

  *



FROM

  `dadosfinanceiro-501613.trusted.areceber`

;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO

-- ####################################################################



-- SELECT



--   COUNT(*) AS total_trusted,



--   COUNTIF(

--     billId IS NULL

--   ) AS billId_nulo,



--   COUNTIF(

--     dueDate IS NULL

--   ) AS dueDate_nulo,



--   COUNTIF(

--     percentual IS NULL

--   ) AS sem_match_unidade,



--   COUNTIF(

--     interestRate IS NULL

--   ) AS interestRate_nulo,



--   MIN(dueDate)

--     AS primeira_dueDate,



--   MAX(dueDate)

--     AS ultima_dueDate,



--   COUNTIF(

--     situacaoInicialAR = 'Adimplente'

--   ) AS adimplente,



--   COUNTIF(

--     situacaoInicialAR = 'Atrasado'

--   ) AS atrasado,



--   COUNTIF(

--     situacaoInicialAR = 'Inadimplente'

--   ) AS inadimplente,



--   SUM(ValorBruto)

--     AS soma_ValorBruto,



--   SUM(ValorPresente)

--     AS soma_ValorPresente



-- FROM

--   `dadosfinanceiro-501613.trusted.areceber`

-- ;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- linhas do raw vs trusted (diferenca = removidas por erro de billId

-- ou duplicadas pelo join com dim_unidades)

-- SELECT



--   (

--     SELECT

--       COUNT(*)



--     FROM

--       `dadosfinanceiro-501613.raw.areceber`

--   ) AS total_raw,



--   (

--     SELECT

--       COUNT(*)



--     FROM

--       `dadosfinanceiro-501613.trusted.areceber`

--   ) AS total_trusted,



--   (

--     SELECT

--       COUNT(*)



--     FROM

--       `dadosfinanceiro-501613.analytics.fato_areceber`

--   ) AS total_analytics

-- ;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ChaveEmpreendimentoLote duplicada na dim_unidades

-- (multiplica linhas no LEFT JOIN, igual ao PQ)

-- SELECT

--   ChaveEmpreendimentoLote,

--   COUNT(*) AS qtd



-- FROM

--   `dadosfinanceiro-501613.analytics.dim_unidades`



-- GROUP BY

--   ChaveEmpreendimentoLote



-- HAVING

--   COUNT(*) > 1



-- ORDER BY

--   qtd DESC

-- ;