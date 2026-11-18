-- ####################################################################
-- LOOKER_STUDIO.RECEBIVEIS_BASE
--
-- FONTE: dadosfinanceiro-501613.analytics.saldo_devedor (= SaldoDevedor)
--
-- Camada de apresentacao: apenas seleciona colunas, sem filtrar linhas,
-- para os totais baterem com o SaldoDevedor do BI.
--   - installmentId removido (o PQ SaldoDevedor remove essa coluna)
--   - sem WHERE paymentDate IS NOT NULL (o BI nao filtra; linhas com
--     paymentDate nulo vao para a particao __NULL__)
--   - OrigemBase: no saldo_devedor (fiel ao PQ) as recebidas ficam NULL.
--     Aqui, so na camada de apresentacao, NULL vira 'Recebidas' para as
--     tabelas do Looker que filtram/classificam por OrigemBase.
-- ####################################################################


DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.recebiveis_base`;


CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.recebiveis_base`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY
  Conta,
  OrigemBase,
  subJudicie,
  companyName

AS

SELECT

  DATE_TRUNC(paymentDate, MONTH) AS MesReferenciaBase,

  ChaveEspecifica,
  ChaveGeral,
  ChaveEmpreendimentoLote,
  ChaveClientes,

  IFNULL(OrigemBase, 'Recebidas') AS OrigemBase,
  Conta,

  subdominio,
  companyId,
  companyName,
  groupCompanyName,
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
  accountType

FROM
  `dadosfinanceiro-501613.analytics.saldo_devedor`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- VALIDACAO: deve bater 100% com analytics.saldo_devedor
-- ####################################################################

-- SELECT
--   'saldo_devedor'   AS tabela,
--   COUNT(*)          AS linhas,
--   SUM(ValorBruto)   AS soma_ValorBruto,
--   SUM(ValorBloko)   AS soma_ValorBloko,
--   COUNTIF(paymentDate IS NULL) AS paymentDate_nulo
-- FROM
--   `dadosfinanceiro-501613.analytics.saldo_devedor`

-- UNION ALL

-- SELECT
--   'recebiveis_base',
--   COUNT(*),
--   SUM(ValorBruto),
--   SUM(ValorBloko),
--   COUNTIF(paymentDate IS NULL)
-- FROM
--   `dadosfinanceiro-501613.looker_studio.recebiveis_base`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- distribuicao de OrigemBase (nao deve existir NULL)
-- SELECT
--   OrigemBase,
--   COUNT(*)        AS linhas,
--   SUM(ValorBruto) AS soma_ValorBruto
-- FROM
--   `dadosfinanceiro-501613.looker_studio.recebiveis_base`
-- GROUP BY
--   OrigemBase;