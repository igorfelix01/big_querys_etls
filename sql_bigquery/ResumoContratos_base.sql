-- ####################################################################
-- ANALYTICS.RESUMOCONTRATOS
--
-- Quantidade de contratos por Data x Companhia x Situacao.
-- Le:
--   analytics.HistoricoInadimplencia  (Data, ChaveGeral, DiasAtraso)
--   analytics.fato_titulos_totalizador (1 linha por contrato: companhia,
--     grupo e subJudicie) -> substitui a antiga analytics.Cliente
--
-- Regra de situacao mantida igual a versao anterior:
--   DiasAtraso = 0  -> Adimplente
--   DiasAtraso < 90 -> Atrasado
--   senao           -> Inadimplente
-- Filtro: subJudicie = 'N'. Sem limite de periodo (filtro no Looker).
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.analytics.ResumoContratos`
AS

WITH

contrato AS (
  SELECT
    ChaveGeral,
    companyName      AS Companhia,
    groupCompanyName AS GrupoCompanhia,
    subJudicie
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral ORDER BY ChaveGeral) = 1
)

SELECT
  h.Data,
  c.Companhia,
  c.GrupoCompanhia,

  CASE
    WHEN h.DiasAtraso = 0  THEN 'Adimplente'
    WHEN h.DiasAtraso < 90 THEN 'Atrasado'
    ELSE 'Inadimplente'
  END AS Situacao,

  COUNT(DISTINCT h.ChaveGeral) AS QtdDeClientes

FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` AS h
INNER JOIN contrato AS c
  ON h.ChaveGeral = c.ChaveGeral

WHERE c.subJudicie = 'N'

GROUP BY
  h.Data,
  c.Companhia,
  c.GrupoCompanhia,
  Situacao;