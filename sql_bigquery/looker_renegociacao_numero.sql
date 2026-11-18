-- ####################################################################
-- LOOKER_STUDIO.RENEGOCIACAO_NUMERO
-- Pagina Renegociacao - grafico por mes:
--   "Primeira / Segunda / Terceira ou Quarta / Quinta ou mais Renegociacao"
--
-- AGORA 1 LINHA POR RENEGOCIACAO (nao mais por contrato): cada
-- renegociacao conta no PROPRIO mes. Ex.: contrato renegociado em
-- mar/2025 e out/2026 -> 'Primeira' em mar/2025 e 'Segunda' em out/2026.
-- Mesmas linhas da looker_studio.renegociacao_eventos (fonte: extrato
-- de reparcelamento, igual ao BI) com os nomes de coluna antigos, para o
-- grafico que ja existe continuar funcionando sem mexer.
-- Contratos = 1 por renegociacao (no Looker: SOMA).
-- SEM periodo no SQL (Looker: DataReparcelamento).
--
-- Depende de: looker_studio.renegociacao_eventos
-- ####################################################################

DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.renegociacao_numero`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.renegociacao_numero`
CLUSTER BY companyGroup, FaixaRenegociacao
AS
SELECT
  ChaveGeral,
  DataReparcelamento,
  MesReparcelamento,                    -- eixo X
  Ano,
  NumeroRenegociacao,
  FaixaRenegociacao,                    -- legenda
  OrdemFaixa,                           -- ordem da legenda
  companyGroup,
  companyName,
  projectName,
  StatusPerf,
  SituacaoContrato,                     -- hoje
  SituacaoNaRenegociacao,               -- no dia da renegociacao
  ConfirmadoNoSienge,
  documentIdentificationId,
  subJudicie,
  NomeCliente,
  enterpriseId,
  1 AS Contratos                        -- no Looker: SOMA
FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eventos`;


-- ####################################################################
-- CONFERENCIA (rodar na mao): por mes e faixa (CT)
-- ####################################################################
-- SELECT MesReparcelamento, FaixaRenegociacao, SUM(Contratos) AS renegociacoes
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_numero`
-- WHERE documentIdentificationId = 'CT' AND MesReparcelamento >= DATE '2025-05-01'
-- GROUP BY 1, 2 ORDER BY 1, MIN(OrdemFaixa);
