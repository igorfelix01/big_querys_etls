-- ####################################################################

-- LOOKER_STUDIO.RENEGOCIACAO_RECEBIMENTOS

-- Pagina Renegociacao - card "Recebido Reneg." (e "Acum. Recebido Reneg.")

--

-- DAX (RecebidoReneg):

--   SUM(SaldoDevedor[ValorBruto]) com

--     SaldoDevedor[paymentDate] >= Reparcelamento_Analise[UltimaDataReparcelamento]

--     SaldoDevedor[OrigemBase] = ""   (so recebidas)

--   filtro do card: Conta = Efeito Caixa

--

-- 1 linha por recebimento (contrato x data de pagamento) DEPOIS da

-- renegociacao, com os mesmos campos de filtro da renegociacao_base.

--   Recebido Reneg.       -> card COM DataPagamento como dimensao de periodo

--   Acum. Recebido Reneg. -> card SEM dimensao de periodo (soma tudo)

--

-- SEM periodo no SQL. JA FILTRADO: companyGroup nao e Bloko nem vazio

-- (vem da renegociacao_base). Filtro CT fica no Looker.

--

-- Depende de: analytics.saldo_devedor, looker_studio.renegociacao_base

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.renegociacao_recebimentos`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.renegociacao_recebimentos`

CLUSTER BY companyGroup

AS



SELECT

  SAFE_CAST(sd.paymentDate AS DATE)          AS DataPagamento,

  b.ChaveGeral,

  b.DataReparcelamento,

  b.MesReparcelamento,

  b.companyGroup,

  b.companyName,

  b.projectName,

  b.StatusPerf,

  b.SituacaoContrato,

  b.documentIdentificationId,

  ROUND(SUM(CAST(sd.ValorBruto AS FLOAT64)), 2) AS ValorRecebidoReneg

FROM `dadosfinanceiro-501613.analytics.saldo_devedor` sd

JOIN `dadosfinanceiro-501613.looker_studio.renegociacao_base` b

  ON b.ChaveGeral = sd.ChaveGeral

WHERE sd.OrigemBase IS NULL

  AND sd.Conta = 'Efeito Caixa'

  AND SAFE_CAST(sd.paymentDate AS DATE) >= b.DataReparcelamento

GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO (BI: Recebido Reneg. 8.483.290 | Acum. 60.967.917)

-- periodo 01/05/2025 a 24/09/2026 - testa as 2 leituras do periodo

-- ####################################################################

-- SELECT

--   IF(documentIdentificationId = 'CT', 'so CT', 'outros')                       AS doc,

--   ROUND(SUM(IF(DataPagamento BETWEEN '2025-05-01' AND '2026-09-24',

--                ValorRecebidoReneg, 0)))                                         AS pago_no_periodo,

--   ROUND(SUM(IF(DataReparcelamento BETWEEN '2025-05-01' AND '2026-09-24',

--                ValorRecebidoReneg, 0)))                                         AS reneg_no_periodo,

--   ROUND(SUM(ValorRecebidoReneg))                                                AS acumulado

-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_recebimentos`

-- GROUP BY 1;