-- ============================================================
-- REPARCELAMENTOS POR CHAVE GERAL E DATA DE PAGAMENTO
-- COM CONTAGEM HISTÓRICA E TOTAL DE RENEGOCIAÇÕES
--
-- GRAVA: trusted.renegociacoes  e  analytics.fato_renegociacoes
--   1 linha por contrato (ChaveGeral) + data de pagamento do
--   Reparcelamento (CT), com:
--     qtd_renegociacoes_ate_aquele_dia = renegociacoes ANTERIORES
--     qtd_renegociacoes_totais         = total do contrato
--   (antes este arquivo era so um SELECT e nao gravava nada)
-- ============================================================

-- Datas: aceita DATE, TIMESTAMP, '2024-10-15', '2024-10-15 00:00:00' e
-- '15/10/2024' (SAFE_CAST direto de texto com hora vira NULL)
CREATE TEMP FUNCTION br_data(valor STRING) AS (
  COALESCE(
    SAFE_CAST(SUBSTR(TRIM(valor), 1, 10) AS DATE),
    SAFE.PARSE_DATE('%d/%m/%Y', SUBSTR(TRIM(valor), 1, 10))
  )
);-- [otimizacao] CTE 'df_reparcelamento' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE df_reparcelamento AS
WITH
recebidas_historico_filtrada AS (
    SELECT
        CAST(companyId AS STRING) AS companyId,
        CAST(companyName AS STRING) AS companyName,

        CAST(projectId AS STRING) AS projectId,
        CAST(projectName AS STRING) AS projectName,

        CAST(clientId AS STRING) AS clientId,
        CAST(clientName AS STRING) AS clientName,

        CAST(groupCompanyId AS STRING) AS groupCompanyId,
        TRIM(CAST(groupCompanyName AS STRING)) AS groupCompanyName,

        TRIM(
            CAST(documentIdentificationId AS STRING)
        ) AS documentIdentificationId,

        CAST(
            documentIdentificationName AS STRING
        ) AS documentIdentificationName,

        CAST(costCenterId AS STRING) AS costCenterId_original,
        CAST(costCenterName AS STRING) AS costCenterName,

        br_data(CAST(paymentDate AS STRING)) AS paymentDate,
        br_data(CAST(dueDate AS STRING)) AS dueDate,

        TRIM(
            CAST(operationTypeName AS STRING)
        ) AS operationTypeName,

        CAST(ChaveEspecifica AS STRING) AS ChaveEspecifica,

        2 AS prioridade_origem,
        'recebidas_historico' AS origem

    FROM
        `dadosfinanceiro-501613.raw.recebidas_historico`

    WHERE
        TRIM(
            CAST(documentIdentificationId AS STRING)
        ) = 'CT'

        AND TRIM(
            CAST(operationTypeName AS STRING)
        ) = 'Reparcelamento'

        AND br_data(CAST(paymentDate AS STRING)) IS NOT NULL
),

recebidas_atualizavel_filtrada AS (
    SELECT
        CAST(companyId AS STRING) AS companyId,
        CAST(companyName AS STRING) AS companyName,

        CAST(projectId AS STRING) AS projectId,
        CAST(projectName AS STRING) AS projectName,

        CAST(clientId AS STRING) AS clientId,
        CAST(clientName AS STRING) AS clientName,

        CAST(groupCompanyId AS STRING) AS groupCompanyId,
        TRIM(CAST(groupCompanyName AS STRING)) AS groupCompanyName,

        TRIM(
            CAST(documentIdentificationId AS STRING)
        ) AS documentIdentificationId,

        CAST(
            documentIdentificationName AS STRING
        ) AS documentIdentificationName,

        CAST(costCenterId AS STRING) AS costCenterId_original,
        CAST(costCenterName AS STRING) AS costCenterName,

        br_data(CAST(paymentDate AS STRING)) AS paymentDate,
        br_data(CAST(dueDate AS STRING)) AS dueDate,

        TRIM(
            CAST(operationTypeName AS STRING)
        ) AS operationTypeName,

        CAST(ChaveEspecifica AS STRING) AS ChaveEspecifica,

        1 AS prioridade_origem,
        'recebidas_atualizavel' AS origem

    FROM
        `dadosfinanceiro-501613.raw.recebidas_atualizavel`

    WHERE
        TRIM(
            CAST(documentIdentificationId AS STRING)
        ) = 'CT'

        AND TRIM(
            CAST(operationTypeName AS STRING)
        ) = 'Reparcelamento'

        AND br_data(CAST(paymentDate AS STRING)) IS NOT NULL
),

recebidas_unificadas AS (
    SELECT *
    FROM recebidas_historico_filtrada

    UNION ALL

    SELECT *
    FROM recebidas_atualizavel_filtrada
),

recebidas_tratadas AS (
    SELECT
        companyId,
        companyName,

        projectId,
        projectName,

        clientId,
        clientName,

        groupCompanyId,
        groupCompanyName,

        documentIdentificationId,
        documentIdentificationName,

        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    costCenterId_original,
                    r',.*$',
                    ''
                ),
                r'\.',
                ''
            )
        ) AS costCenterId,

        costCenterName,

        paymentDate,
        dueDate,

        operationTypeName,
        ChaveEspecifica,

        REGEXP_EXTRACT(
            ChaveEspecifica,
            r'^(\d+-\d+)'
        ) AS ChaveGeral,

        DATE_DIFF(
            paymentDate,
            dueDate,
            DAY
        ) AS atraso,

        prioridade_origem,
        origem

    FROM
        recebidas_unificadas

    WHERE
        REGEXP_EXTRACT(
            ChaveEspecifica,
            r'^(\d+-\d+)'
        ) IS NOT NULL
),

centros_validos AS (
    -- raw.centros_de_custos nao existe no BigQuery: os centros de custo
    -- validos sao os empreendimentos cadastrados na Nome_Companhias
    -- (a mesma planilha do BI; enterpriseId = centro de custo)
    SELECT DISTINCT
        CAST(SAFE_CAST(enterpriseId AS INT64) AS STRING) AS costCenterId
    FROM
        `dadosfinanceiro-501613.analytics.dim_nome_companhias`
    WHERE
        SAFE_CAST(enterpriseId AS INT64) IS NOT NULL
),

recebidas_com_centro_valido AS (
    SELECT
        r.*

    FROM
        recebidas_tratadas AS r

    INNER JOIN
        centros_validos AS c
        ON r.costCenterId = c.costCenterId
),

recebidas_com_companhia AS (
    SELECT
        companyId,
        companyName,

        projectId,
        projectName,

        clientId,
        clientName,

        groupCompanyId,
        groupCompanyName,

        documentIdentificationId,
        documentIdentificationName,

        costCenterId,
        costCenterName,

        paymentDate,
        dueDate,

        operationTypeName,

        ChaveEspecifica,
        ChaveGeral,

        atraso,

        CASE
            WHEN groupCompanyName = 'GRUPO INLOT'
                 AND costCenterId IN (
                     '10400',
                     '10401',
                     '10402',
                     '10403'
                 )
            THEN 'Jatai'

            WHEN groupCompanyName = 'GRUPO INLOT'
            THEN 'Inlot'

            ELSE groupCompanyName
        END AS Companhia,

        prioridade_origem,
        origem

    FROM
        recebidas_com_centro_valido
),

recebidas_com_chave_pagamento AS (
    SELECT
        CONCAT(
            ChaveGeral,
            ' - ',
            FORMAT_DATE(
                '%Y-%m-%d',
                paymentDate
            )
        ) AS ChaveGeral_paymentDate,

        companyId,
        companyName,

        projectId,
        projectName,

        clientId,
        clientName,

        groupCompanyId,
        groupCompanyName,

        documentIdentificationId,
        documentIdentificationName,

        costCenterId,
        costCenterName,

        paymentDate,
        dueDate,

        operationTypeName,
        Companhia,

        ChaveGeral,
        ChaveEspecifica,

        atraso,

        prioridade_origem,
        origem

    FROM
        recebidas_com_companhia
)
SELECT * FROM (

    SELECT
        *

    FROM
        recebidas_com_chave_pagamento

    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                ChaveGeral_paymentDate

            ORDER BY
                prioridade_origem ASC,
                ChaveEspecifica ASC
        ) = 1

);



CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.renegociacoes` AS
WITH
base_datas_quantidade AS (
    SELECT
        ChaveGeral,
        paymentDate,

        COUNT(*) AS qtd_no_dia

    FROM
        df_reparcelamento

    GROUP BY
        ChaveGeral,
        paymentDate
),

base_datas AS (
    SELECT
        ChaveGeral,
        paymentDate,
        qtd_no_dia,

        COALESCE(
            SUM(qtd_no_dia) OVER (
                PARTITION BY
                    ChaveGeral

                ORDER BY
                    paymentDate

                ROWS BETWEEN
                    UNBOUNDED PRECEDING
                    AND 1 PRECEDING
            ),
            0
        ) AS qtd_renegociacoes_ate_aquele_dia

    FROM
        base_datas_quantidade
),

totais AS (
    SELECT
        ChaveGeral,

        COUNT(*) AS qtd_renegociacoes_totais

    FROM
        df_reparcelamento

    GROUP BY
        ChaveGeral
),

resultado_com_contagens AS (
    SELECT
        r.ChaveGeral_paymentDate,

        r.companyId,
        r.companyName,

        r.projectId,
        r.projectName,

        r.clientId,
        r.clientName,

        r.groupCompanyId,
        r.groupCompanyName,

        r.documentIdentificationId,
        r.documentIdentificationName,

        r.costCenterId,
        r.costCenterName,

        r.paymentDate,
        r.dueDate,

        r.operationTypeName,
        r.Companhia,

        r.ChaveGeral,
        r.ChaveEspecifica,

        r.atraso,

        b.qtd_no_dia,
        b.qtd_renegociacoes_ate_aquele_dia,

        t.qtd_renegociacoes_totais,

        r.origem

    FROM
        df_reparcelamento AS r

    LEFT JOIN
        base_datas AS b
        ON r.ChaveGeral = b.ChaveGeral
        AND r.paymentDate = b.paymentDate

    LEFT JOIN
        totais AS t
        ON r.ChaveGeral = t.ChaveGeral
)
-- ============================================================
-- 14. RESULTADO FINAL
-- ============================================================

SELECT
    ChaveGeral_paymentDate,

    companyId,
    companyName,

    projectId,
    projectName,

    clientId,
    clientName,

    groupCompanyId,
    groupCompanyName,

    documentIdentificationId,
    documentIdentificationName,

    costCenterId,
    costCenterName,

    paymentDate,
    dueDate,

    operationTypeName,
    Companhia,

    ChaveGeral,
    ChaveEspecifica,

    atraso,

    qtd_no_dia,
    qtd_renegociacoes_ate_aquele_dia,
    qtd_renegociacoes_totais,

    origem

FROM
    resultado_com_contagens;


CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_renegociacoes` AS
SELECT *
FROM `dadosfinanceiro-501613.trusted.renegociacoes`;