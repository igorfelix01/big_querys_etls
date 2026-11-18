-- SEM particao (validade de particao de 60 dias apagava os meses antigos)
-- DiaParametro = filtro "Dias" do Looker (igual ao BI): cada linha traz o
--   recebido ACUMULADO do dia 1 ate o DiaParametro (31 = mes todo).
--   Em aberto (sem data de pagamento) entra em todos os dias.
--   No Looker: lista suspensa no campo DiaParametro, SELECAO UNICA, padrao 31.
DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.recebiveis_grafico_mensal`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.recebiveis_grafico_mensal`
CLUSTER BY DiaParametro, documentIdentificationId, companyGroup, companyName
AS
SELECT
  d.DiaParametro,
  MesReferencia,
  paymentYear,
  paymentMonth,
  documentIdentificationId,
  subJudicie,
  companyGroup,
  anoPeriodoVenda,
  companyId,
  companyName,
  costCenterId,
  costCenterName,

  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Adimplente'    THEN ValorBruto_EfeitoCaixa ELSE 0 END), 2) AS Adimplente_ValorBruto,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Atrasado'      THEN ValorBruto_EfeitoCaixa ELSE 0 END), 2) AS Atrasado_ValorBruto,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Inadimplente'  THEN ValorBruto_EfeitoCaixa ELSE 0 END), 2) AS Inadimplente_ValorBruto,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Antecipado'    THEN ValorBruto_EfeitoCaixa ELSE 0 END), 2) AS Antecipado_ValorBruto,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Quitação'      THEN ValorBruto_EfeitoCaixa ELSE 0 END), 2) AS Quitacao_ValorBruto,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Venda à vista' THEN ValorBruto_EfeitoCaixa ELSE 0 END), 2) AS VendaAVista_ValorBruto,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Ato'           THEN ValorBruto_EfeitoCaixa ELSE 0 END), 2) AS Ato_ValorBruto,

  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Adimplente'    THEN ValorBloko_EfeitoCaixa ELSE 0 END), 2) AS Adimplente_ValorBloko,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Atrasado'      THEN ValorBloko_EfeitoCaixa ELSE 0 END), 2) AS Atrasado_ValorBloko,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Inadimplente'  THEN ValorBloko_EfeitoCaixa ELSE 0 END), 2) AS Inadimplente_ValorBloko,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Antecipado'    THEN ValorBloko_EfeitoCaixa ELSE 0 END), 2) AS Antecipado_ValorBloko,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Quitação'      THEN ValorBloko_EfeitoCaixa ELSE 0 END), 2) AS Quitacao_ValorBloko,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Venda à vista' THEN ValorBloko_EfeitoCaixa ELSE 0 END), 2) AS VendaAVista_ValorBloko,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Ato'           THEN ValorBloko_EfeitoCaixa ELSE 0 END), 2) AS Ato_ValorBloko,

  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Adimplente'    THEN ValorParceiro_EfeitoCaixa ELSE 0 END), 2) AS Adimplente_ValorParceiro,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Atrasado'      THEN ValorParceiro_EfeitoCaixa ELSE 0 END), 2) AS Atrasado_ValorParceiro,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Inadimplente'  THEN ValorParceiro_EfeitoCaixa ELSE 0 END), 2) AS Inadimplente_ValorParceiro,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Antecipado'    THEN ValorParceiro_EfeitoCaixa ELSE 0 END), 2) AS Antecipado_ValorParceiro,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Quitação'      THEN ValorParceiro_EfeitoCaixa ELSE 0 END), 2) AS Quitacao_ValorParceiro,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Venda à vista' THEN ValorParceiro_EfeitoCaixa ELSE 0 END), 2) AS VendaAVista_ValorParceiro,
  ROUND(SUM(CASE WHEN SituacaoParcelaVisual = 'Ato'           THEN ValorParceiro_EfeitoCaixa ELSE 0 END), 2) AS Ato_ValorParceiro,

  ROUND(SUM(ValorBruto_EfeitoCaixa), 2)    AS TotalBarras_ValorBruto,
  ROUND(SUM(ValorBloko_EfeitoCaixa), 2)    AS TotalBarras_ValorBloko,
  ROUND(SUM(ValorParceiro_EfeitoCaixa), 2) AS TotalBarras_ValorParceiro,

  ROUND(SUM(ValorEmAberto), 2)         AS ValorEmAberto,
  ROUND(SUM(ValorEmAbertoBloko), 2)    AS ValorEmAbertoBloko,
  ROUND(SUM(ValorEmAbertoParceiro), 2) AS ValorEmAbertoParceiro,

  ROUND(SUM(ValorBruto_Total), 2)    AS ValorBruto_Total,
  ROUND(SUM(ValorBloko_Total), 2)    AS ValorBloko_Total,
  ROUND(SUM(ValorParceiro_Total), 2) AS ValorParceiro_Total,

  ROUND(IFNULL(SUM(ValorBruto_EfeitoCaixa), 0)    + IFNULL(SUM(ValorEmAberto), 0), 2)         AS ValorCompetenciaTotal_ValorBruto,
  ROUND(IFNULL(SUM(ValorBloko_EfeitoCaixa), 0)    + IFNULL(SUM(ValorEmAbertoBloko), 0), 2)    AS ValorCompetenciaTotal_ValorBloko,
  ROUND(IFNULL(SUM(ValorParceiro_EfeitoCaixa), 0) + IFNULL(SUM(ValorEmAbertoParceiro), 0), 2) AS ValorCompetenciaTotal_ValorParceiro,

  SUM(linhas)                    AS linhas,
  SUM(contagem_chave_especifica) AS contagem_chave_especifica,
  SUM(chaves_distintas)          AS chaves_distintas,
  SUM(contratos)                 AS contratos

FROM `dadosfinanceiro-501613.looker_studio.recebiveis_historico_mensal` h
JOIN (SELECT dia AS DiaParametro FROM UNNEST(GENERATE_ARRAY(1, 31)) AS dia) d
  ON IFNULL(h.NumeroDiaDaSemana, 0) <= d.DiaParametro   -- acumulado ate o dia
GROUP BY
  d.DiaParametro, MesReferencia, paymentYear, paymentMonth, documentIdentificationId,
  subJudicie, companyGroup, anoPeriodoVenda, companyId, companyName,
  costCenterId, costCenterName;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- CONFERENCIA: recebido (Efeito Caixa) ate o dia 15 e no mes todo, ultimos meses
-- ####################################################################
-- SELECT
--   MesReferencia,
--   ROUND(SUM(IF(DiaParametro = 15, TotalBarras_ValorBruto, 0))) AS recebido_ate_dia_15,
--   ROUND(SUM(IF(DiaParametro = 31, TotalBarras_ValorBruto, 0))) AS recebido_mes_todo
-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_grafico_mensal`
-- WHERE documentIdentificationId = 'CT'
--   AND companyGroup <> 'Bloko Capital'
--   AND MesReferencia >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 6 MONTH)
-- GROUP BY 1
-- ORDER BY 1;