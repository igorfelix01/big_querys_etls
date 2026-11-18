-- [otimizacao] CTE 'contrato' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE contrato AS
  SELECT
    CAST(ChaveGeral AS STRING)     AS ChaveGeral,
    ANY_VALUE(groupCompanyName)    AS groupCompanyName,
    ANY_VALUE(companyName)         AS companyName,
    ANY_VALUE(cancellationDate)    AS cancellationDate
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  WHERE documentIdentificationId = 'CT'
    AND subJudicie = 'N'
    AND IFNULL(TRIM(groupCompanyName), '') <> ''
    AND NOT REGEXP_CONTAINS(
          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),
          r'BLOKO')
  GROUP BY 1;

-- ####################################################################
-- COBRANCA: RISCO DE ROLAGEM PARA INADIMPLENCIA
--
-- Pergunta: dos contratos que estao ATRASADOS hoje (1 a 89 dias), quais
-- vao virar INADIMPLENTES (90+ dias) e quanto dinheiro isso representa?
--
-- Como: usa o historico diario (analytics.HistoricoInadimplencia) para
-- medir, no passado, quantos contratos que chegaram a X dias de atraso
-- seguiram ate 90+ dias (sem regularizar). Essa taxa vira a probabilidade
-- de cada contrato atrasado hoje, e
--   ValorEmRiscoEsperado = probabilidade x saldo em aberto do contrato.
--
-- Cria 2 tabelas:
--   looker_studio.cobranca_curva_rolagem
--     grupo x ano do inicio do atraso x faixa -> episodios, quantos
--     viraram inadimplentes, quantos se regularizaram
--     (no Looker: SOMA(Viraram)/SOMA(Episodios) = taxa de rolagem)
--   looker_studio.cobranca_risco_contratos
--     1 linha por contrato atrasado hoje, com probabilidade, valor em
--     risco e a ordem de prioridade de cobranca
--
-- Episodio de atraso = dias seguidos com DiasAtraso > 0 no contrato.
-- Maturidade: so entram na curva os episodios que comecaram ha 120 dias
-- ou mais (episodio recente ainda nao teve tempo de chegar a 90 dias e
-- puxaria a taxa para baixo). NAO e filtro de periodo: o periodo continua
-- livre no Looker pelo campo AnoInicioEpisodio.
--
-- Universo: CT, sem sub judice, sem empresas Bloko.
-- Historico cortado na data do distrato (depois dele as parcelas
-- canceladas pareciam "abertas" e inflavam a rolagem). Distrato durante
-- o atraso conta como perda (rolou). "Hoje" = ultimo dia do historico.
-- Se o grupo tiver menos de 30 episodios na faixa, usa a taxa geral.
--
-- Depende de: analytics.HistoricoInadimplencia,
--             analytics.fato_titulos_totalizador, analytics.saldo_devedor
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.cobranca_curva_rolagem`
CLUSTER BY groupCompanyName
AS
WITH
hoje AS (
  SELECT MAX(Data) AS d
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`
),

marcado AS (
  SELECT
    CAST(h.ChaveGeral AS STRING) AS ChaveGeral,
    h.Data,
    h.DiasAtraso,
    -- cada dia em dia (DiasAtraso = 0) fecha o episodio anterior
    COUNTIF(h.DiasAtraso = 0) OVER (
      PARTITION BY h.ChaveGeral ORDER BY h.Data) AS grupo_zero
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h
  JOIN contrato c
    ON c.ChaveGeral = CAST(h.ChaveGeral AS STRING)
  -- depois do distrato as parcelas canceladas parecem "abertas": corta
  WHERE h.Data < IFNULL(c.cancellationDate, DATE '9999-12-31')
),

episodio AS (
  SELECT
    ChaveGeral,
    grupo_zero,
    MIN(Data)       AS inicio,
    MAX(Data)       AS ultimo_dia,
    MAX(DiasAtraso) AS max_atraso
  FROM marcado
  WHERE DiasAtraso > 0
  GROUP BY 1, 2
),

faixas AS (
  SELECT * FROM UNNEST([
    STRUCT(1 AS De, '01-15 dias' AS Faixa),
    (16, '16-30 dias'),
    (31, '31-60 dias'),
    (61, '61-89 dias')
  ])
)
SELECT
  c.groupCompanyName,
  c.companyName,
  EXTRACT(YEAR FROM e.inicio)                                   AS AnoInicioEpisodio,
  DATE_TRUNC(e.inicio, MONTH)                                   AS MesInicioEpisodio,
  f.De                                                          AS FaixaDe,
  f.Faixa,
  COUNT(*)                                                      AS Episodios,
  -- distrato durante o atraso (antes dos 90 dias) tambem conta como perda
  COUNTIF(e.max_atraso >= 90 OR distratou)                      AS ViraramInadimplentes,
  COUNTIF(e.max_atraso < 90 AND NOT distratou AND e.ultimo_dia < h.d) AS Regularizaram,
  COUNTIF(e.max_atraso < 90 AND NOT distratou AND e.ultimo_dia = h.d) AS AindaAtrasados
FROM (
  SELECT
    e.*,
    IFNULL(e.ultimo_dia >= DATE_SUB(c.cancellationDate, INTERVAL 1 DAY), FALSE) AS distratou
  FROM episodio e
  JOIN contrato c USING (ChaveGeral)
) e
JOIN contrato c USING (ChaveGeral)
CROSS JOIN hoje h
JOIN faixas f
  ON e.max_atraso >= f.De
WHERE e.inicio <= DATE_SUB(h.d, INTERVAL 120 DAY)   -- maturidade (ver cabecalho)
GROUP BY 1, 2, 3, 4, 5, 6;


-- ####################################################################
-- CONTRATOS ATRASADOS HOJE: probabilidade e valor em risco
-- ####################################################################
CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.cobranca_risco_contratos`
CLUSTER BY groupCompanyName
AS

WITH

hoje AS (
  SELECT MAX(Data) AS d
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`
),

contrato AS (
  SELECT
    CAST(ChaveGeral AS STRING)       AS ChaveGeral,
    ANY_VALUE(groupCompanyName)      AS groupCompanyName,
    ANY_VALUE(companyName)           AS companyName,
    ANY_VALUE(clientName)            AS clientName,
    ANY_VALUE(anoPeriodoVenda)       AS anoPeriodoVenda,
    ANY_VALUE(SaldoDevedorComJuros)  AS SaldoEmAberto
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  WHERE documentIdentificationId = 'CT'
    AND subJudicie = 'N'
    AND cancellationDate IS NULL
    AND IFNULL(TRIM(groupCompanyName), '') <> ''
    AND NOT REGEXP_CONTAINS(
          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),
          r'BLOKO')
  GROUP BY 1
),

-- taxa de rolagem por grupo e faixa (todo o historico maduro)
curva_grupo AS (
  SELECT groupCompanyName, FaixaDe,
         SUM(Episodios) AS ep, SUM(ViraramInadimplentes) AS vir
  FROM `dadosfinanceiro-501613.looker_studio.cobranca_curva_rolagem`
  GROUP BY 1, 2
),

curva_geral AS (
  SELECT FaixaDe,
         SUM(Episodios) AS ep, SUM(ViraramInadimplentes) AS vir
  FROM `dadosfinanceiro-501613.looker_studio.cobranca_curva_rolagem`
  GROUP BY 1
),

atual AS (
  SELECT
    CAST(h.ChaveGeral AS STRING) AS ChaveGeral,
    h.DiasAtraso,
    h.QtdParcelas
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h, hoje
  WHERE h.Data = hoje.d
    AND h.DiasAtraso BETWEEN 1 AND 89
),

vencido AS (
  SELECT
    CAST(ChaveGeral AS STRING) AS ChaveGeral,
    SUM(ValorBruto)            AS ValorVencido
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`, hoje
  WHERE OrigemBase = 'A Receber'
    AND dueDate < hoje.d
  GROUP BY 1
),

base AS (
  SELECT
    a.ChaveGeral,
    c.groupCompanyName,
    c.companyName,
    c.clientName,
    c.anoPeriodoVenda,
    a.DiasAtraso,
    a.QtdParcelas                                  AS ParcelasVencidas,
    CASE WHEN a.DiasAtraso <= 15 THEN 1
         WHEN a.DiasAtraso <= 30 THEN 16
         WHEN a.DiasAtraso <= 60 THEN 31
         ELSE 61 END                               AS FaixaDe,
    IFNULL(v.ValorVencido, 0)                      AS ValorVencido,
    IFNULL(c.SaldoEmAberto, 0)                     AS SaldoEmAberto
  FROM atual a
  JOIN contrato c USING (ChaveGeral)
  LEFT JOIN vencido v USING (ChaveGeral)
)

SELECT
  b.ChaveGeral,
  b.groupCompanyName,
  b.companyName,
  b.clientName,
  b.anoPeriodoVenda,
  b.DiasAtraso,
  CASE b.FaixaDe WHEN 1 THEN '01-15 dias' WHEN 16 THEN '16-30 dias'
                 WHEN 31 THEN '31-60 dias' ELSE '61-89 dias' END        AS Faixa,
  b.ParcelasVencidas,
  ROUND(b.ValorVencido, 2)                                              AS ValorVencido,
  ROUND(b.SaldoEmAberto, 2)                                             AS SaldoEmAberto,
  IF(IFNULL(cg.ep, 0) >= 30, 'Grupo', 'Geral')                          AS BaseDaTaxa,
  ROUND(IF(IFNULL(cg.ep, 0) >= 30,
           SAFE_DIVIDE(cg.vir, cg.ep),
           SAFE_DIVIDE(gg.vir, gg.ep)), 4)                              AS ProbInadimplencia,
  ROUND(b.SaldoEmAberto * IF(IFNULL(cg.ep, 0) >= 30,
           SAFE_DIVIDE(cg.vir, cg.ep),
           SAFE_DIVIDE(gg.vir, gg.ep)), 2)                              AS ValorEmRiscoEsperado,
  RANK() OVER (ORDER BY b.SaldoEmAberto * IF(IFNULL(cg.ep, 0) >= 30,
           SAFE_DIVIDE(cg.vir, cg.ep),
           SAFE_DIVIDE(gg.vir, gg.ep)) DESC)                            AS PrioridadeCobranca,
  hoje.d                                                                AS DataReferencia
FROM base b
CROSS JOIN hoje
LEFT JOIN curva_grupo cg
  ON cg.groupCompanyName = b.groupCompanyName AND cg.FaixaDe = b.FaixaDe
LEFT JOIN curva_geral gg
  ON gg.FaixaDe = b.FaixaDe;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- RESULTADO RAPIDO
-- ####################################################################

-- (1) taxa de rolagem por faixa (carteira toda): "de cada 100 contratos
--     que chegam a X dias de atraso, quantos viram inadimplentes?"
-- SELECT
--   Faixa,
--   SUM(Episodios)                                                AS episodios,
--   ROUND(100 * SAFE_DIVIDE(SUM(ViraramInadimplentes), SUM(Episodios)), 1) AS pct_viram_inadimplentes,
--   ROUND(100 * SAFE_DIVIDE(SUM(Regularizaram), SUM(Episodios)), 1)        AS pct_regularizam
-- FROM `dadosfinanceiro-501613.looker_studio.cobranca_curva_rolagem`
-- GROUP BY 1
-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (2) dinheiro em risco hoje, por grupo
-- SELECT
--   groupCompanyName,
--   COUNT(*)                          AS contratos_atrasados,
--   ROUND(SUM(ValorVencido))          AS vencido,
--   ROUND(SUM(SaldoEmAberto))         AS saldo_em_aberto,
--   ROUND(SUM(ValorEmRiscoEsperado))  AS valor_em_risco_esperado
-- FROM `dadosfinanceiro-501613.looker_studio.cobranca_risco_contratos`
-- GROUP BY 1
-- ORDER BY valor_em_risco_esperado DESC;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (3) os 30 contratos onde a cobranca vale mais a pena agora
-- SELECT
--   PrioridadeCobranca, ChaveGeral, groupCompanyName, clientName, DiasAtraso,
--   ValorVencido, SaldoEmAberto, ProbInadimplencia, ValorEmRiscoEsperado
-- FROM `dadosfinanceiro-501613.looker_studio.cobranca_risco_contratos`
-- ORDER BY PrioridadeCobranca
-- LIMIT 30;