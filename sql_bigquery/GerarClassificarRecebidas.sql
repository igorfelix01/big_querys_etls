-- Datas: aceita DATE, TIMESTAMP, '2024-10-15', '2024-10-15 00:00:00' e
-- '15/10/2024' (SAFE_CAST direto de texto com hora vira NULL)
CREATE TEMP FUNCTION br_data(valor STRING) AS (
  COALESCE(
    SAFE_CAST(SUBSTR(TRIM(valor), 1, 10) AS DATE),
    SAFE.PARSE_DATE('%d/%m/%Y', SUBSTR(TRIM(valor), 1, 10))
  )
);

CREATE OR REPLACE TABLE
    `dadosfinanceiro-501613.looker_studio.recebidas`
AS

WITH

-- ============================================================
-- 1. RECEBIDAS HISTÓRICO
-- ============================================================

recebidas_historico_filtrada AS (
    SELECT
        CAST(chaveespecifica AS STRING) AS ChaveEspecifica,

        REGEXP_EXTRACT(
            CAST(chaveespecifica AS STRING),
            r'^(\d+-\d+)'
        ) AS ChaveGeral,

        TRIM(
            CAST(accountnumber AS STRING)
        ) AS accountNumber,

        CAST(companyname AS STRING) AS companyName,

        br_data(CAST(issuedate AS STRING)) AS issueDate,

        br_data(CAST(duedate AS STRING)) AS dueDate,

        CASE
            WHEN TRIM(
                CAST(groupcompanyname AS STRING)
            ) = 'Grupo Macapá S/A'
            THEN 'GRUPO MACAPÁ'

            ELSE TRIM(
                CAST(groupcompanyname AS STRING)
            )
        END AS groupCompanyName,

        SAFE_CAST(netamount AS NUMERIC) AS netAmount,

        TRIM(
            CAST(operationtypename AS STRING)
        ) AS operationTypeName,

        br_data(CAST(paymentdate AS STRING)) AS paymentDate,

        REPLACE(
            CAST(documentidentificationid AS STRING),
            ' ',
            ''
        ) AS documentIdentificationId,

        CAST(costcenterid AS STRING) AS costCenterId_original,

        TRIM(
            CAST(paymentTerm_Id AS STRING)
        ) AS paymentTerm_Id,

        2 AS prioridade_origem

    FROM
        `dadosfinanceiro-501613.raw.recebidas_historico`

    WHERE
        operationtypeid = 2

        AND REPLACE(
            UPPER(
                CAST(documentidentificationid AS STRING)
            ),
            ' ',
            ''
        ) LIKE '%CT%'

        AND paymentdate IS NOT NULL
),


-- ============================================================
-- 2. RECEBIDAS ATUALIZÁVEL
-- ============================================================

recebidas_atualizavel_filtrada AS (
    SELECT
        CAST(chaveespecifica AS STRING) AS ChaveEspecifica,

        REGEXP_EXTRACT(
            CAST(chaveespecifica AS STRING),
            r'^(\d+-\d+)'
        ) AS ChaveGeral,

        TRIM(
            CAST(accountnumber AS STRING)
        ) AS accountNumber,

        CAST(companyname AS STRING) AS companyName,

        br_data(CAST(issuedate AS STRING)) AS issueDate,

        br_data(CAST(duedate AS STRING)) AS dueDate,

        CASE
            WHEN TRIM(
                CAST(groupcompanyname AS STRING)
            ) = 'Grupo Macapá S/A'
            THEN 'GRUPO MACAPÁ'

            ELSE TRIM(
                CAST(groupcompanyname AS STRING)
            )
        END AS groupCompanyName,

        SAFE_CAST(netamount AS NUMERIC) AS netAmount,

        TRIM(
            CAST(operationtypename AS STRING)
        ) AS operationTypeName,

        br_data(CAST(paymentdate AS STRING)) AS paymentDate,

        REPLACE(
            CAST(documentidentificationid AS STRING),
            ' ',
            ''
        ) AS documentIdentificationId,

        CAST(costcenterid AS STRING) AS costCenterId_original,

        TRIM(
            CAST(paymentTerm_Id AS STRING)
        ) AS paymentTerm_Id,

        1 AS prioridade_origem

    FROM
        `dadosfinanceiro-501613.raw.recebidas_atualizavel`

    WHERE
        operationtypeid = 2

        AND REPLACE(
            UPPER(
                CAST(documentidentificationid AS STRING)
            ),
            ' ',
            ''
        ) LIKE '%CT%'

        AND paymentdate IS NOT NULL
),


-- ============================================================
-- 3. UNIR AS DUAS BASES
-- ============================================================

recebidas_unificadas AS (
    SELECT *
    FROM recebidas_historico_filtrada

    UNION ALL

    SELECT *
    FROM recebidas_atualizavel_filtrada
),


-- ============================================================
-- 4. TRATAMENTOS
-- ============================================================

recebidas_tratadas AS (
    SELECT
        ChaveEspecifica,
        ChaveGeral,
        accountNumber,
        companyName,
        issueDate,
        dueDate,
        groupCompanyName,
        netAmount,
        operationTypeName,
        paymentDate,
        documentIdentificationId,
        paymentTerm_Id,

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

        DATE_DIFF(
            paymentDate,
            dueDate,
            DAY
        ) AS atraso,

        prioridade_origem

    FROM
        recebidas_unificadas

    WHERE
        ChaveGeral IS NOT NULL
),


-- ============================================================
-- 5. CENTROS DE CUSTOS VÁLIDOS
-- ============================================================

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


-- ============================================================
-- 6. CONTAS BANCÁRIAS
-- ============================================================

contas_tratadas AS (
    SELECT
        TRIM(
            CAST(accountNumber AS STRING)
        ) AS accountNumber,

        TRIM(
            CAST(Conta AS STRING)
        ) AS Conta

    FROM
        `dadosfinanceiro-501613.raw.contas_bancarias`

    WHERE
        accountNumber IS NOT NULL
),


-- ============================================================
-- 7. FILTRAR CENTROS DE CUSTO
-- ============================================================

recebidas_com_centro_valido AS (
    SELECT
        r.*

    FROM
        recebidas_tratadas AS r

    INNER JOIN
        centros_validos AS c
        ON r.costCenterId = c.costCenterId
),


-- ============================================================
-- 8. CRIAR COMPANHIA
-- ============================================================

recebidas_com_companhia AS (
    SELECT
        ChaveEspecifica,
        ChaveGeral,
        accountNumber,
        companyName,
        issueDate,
        dueDate,
        groupCompanyName,
        netAmount,
        operationTypeName,
        paymentDate,
        documentIdentificationId,
        paymentTerm_Id,
        costCenterId,
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

        prioridade_origem

    FROM
        recebidas_com_centro_valido
),


-- ============================================================
-- 9. JOIN COM CONTAS BANCÁRIAS
-- ============================================================

recebidas_com_conta AS (
    SELECT
        r.ChaveEspecifica,
        r.ChaveGeral,
        r.accountNumber,
        r.companyName,
        r.issueDate,
        r.dueDate,
        r.groupCompanyName,
        r.netAmount,
        r.operationTypeName,
        r.paymentDate,
        r.documentIdentificationId,
        r.paymentTerm_Id,
        r.costCenterId,
        r.atraso,
        r.Companhia,

        c.Conta,

        r.prioridade_origem

    FROM
        recebidas_com_companhia AS r

    LEFT JOIN
        contas_tratadas AS c
        ON r.accountNumber = c.accountNumber
),


-- ============================================================
-- 10. REMOVER CONTAS GERENCIAIS
--
-- Mantém o comportamento do Polars:
-- linhas com Conta nula também são removidas.
-- ============================================================

recebidas_sem_gerencial AS (
    SELECT
        *

    FROM
        recebidas_com_conta

    WHERE
        Conta != 'Gerencial'
),


-- ============================================================
-- 11. REMOVER DUPLICIDADES ENTRE AS DUAS FONTES
--
-- A recebidas_atualizavel tem prioridade quando o mesmo
-- pagamento está nas duas tabelas.
-- ============================================================

recebidas_deduplicadas AS (
    SELECT
        *

    FROM
        recebidas_sem_gerencial

    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                ChaveEspecifica,
                paymentDate,
                accountNumber,
                netAmount

            ORDER BY
                prioridade_origem ASC
        ) = 1
),


-- ============================================================
-- 12. CRIAR UMA ORDEM DETERMINÍSTICA DOS PAGAMENTOS
--
-- A ordenação é feita dentro de cada ChaveGeral.
--
-- Para pagamentos na mesma data, utiliza:
--   ChaveEspecifica
--   accountNumber
--   netAmount
-- ============================================================

recebidas_ordenadas AS (
    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY
                ChaveGeral

            ORDER BY
                paymentDate,
                ChaveEspecifica,
                accountNumber,
                netAmount
        ) AS ordem_pagamento

    FROM
        recebidas_deduplicadas
),


-- ============================================================
-- 13. ÚLTIMO E PENÚLTIMO PAGAMENTO NO CONTEXTO DA LINHA
--
-- Não utiliza pagamentos futuros.
--
-- Para cada linha:
--   UltimaDataPagamento = maior paymentDate até a linha atual
--   UltimoValorPago = valor da linha mais recente até a atual
--   PenultimoValorPago = valor da linha imediatamente anterior
-- ============================================================

recebidas_com_historico AS (
    SELECT
        ChaveEspecifica,
        ChaveGeral,
        accountNumber,
        companyName,
        issueDate,
        dueDate,
        groupCompanyName,
        netAmount,
        operationTypeName,
        paymentDate,
        documentIdentificationId,
        paymentTerm_Id,
        costCenterId,
        atraso,
        Companhia,
        Conta,
        ordem_pagamento,

        MAX(paymentDate) OVER (
            PARTITION BY
                ChaveGeral

            ORDER BY
                paymentDate,
                ChaveEspecifica,
                accountNumber,
                netAmount

            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW
        ) AS UltimaDataPagamento,

        LAST_VALUE(netAmount) OVER (
            PARTITION BY
                ChaveGeral

            ORDER BY
                paymentDate,
                ChaveEspecifica,
                accountNumber,
                netAmount

            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW
        ) AS UltimoValorPago,

        LAG(netAmount, 1) OVER (
            PARTITION BY
                ChaveGeral

            ORDER BY
                paymentDate,
                ChaveEspecifica,
                accountNumber,
                netAmount
        ) AS PenultimoValorPago

    FROM
        recebidas_ordenadas
),


-- ============================================================
-- 14. CRIAR CATEGORIA
--
-- Ordem de prioridade:
--   1. Venda à vista
--   2. Quitação
--   3. Ato
--   4. Antecipado
--   5. Adimplente
--   6. Atrasado
--   7. Inadimplente
-- ============================================================

resultado_categorizado AS (
    SELECT
        ChaveEspecifica,
        ChaveGeral,
        accountNumber,
        companyName,
        issueDate,
        dueDate,
        groupCompanyName,
        netAmount,
        operationTypeName,
        paymentDate,
        documentIdentificationId,
        paymentTerm_Id,
        costCenterId,
        atraso,
        Companhia,
        Conta,

        UltimaDataPagamento,
        UltimoValorPago,
        PenultimoValorPago,

        CASE

            -- ==================================================
            -- VENDA À VISTA
            --
            -- issueDate existe;
            -- pagamento da linha está no mesmo ano da issueDate;
            -- diferença inferior a dois meses.
            -- ==================================================

            WHEN
                issueDate IS NOT NULL

                AND UltimaDataPagamento IS NOT NULL

                AND DATE_DIFF(
                    issueDate,
                    UltimaDataPagamento,
                    YEAR
                ) = 0

                AND DATE_DIFF(
                    UltimaDataPagamento,
                    issueDate,
                    MONTH
                ) < 2

            THEN 'Venda à vista'


            -- ==================================================
            -- QUITAÇÃO
            --
            -- 1. Valor pago na linha maior que cinco vezes
            --    o pagamento imediatamente anterior;
            --
            -- OU
            --
            -- 2. paymentTerm_Id igual a QT;
            --
            -- OU
            --
            -- 3. Último valor conhecido até a linha maior que
            --    cinco vezes o valor imediatamente anterior.
            -- ==================================================

            WHEN
                (
                    PenultimoValorPago IS NOT NULL

                    AND netAmount >
                        5 * PenultimoValorPago

                    AND DATE_DIFF(
                        paymentDate,
                        UltimaDataPagamento,
                        YEAR
                    ) = 0

                    AND DATE_DIFF(
                        paymentDate,
                        UltimaDataPagamento,
                        MONTH
                    ) < 3
                )

                OR paymentTerm_Id = 'QT'

                OR (
                    PenultimoValorPago IS NOT NULL

                    AND UltimoValorPago >
                        5 * PenultimoValorPago

                    AND DATE_DIFF(
                        paymentDate,
                        UltimaDataPagamento,
                        YEAR
                    ) = 0

                    AND DATE_DIFF(
                        paymentDate,
                        UltimaDataPagamento,
                        MONTH
                    ) = 0
                )

            THEN 'Quitação'


            -- ==================================================
            -- ATO
            -- ==================================================

            WHEN paymentTerm_Id = 'AT'
            THEN 'Ato'


            -- ==================================================
            -- ANTECIPADO
            --
            -- Pagamento em ano anterior ao vencimento.
            -- ==================================================

            WHEN
                EXTRACT(YEAR FROM paymentDate)
                <
                EXTRACT(YEAR FROM dueDate)

            THEN 'Antecipado'


            -- ==================================================
            -- ANTECIPADO
            --
            -- Mesmo ano, mas pagamento em mês anterior.
            -- ==================================================

            WHEN
                EXTRACT(YEAR FROM paymentDate)
                =
                EXTRACT(YEAR FROM dueDate)

                AND EXTRACT(MONTH FROM paymentDate)
                <
                EXTRACT(MONTH FROM dueDate)

            THEN 'Antecipado'


            -- ==================================================
            -- ADIMPLENTE
            --
            -- Mesmo mês e ano do vencimento.
            -- ==================================================

            WHEN
                EXTRACT(YEAR FROM paymentDate)
                =
                EXTRACT(YEAR FROM dueDate)

                AND EXTRACT(MONTH FROM paymentDate)
                =
                EXTRACT(MONTH FROM dueDate)

            THEN 'Adimplente'


            -- ==================================================
            -- ATRASADO
            --
            -- Até 90 dias de atraso, inclusive.
            -- ==================================================

            WHEN atraso <= 90
            THEN 'Atrasado'


            -- ==================================================
            -- INADIMPLENTE
            --
            -- Mais de 90 dias de atraso.
            -- ==================================================

            ELSE 'Inadimplente'

        END AS Categoria

    FROM
        recebidas_com_historico
)


-- ============================================================
-- 15. RESULTADO FINAL
-- ============================================================

SELECT
    ChaveEspecifica,
    ChaveGeral,
    accountNumber,
    companyName,
    issueDate,
    dueDate,
    groupCompanyName,
    netAmount,
    operationTypeName,
    paymentDate,
    documentIdentificationId,
    paymentTerm_Id,
    costCenterId,
    atraso,
    Companhia,
    Conta,

    UltimaDataPagamento,
    UltimoValorPago,
    PenultimoValorPago,

    Categoria

FROM
    resultado_categorizado;