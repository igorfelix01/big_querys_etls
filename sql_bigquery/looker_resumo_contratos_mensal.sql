-- ####################################################################
-- LOOKER_STUDIO.RESUMO_CONTRATOS_MENSAL
-- Grafico "Quantidade de Contratos - Sem Subjudicie" (linha por mes)
--
-- A analytics.ResumoContratos tem 1 linha POR DIA. Somando o mes inteiro
-- o Looker contava os DIAS (28, 30, 31...) ou somava 30 vezes o mesmo
-- contrato. Aqui fica 1 FOTO POR MES: a quantidade de contratos no
-- ULTIMO DIA do mes (no mes corrente, o ultimo dia que existe na base).
--
-- No Looker: Dimensao = Mes | Detalhamento = Situacao |
--            Metrica = QtdDeClientes (SOMA)
-- Filtros: Companhia (Loteadora), GrupoCompanhia, Situacao.
-- SEM periodo fixo: filtro de data do Looker no campo Mes.
--
-- Depende de: analytics.ResumoContratos
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.resumo_contratos_mensal`
AS

WITH ultimo_dia AS (
  SELECT
    DATE_TRUNC(Data, MONTH) AS Mes,
    MAX(Data)               AS Data
  FROM `dadosfinanceiro-501613.analytics.ResumoContratos`
  GROUP BY 1
)

SELECT
  u.Mes,
  r.Data,
  r.Companhia,
  r.GrupoCompanhia,
  r.Situacao,
  CASE r.Situacao
    WHEN 'Adimplente'   THEN 1
    WHEN 'Atrasado'     THEN 2
    WHEN 'Inadimplente' THEN 3
  END                     AS OrdemSituacao,
  r.QtdDeClientes
FROM `dadosfinanceiro-501613.analytics.ResumoContratos` r
JOIN ultimo_dia u
  ON u.Data = r.Data;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- CONFERENCIA: contratos por mes e situacao (ultimos 12 meses)
-- SELECT Mes, Situacao, SUM(QtdDeClientes) AS contratos
-- FROM `dadosfinanceiro-501613.looker_studio.resumo_contratos_mensal`
-- WHERE Mes >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 12 MONTH)
-- GROUP BY 1, 2
-- ORDER BY 1, 2;