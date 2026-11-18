-- ####################################################################
-- LOOKER_STUDIO.RENEGOCIACAO_BASE
-- Pagina Renegociacao - visao por CONTRATO (1 linha por contrato
-- renegociado), para a tabela "Detalhamento Renegociacoes", a barra
-- "Composicao" e os cards SD ReparcMes / Acum. SD Recuperado /
-- SD Recuperado / Acum. Recebido.
-- (graficos por MES usam looker_studio.renegociacao_eventos)
--
-- Fonte (igual ao BI): o extrato de reparcelamento, via
-- looker_studio.renegociacao_eventos. A data do contrato e a da ULTIMA
-- renegociacao (= UltimaDataReparcelamento do extrato; conferido: bate
-- em 100% dos contratos). Nao depende mais de o Sienge confirmar:
-- a coluna ConfirmadoNoSienge mostra isso e pode ser usada como filtro.
-- Cobranca 3P continua fora; companyGroup sem Bloko e sem vazio.
-- Filtro CT fica no Looker. SEM periodo no SQL.
--
-- Colunas novas:
--   QtdRenegociacoes        quantas vezes o contrato foi renegociado
--   PrimeiraDataReneg       data da 1a renegociacao
--   SituacaoNaUltimaReneg   situacao no dia anterior a ultima renegociacao
--   SituacaoContrato        situacao HOJE
--   ConfirmadoNoSienge      a ultima renegociacao existe hoje no Sienge?
--   RenegociacaoAberta / StatusRenegociacao  ainda tem parcela a pagar?
--
-- Depende de: looker_studio.renegociacao_eventos,
--             analytics.fato_reparcelamento_analise,
--             analytics.fato_titulos_totalizador, analytics.fato_recebidas,
--             analytics.saldo_devedor
-- ####################################################################

DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.renegociacao_base`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.renegociacao_base`
CLUSTER BY companyGroup, SituacaoContrato
AS
WITH
-- ultima renegociacao de cada contrato (+ primeira e quantidade)
ultima AS (
  SELECT
    ChaveGeral,
    DataReparcelamento,
    TotalRenegociacoes,
    SituacaoNaRenegociacao,
    AtrasoNaRenegociacao,
    ConfirmadoNoSienge,
    companyGroup, companyName, projectName, StatusPerf,
    SituacaoContrato, documentIdentificationId, subJudicie,
    enterpriseId, NomeCliente, Unidade,
    MIN(DataReparcelamento) OVER (PARTITION BY ChaveGeral) AS PrimeiraDataReneg
  FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eventos`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral
                             ORDER BY DataReparcelamento DESC) = 1
),
cliente AS (
  SELECT ChaveGeral, CPF, CNPJ, Telefone, Email
  FROM `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise`
  WHERE ChaveGeral IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral
                             ORDER BY UltimaDataReparcelamento DESC) = 1
),
titulos AS (
  SELECT
    CAST(ChaveGeral AS STRING)          AS ChaveGeral,
    ANY_VALUE(MaxAtrasoDias)            AS MaxAtrasoDias,
    ANY_VALUE(PrimeiraDataVencimento)   AS PrimeiraDataVencimento,
    ANY_VALUE(SaldoDevedorSemJuros)     AS SaldoDevedorSemJuros,
    ANY_VALUE(SaldoDevedorComJuros)     AS SaldoDevedorComJuros,
    ANY_VALUE(ValorLiquidoAgregado)     AS ValorLiquidoAgregado
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  GROUP BY 1
),
-- recebido DEPOIS da ultima renegociacao (coluna ValorRecebidoAposReneg
-- do BI: db_recebidas[ValorBruto], paymentDate >= data, sem filtro de Conta)
recebido_apos AS (
  SELECT
    u.ChaveGeral,
    SUM(CAST(rc.ValorBruto AS FLOAT64)) AS ValorRecebidoAposReneg
  FROM `dadosfinanceiro-501613.analytics.fato_recebidas` rc
  JOIN ultima u
    ON u.ChaveGeral = CAST(rc.ChaveGeral AS STRING)
  WHERE SAFE_CAST(rc.paymentDate AS DATE) >= u.DataReparcelamento
  GROUP BY 1
),
-- renegociacao ABERTA = ainda tem parcela a pagar no A Receber e nao foi
-- distratado (o reparcelamento troca as parcelas em aberto pelas novas)
parcelas_abertas AS (
  SELECT
    CAST(ChaveGeral AS STRING) AS ChaveGeral,
    COUNT(DISTINCT IF(OrigemBase = 'A Receber',
          CONCAT(CAST(ChaveEspecifica AS STRING), '|', CAST(dueDate AS STRING)), NULL)) AS ParcelasEmAberto,
    COUNT(DISTINCT IF(OrigemBase = 'A Receber'
                        AND dueDate < CURRENT_DATE('America/Sao_Paulo'),
          CONCAT(CAST(ChaveEspecifica AS STRING), '|', CAST(dueDate AS STRING)), NULL)) AS ParcelasVencidasEmAberto,
    MAX(cancellationDate)      AS DataDistrato
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`
  WHERE ChaveGeral IS NOT NULL
  GROUP BY 1
)
SELECT
  u.ChaveGeral,
  u.DataReparcelamento,
  DATE_TRUNC(u.DataReparcelamento, MONTH)          AS MesReparcelamento,
  EXTRACT(YEAR FROM u.DataReparcelamento)          AS Ano,
  u.PrimeiraDataReneg,
  u.TotalRenegociacoes                             AS QtdRenegociacoes,

  u.companyGroup,
  u.companyName,
  u.projectName,
  u.StatusPerf,

  u.SituacaoContrato,                              -- hoje
  u.SituacaoNaRenegociacao                         AS SituacaoNaUltimaReneg,
  u.AtrasoNaRenegociacao                           AS AtrasoNaUltimaReneg,
  u.documentIdentificationId,
  u.ConfirmadoNoSienge,

  u.enterpriseId,
  u.NomeCliente,
  u.Unidade,

  -- ===== tabela Detalhamento Renegociacoes =====
  t.MaxAtrasoDias                                  AS Atraso,
  t.PrimeiraDataVencimento                         AS Vencimento,
  ROUND(t.SaldoDevedorComJuros, 2)                 AS SaldoDevedor,
  ROUND(t.ValorLiquidoAgregado, 2)                 AS ValorRecebido,
  u.subJudicie,
  c.CPF,
  c.CNPJ,
  c.Telefone,
  c.Email,

  -- ===== cards =====
  ROUND(t.SaldoDevedorSemJuros, 2)                 AS SDSemJuros,
  ROUND(IF(u.SituacaoContrato IN ('Adimplente', 'Quitado'),
           t.SaldoDevedorSemJuros, 0), 2)          AS SDRecuperado,
  ROUND(IFNULL(ra.ValorRecebidoAposReneg, 0), 2)   AS ValorRecebidoAposReneg,

  -- ===== renegociacao aberta ou encerrada =====
  IF(pa.DataDistrato IS NULL AND IFNULL(pa.ParcelasEmAberto, 0) > 0,
     'Sim', 'Não')                                 AS RenegociacaoAberta,
  CASE
    WHEN pa.DataDistrato IS NOT NULL              THEN 'Encerrada - distratada'
    WHEN IFNULL(pa.ParcelasEmAberto, 0) = 0       THEN 'Encerrada - quitada'
    WHEN pa.ParcelasVencidasEmAberto > 0          THEN 'Aberta - com parcela vencida'
    ELSE                                               'Aberta - em dia'
  END                                              AS StatusRenegociacao,
  IFNULL(pa.ParcelasEmAberto, 0)                   AS ParcelasEmAberto,
  IFNULL(pa.ParcelasVencidasEmAberto, 0)           AS ParcelasVencidasEmAberto,

  1 AS Contratos           -- no Looker: SOMA
FROM ultima u
LEFT JOIN cliente c           ON c.ChaveGeral = u.ChaveGeral
LEFT JOIN titulos t           ON t.ChaveGeral = u.ChaveGeral
LEFT JOIN recebido_apos ra    ON ra.ChaveGeral = u.ChaveGeral
LEFT JOIN parcelas_abertas pa ON pa.ChaveGeral = u.ChaveGeral;


-- ####################################################################
-- CONFERENCIA (rodar na mao)
-- ####################################################################
-- SELECT StatusRenegociacao, ConfirmadoNoSienge, COUNT(*) AS contratos,
--        ROUND(SUM(SaldoDevedor), 2) AS saldo_devedor
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base`
-- WHERE documentIdentificationId = 'CT'
-- GROUP BY 1, 2 ORDER BY 1, 2;
