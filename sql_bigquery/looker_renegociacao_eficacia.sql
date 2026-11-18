-- [otimizacao] CTE 'base' usada 4x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base AS
WITH
contrato AS (
  SELECT
    CAST(ChaveGeral AS STRING)      AS ChaveGeral,
    ANY_VALUE(groupCompanyName)     AS groupCompanyName,
    ANY_VALUE(companyName)          AS companyName,
    ANY_VALUE(clientName)           AS clientName,
    ANY_VALUE(Telefone)             AS Telefone,
    ANY_VALUE(SituacaoContrato)     AS SituacaoContratoHoje,
    ANY_VALUE(SaldoDevedorComJuros) AS SaldoEmAberto,
    ANY_VALUE(cancellationDate)     AS cancellationDate
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  WHERE documentIdentificationId = 'CT'
    AND IFNULL(TRIM(groupCompanyName), '') <> ''
    AND NOT REGEXP_CONTAINS(
          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),
          r'BLOKO')
  GROUP BY 1
),

evento AS (
  SELECT
    CAST(r.ChaveGeral AS STRING)               AS ChaveGeral,
    r.paymentDate                              AS DataRenegociacao,
    ANY_VALUE(r.Companhia)                     AS Companhia,
    ANY_VALUE(r.costCenterName)                AS costCenterName,
    MIN(r.qtd_renegociacoes_ate_aquele_dia) + 1 AS NumeroRenegociacao,
    ANY_VALUE(r.qtd_renegociacoes_totais)      AS RenegociacoesTotaisContrato
  FROM `dadosfinanceiro-501613.analytics.fato_renegociacoes` r
  WHERE r.paymentDate IS NOT NULL
    AND r.documentIdentificationId = 'CT'
  GROUP BY 1, 2
)
SELECT * FROM (

  SELECT e.*, c.* EXCEPT (ChaveGeral)
  FROM evento e
  JOIN contrato c USING (ChaveGeral)
  WHERE e.DataRenegociacao < IFNULL(c.cancellationDate, DATE '9999-12-31')

);

-- ####################################################################
-- AS RENEGOCIACOES FUNCIONAM?
--
-- Pergunta: depois de renegociar (reparcelamento), quantos % dos
-- contratos SE MANTIVERAM EM DIA e quantos % VOLTARAM A ATRASAR?
-- Olhando 3, 6 e 12 meses depois da renegociacao.
--
-- Mesmo modelo dos graficos de rolagem / regularizacao:
--   Manteve em dia     nunca passou de 29 dias de atraso no periodo
--   Voltou a atrasar   chegou a 30+ dias de atraso (ou distratou)
--                      dentro do periodo
--   (as duas somam 100%)
--
-- Renegociacao = data de pagamento do Reparcelamento (CT) em
-- analytics.fato_renegociacoes (1 evento por contrato x data).
-- Atraso depois = analytics.HistoricoInadimplencia (cortado no distrato).
-- Um evento so entra num horizonte (3/6/12 meses) se ja passou esse
-- tempo desde a renegociacao (senao ainda nao da para saber).
-- Sem periodo fixo: filtrar AnoRenegociacao / DataRenegociacao no Looker.
--
-- Cria 2 tabelas:
--   looker_studio.renegociacao_eficacia
--     1 linha por renegociacao: atraso antes, voltou a atrasar em 3/6/12
--     meses, virou inadimplente, quanto pagou nos 6 meses seguintes,
--     situacao hoje (lista para o Looker)
--   looker_studio.renegociacao_eficacia_curva
--     grupo x ano x horizonte x atraso antes -> renegociacoes,
--     mantiveram em dia, voltaram a atrasar
--     Looker: SOMA(MantiveramEmDia)/SOMA(Renegociacoes) e
--             SOMA(VoltaramAtrasar)/SOMA(Renegociacoes)
--
-- Universo: CT, sem empresas Bloko.
--
-- Depende de: analytics.fato_renegociacoes, analytics.HistoricoInadimplencia,
--             analytics.fato_titulos_totalizador, analytics.fato_recebidas
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.renegociacao_eficacia`
CLUSTER BY Companhia, DataRenegociacao
AS
WITH
hoje AS (
  SELECT MAX(Data) AS d
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`
),

antes AS (
  SELECT b.ChaveGeral, b.DataRenegociacao, MAX(h.DiasAtraso) AS AtrasoAntes
  FROM base b
  JOIN `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h
    ON CAST(h.ChaveGeral AS STRING) = b.ChaveGeral
   AND h.Data = DATE_SUB(b.DataRenegociacao, INTERVAL 1 DAY)
  GROUP BY 1, 2
),

depois AS (
  SELECT
    b.ChaveGeral,
    b.DataRenegociacao,
    MAX(IF(h.Data <= DATE_ADD(b.DataRenegociacao, INTERVAL 3 MONTH),  h.DiasAtraso, NULL)) AS max_3m,
    MAX(IF(h.Data <= DATE_ADD(b.DataRenegociacao, INTERVAL 6 MONTH),  h.DiasAtraso, NULL)) AS max_6m,
    MAX(h.DiasAtraso)                                                                      AS max_12m,
    -- a renegociacao zerou o atraso? (menor atraso nos 10 primeiros dias)
    MIN(IF(h.Data <= DATE_ADD(b.DataRenegociacao, INTERVAL 10 DAY), h.DiasAtraso, NULL))   AS min_10d
  FROM base b
  JOIN `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h
    ON CAST(h.ChaveGeral AS STRING) = b.ChaveGeral
   AND h.Data >  b.DataRenegociacao
   AND h.Data <= DATE_ADD(b.DataRenegociacao, INTERVAL 12 MONTH)
   AND h.Data <  IFNULL(b.cancellationDate, DATE '9999-12-31')
  GROUP BY 1, 2
),

pagou AS (
  SELECT
    b.ChaveGeral,
    b.DataRenegociacao,
    COUNT(DISTINCT CONCAT(CAST(r.ChaveEspecifica AS STRING), '|', CAST(r.dueDate AS STRING))) AS ParcelasPagas6m,
    SUM(r.ValorBruto)                                                                        AS ValorPago6m
  FROM base b
  JOIN `dadosfinanceiro-501613.analytics.fato_recebidas` r
    ON CAST(r.ChaveGeral AS STRING) = b.ChaveGeral
   AND r.paymentDate >  b.DataRenegociacao
   AND r.paymentDate <= DATE_ADD(b.DataRenegociacao, INTERVAL 6 MONTH)
   AND r.Conta = 'Efeito Caixa'
  GROUP BY 1, 2
),

atual AS (
  SELECT CAST(h.ChaveGeral AS STRING) AS ChaveGeral, h.DiasAtraso AS DiasAtrasoHoje
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h, hoje
  WHERE h.Data = hoje.d
)
SELECT
  b.ChaveGeral,
  b.DataRenegociacao,
  EXTRACT(YEAR FROM b.DataRenegociacao)                           AS AnoRenegociacao,
  b.Companhia,
  b.groupCompanyName,
  b.companyName,
  b.costCenterName,
  b.clientName,
  b.Telefone,
  b.NumeroRenegociacao,
  b.RenegociacoesTotaisContrato,

  IFNULL(a.AtrasoAntes, 0)                                        AS AtrasoAntes,
  CASE
    WHEN IFNULL(a.AtrasoAntes, 0) = 0  THEN '1. Em dia'
    WHEN a.AtrasoAntes < 90           THEN '2. Atrasado (1-89 dias)'
    ELSE                                   '3. Inadimplente (90+ dias)'
  END                                                             AS SituacaoAntes,

  -- horizontes ja observados?
  DATE_ADD(b.DataRenegociacao, INTERVAL 3 MONTH)  <= h.d          AS Observado3m,
  DATE_ADD(b.DataRenegociacao, INTERVAL 6 MONTH)  <= h.d          AS Observado6m,
  DATE_ADD(b.DataRenegociacao, INTERVAL 12 MONTH) <= h.d          AS Observado12m,

  -- voltou a atrasar 30+ dias (ou distratou) dentro do horizonte
  IFNULL(dp.max_3m >= 30, FALSE)
    OR IFNULL(b.cancellationDate <= DATE_ADD(b.DataRenegociacao, INTERVAL 3 MONTH), FALSE)  AS VoltouAtrasar3m,
  IFNULL(dp.max_6m >= 30, FALSE)
    OR IFNULL(b.cancellationDate <= DATE_ADD(b.DataRenegociacao, INTERVAL 6 MONTH), FALSE)  AS VoltouAtrasar6m,
  IFNULL(dp.max_12m >= 30, FALSE)
    OR IFNULL(b.cancellationDate <= DATE_ADD(b.DataRenegociacao, INTERVAL 12 MONTH), FALSE) AS VoltouAtrasar12m,
  IFNULL(dp.max_12m >= 90, FALSE)                                 AS VirouInadimplente12m,
  IFNULL(dp.max_12m, 0)                                           AS MaiorAtraso12m,
  -- TRUE = ficou em dia logo depois de renegociar (esperado).
  -- FALSE = o atraso continuou: a renegociacao nao zerou o atraso no
  -- historico (conferir com a consulta 3 do final)
  IFNULL(dp.min_10d = 0, TRUE)                                    AS EmDiaAposRenegociacao,

  IFNULL(p.ParcelasPagas6m, 0)                                    AS ParcelasPagas6m,
  ROUND(IFNULL(p.ValorPago6m, 0), 2)                              AS ValorPago6m,

  b.SituacaoContratoHoje,
  IF(b.cancellationDate IS NOT NULL, NULL, t.DiasAtrasoHoje)      AS DiasAtrasoHoje,
  b.cancellationDate                                              AS DataDistrato,
  ROUND(IFNULL(b.SaldoEmAberto, 0), 2)                            AS SaldoEmAberto,
  h.d                                                             AS DataReferencia
FROM base b
CROSS JOIN hoje h
LEFT JOIN antes  a  USING (ChaveGeral, DataRenegociacao)
LEFT JOIN depois dp USING (ChaveGeral, DataRenegociacao)
LEFT JOIN pagou  p  USING (ChaveGeral, DataRenegociacao)
LEFT JOIN atual  t  USING (ChaveGeral);


-- ####################################################################
-- CURVA: manteve em dia x voltou a atrasar, por horizonte
-- ####################################################################
CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.renegociacao_eficacia_curva`
CLUSTER BY Companhia
AS
SELECT
  e.Companhia,
  e.groupCompanyName,
  e.costCenterName,
  e.AnoRenegociacao,
  DATE_TRUNC(e.DataRenegociacao, MONTH)                     AS MesRenegociacao,
  e.SituacaoAntes,
  IF(e.NumeroRenegociacao = 1, '1a renegociacao', '2a ou mais') AS TipoRenegociacao,
  hz.HorizonteMeses,
  hz.Horizonte,
  COUNT(*)                                                  AS Renegociacoes,
  COUNTIF(NOT hz.voltou)                                    AS MantiveramEmDia,
  COUNTIF(hz.voltou)                                        AS VoltaramAtrasar,
  COUNTIF(hz.HorizonteMeses = 12 AND e.VirouInadimplente12m) AS ViraramInadimplentes12m,
  ROUND(SUM(IF(hz.HorizonteMeses = 6, e.ValorPago6m, 0)), 2) AS ValorPago6m
FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eficacia` e,
UNNEST([
  STRUCT(3  AS HorizonteMeses, '03 meses depois' AS Horizonte, e.Observado3m  AS observado, e.VoltouAtrasar3m  AS voltou),
  STRUCT(6,  '06 meses depois', e.Observado6m,  e.VoltouAtrasar6m),
  STRUCT(12, '12 meses depois', e.Observado12m, e.VoltouAtrasar12m)
]) AS hz
WHERE hz.observado
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- RESULTADO RAPIDO
-- ####################################################################

-- (1) depois de renegociar: % que manteve em dia x % que voltou a atrasar
-- SELECT
--   Horizonte,
--   SUM(Renegociacoes)                                                     AS renegociacoes,
--   ROUND(100 * SAFE_DIVIDE(SUM(MantiveramEmDia), SUM(Renegociacoes)), 1)  AS pct_mantiveram_em_dia,
--   ROUND(100 * SAFE_DIVIDE(SUM(VoltaramAtrasar), SUM(Renegociacoes)), 1)  AS pct_voltaram_atrasar
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eficacia_curva`
-- GROUP BY 1
-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (3) conferencia: a renegociacao zerou o atraso no historico?
--     (se muitos FALSE, o "voltou a atrasar" esta pegando o atraso antigo)
-- SELECT
--   EmDiaAposRenegociacao,
--   COUNT(*) AS renegociacoes
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eficacia`
-- GROUP BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (2) 1a renegociacao x quem ja renegociou antes (12 meses depois)
-- SELECT
--   TipoRenegociacao,
--   SituacaoAntes,
--   SUM(Renegociacoes)                                                     AS renegociacoes,
--   ROUND(100 * SAFE_DIVIDE(SUM(VoltaramAtrasar), SUM(Renegociacoes)), 1)  AS pct_voltaram_atrasar
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eficacia_curva`
-- WHERE HorizonteMeses = 12
-- GROUP BY 1, 2
-- ORDER BY 1, 2;