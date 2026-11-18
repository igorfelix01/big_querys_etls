-- ####################################################################
-- LOOKER_STUDIO.RECEBIVEIS_SITUACAO_PARCELA
--
-- FONTE: looker_studio.recebiveis_base (+ dim_nome_companhias)
--
-- CORRECOES:
--   1. installmentId removido do SELECT final: recebiveis_base nao tem
--      mais essa coluna (o PQ SaldoDevedor remove) -> daria erro.
--   2. OrigemBase protegido contra NULL na CTE base
--      (IFNULL(OrigemBase, 'Recebidas')): funciona mesmo se a
--      recebiveis_base for de uma versao anterior.
--   3. Regra de Quitacao das recebidas: DATE_DIFF estava com os
--      argumentos invertidos no teste "< 3 meses":
--        DATE_DIFF(paymentDate, UltimaDataPagamento, MONTH) < 3
--      paymentDate <= UltimaDataPagamento -> resultado sempre <= 0 ->
--      condicao sempre verdadeira. Corrigido para
--        DATE_DIFF(UltimaDataPagamento, paymentDate, MONTH) < 3
--      (mesma ordem da saldo_devedor_com_situacao_parcela).
--   4. companyGroup NULL (companyId fora da dim_nome_companhias) vira
--      'Sem grupo'. No BI essas linhas entram no grafico; no Looker o
--      NULL era descartado (jul/26: 19.479,68 de diferenca).
--      Os testes "= 0" nao mudam de resultado com a ordem, mas foram
--      padronizados.
--
-- Demais regras de negocio mantidas sem alteracao.
-- ####################################################################


DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`;-- [otimizacao] CTE 'base' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base AS
WITH
nome_companhias AS (
  SELECT
    companyId,
    companyGroup
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY companyId
    ORDER BY companyId
  ) = 1
)
SELECT * FROM (

  SELECT
    rb.* EXCEPT (OrigemBase),
    IFNULL(rb.OrigemBase, 'Recebidas') AS OrigemBase,
    -- companyId sem cadastro em Nome_Companhias: o BI mostra (Em branco),
    -- o Looker descartava a linha (NULL). Rotulo explicito para aparecer.
    IFNULL(nc.companyGroup, 'Sem grupo') AS companyGroup
  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_base` rb
  LEFT JOIN nome_companhias nc
    ON rb.companyId = nc.companyId

);

-- [otimizacao] CTE 'datas_contrato' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE datas_contrato AS
  SELECT
    base.*,

    MAX(
      CASE
        WHEN OrigemBase <> 'A Receber'
        THEN paymentDate
        ELSE NULL
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS UltimaDataPagamento,

    MAX(
      CASE
        WHEN OrigemBase = 'A Receber'
        THEN dueDate
        ELSE NULL
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS UltimaDataVencimento,

    COUNT(
      CASE
        WHEN OrigemBase = 'A Receber'
        THEN ChaveGeral
        ELSE NULL
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS ContratoFinalizado,

    CASE
      WHEN cancellationDate IS NOT NULL THEN 'Distratado'
      ELSE 'Ativo'
    END AS ContratoDistratado

  FROM base;

-- [otimizacao] CTE 'datas_penultimas' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE datas_penultimas AS
  SELECT
    datas_contrato.*,

    MAX(
      CASE
        WHEN OrigemBase <> 'A Receber'
          AND paymentDate < UltimaDataPagamento
          AND CAST(paymentTerm_id AS STRING) = 'PM'
        THEN paymentDate
        ELSE NULL
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS PenultimaDataPagamento,

    MAX(
      CASE
        WHEN OrigemBase = 'A Receber'
          AND dueDate < UltimaDataVencimento
        THEN dueDate
        ELSE NULL
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS PenultimaDataVencimento

  FROM datas_contrato;

-- [otimizacao] CTE 'valores_contrato' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE valores_contrato AS
  SELECT
    datas_penultimas.*,

    SUM(
      CASE
        WHEN paymentDate = PenultimaDataPagamento
          AND OrigemBase <> 'A Receber'
        THEN IFNULL(originalAmount, 0)
        ELSE 0
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS PenultimoValorPago,

    SUM(
      CASE
        WHEN paymentDate = UltimaDataPagamento
          AND OrigemBase <> 'A Receber'
        THEN IFNULL(ValorBruto, 0)
        ELSE 0
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS UltimoValorPago,

    SUM(
      CASE
        WHEN dueDate = PenultimaDataVencimento
          AND OrigemBase = 'A Receber'
        THEN IFNULL(originalAmount, 0)
        ELSE 0
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS PenultimoValorAR,

    SUM(
      CASE
        WHEN dueDate = UltimaDataVencimento
          AND OrigemBase = 'A Receber'
        THEN IFNULL(originalAmount, 0)
        ELSE 0
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS UltimoValorAR,

    SUM(
      CASE
        WHEN dueDate <= UltimaDataVencimento
          AND OrigemBase = 'A Receber'
        THEN IFNULL(ValorBruto, 0)
        ELSE 0
      END
    ) OVER (
      PARTITION BY ChaveGeral
    ) AS SomaValorAR

  FROM datas_penultimas;




CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY
  SituacaoParcelaVisual,
  companyGroup,
  documentIdentificationId

AS
WITH
classificacao AS (
  SELECT
    valores_contrato.*,

    CASE
      WHEN OrigemBase = 'A Receber' THEN
        CASE
          WHEN (
            (
              contractDate IS NOT NULL
              AND DATE_DIFF(UltimaDataPagamento, contractDate, YEAR) = 0
              AND DATE_DIFF(UltimaDataPagamento, contractDate, MONTH) < 2
              AND ContratoFinalizado < 4
              AND ContratoDistratado = 'Ativo'
            )
            OR (
              IFNULL(UltimoValorPago, 0) = 0
              AND ContratoFinalizado < 4
              AND ContratoDistratado = 'Ativo'
            )
          )
          THEN 'Venda à vista'

          WHEN (
            (
              (
                IFNULL(SomaValorAR, 0) > 5 * IFNULL(PenultimoValorPago, 0)
                AND IFNULL(UltimoValorPago, 0) <> 0
                AND ContratoFinalizado < 3
              )
              OR CAST(paymentTerm_id AS STRING) = 'QT'
              OR (
                (IFNULL(UltimoValorAR, 0) + IFNULL(PenultimoValorAR, 0)) > 5 * (IFNULL(UltimoValorPago, 0) + IFNULL(PenultimoValorPago, 0))
                AND IFNULL(UltimoValorPago, 0) <> 0
                AND ContratoFinalizado < 3
              )
            )
            AND ContratoDistratado = 'Ativo'
          )
          THEN 'Quitação'

          ELSE 'A Receber'
        END

      ELSE
        CASE
          WHEN (
            contractDate IS NOT NULL
            AND DATE_DIFF(UltimaDataPagamento, contractDate, YEAR) = 0
            AND DATE_DIFF(UltimaDataPagamento, contractDate, MONTH) < 2
            AND ContratoFinalizado < 3
            AND ContratoDistratado = 'Ativo'
          )
          THEN 'Venda à vista'

          WHEN (
            (
              ValorBruto > 5 * IFNULL(PenultimoValorPago, 0)
              AND ContratoFinalizado < 3
              AND ContratoDistratado = 'Ativo'
              AND DATE_DIFF(UltimaDataPagamento, paymentDate, YEAR) = 0
              -- CORRIGIDO: ordem dos argumentos
              AND DATE_DIFF(UltimaDataPagamento, paymentDate, MONTH) < 3
            )
            OR CAST(paymentTerm_id AS STRING) = 'QT'
            OR (
              IFNULL(UltimoValorPago, 0) > 5 * IFNULL(PenultimoValorPago, 0)
              AND ContratoFinalizado < 3
              AND ContratoDistratado = 'Ativo'
              AND DATE_DIFF(UltimaDataPagamento, paymentDate, YEAR) = 0
              AND DATE_DIFF(UltimaDataPagamento, paymentDate, MONTH) = 0
            )
          )
          THEN 'Quitação'

          WHEN CAST(paymentTerm_id AS STRING) = 'AT'
          THEN 'Ato'

          WHEN paymentYear < dueYear
          THEN 'Antecipado'

          WHEN paymentYear = dueYear
            AND paymentMonth < dueMonth
          THEN 'Antecipado'

          WHEN paymentYear = dueYear
            AND paymentMonth = dueMonth
          THEN 'Adimplente'

          WHEN DATE_DIFF(paymentDate, dueDate, DAY) <= 90
          THEN 'Atrasado'

          ELSE 'Inadimplente'
        END
    END AS SituacaoParcela

  FROM valores_contrato
)
SELECT
  ChaveEspecifica,
  ChaveGeral,
  ChaveEmpreendimentoLote,
  ChaveClientes,

  OrigemBase,
  Conta,

  subdominio,
  companyId,
  companyName,
  groupCompanyName,
  companyGroup,

  clientId,
  clientName,

  billId,

  documentIdentificationId,
  documentIdentificationName,
  documentNumber,

  operationTypeId,
  operationTypeName,

  paymentDate,
  dueDate,
  paymentYear,
  paymentMonth,
  dueYear,
  dueMonth,
  NumeroDiaDaSemana,

  issueDate,
  billDate,
  installmentBaseDate,
  interestBaseDate,

  contractDate,
  cancellationDate,
  anoPeriodoVenda,

  mainUnit,
  costCenterId,
  costCenterName,

  financialCategoryId,
  financialCategoryName,
  financialCategoryReducer,
  financialCategoryType,

  paymentTerm_id,
  paymentTerm_descrition,

  subJudicie,
  situacaoInicialAR,

  ValorBruto,
  ValorBloko,
  ValorParceiro,

  originalAmount,
  balanceAmount,
  correctedBalanceAmount,

  value,
  totalSellingValue,

  percentual,
  situationId,

  receivableBillId,
  cancellationPayableBillId,

  accountNumber,
  accountType,

  UltimaDataPagamento,
  UltimaDataVencimento,
  PenultimaDataPagamento,
  PenultimaDataVencimento,

  PenultimoValorPago,
  UltimoValorPago,
  PenultimoValorAR,
  UltimoValorAR,
  SomaValorAR,

  ContratoFinalizado,
  ContratoDistratado,

  SituacaoParcela,

  CASE
    WHEN SituacaoParcela = 'A Receber' THEN 'Em Aberto'
    ELSE SituacaoParcela
  END AS SituacaoParcelaVisual,

  DATE_TRUNC(
    CASE
      WHEN OrigemBase = 'A Receber' THEN dueDate
      ELSE paymentDate
    END,
    MONTH
  ) AS MesReferencia,

  CASE
    WHEN Conta = 'Efeito Caixa' THEN ValorBruto
    ELSE 0
  END AS ValorBruto_EfeitoCaixa,

  CASE
    WHEN Conta = 'Efeito Caixa' THEN ValorBloko
    ELSE 0
  END AS ValorBloko_EfeitoCaixa,

  CASE
    WHEN Conta = 'Efeito Caixa' THEN ValorParceiro
    ELSE 0
  END AS ValorParceiro_EfeitoCaixa

FROM classificacao;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- VALIDACAO
-- ####################################################################

-- 1) setembro: recebidas devem aparecer classificadas
-- SELECT
--   MesReferencia,
--   OrigemBase,
--   SituacaoParcelaVisual,
--   COUNT(*)                    AS linhas,
--   SUM(ValorBruto)             AS soma_ValorBruto,
--   SUM(ValorBruto_EfeitoCaixa) AS soma_EfeitoCaixa
-- FROM
--   `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`
-- WHERE
--   MesReferencia BETWEEN '2026-08-01' AND '2026-09-01'
-- GROUP BY
--   1, 2, 3
-- ORDER BY
--   1, 2, 3;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- 2) Conta das recebidas por mes: o grafico so soma Conta = 'Efeito Caixa'.
--    Se setembro vier com Conta NULL, o problema e o join com
--    dim_contas_bancarias na fato_recebidas.
-- SELECT
--   MesReferencia,
--   IFNULL(Conta, '(NULL)') AS Conta,
--   COUNT(*)                AS linhas,
--   SUM(ValorBruto)         AS soma_ValorBruto
-- FROM
--   `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`
-- WHERE
--   OrigemBase = 'Recebidas'
--   AND MesReferencia >= '2026-06-01'
-- GROUP BY
--   1, 2
-- ORDER BY
--   1, 2;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- 3) companyId sem companyGroup (cadastrar na planilha Nome_Companhias)
-- SELECT
--   companyId,
--   companyName,
--   COUNT(*)                    AS linhas,
--   SUM(ValorBruto_EfeitoCaixa) AS efeito_caixa
-- FROM
--   `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`
-- WHERE
--   companyGroup = 'Sem grupo'
-- GROUP BY
--   1, 2
-- ORDER BY
--   efeito_caixa DESC;