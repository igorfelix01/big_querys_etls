-- [otimizacao] CTE 'contrato' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE contrato AS
  SELECT
    CAST(ChaveGeral AS STRING)      AS ChaveGeral,
    ANY_VALUE(groupCompanyName)     AS groupCompanyName,
    ANY_VALUE(companyName)          AS companyName,
    ANY_VALUE(subJudicie)           AS subJudicie,
    ANY_VALUE(cancellationDate)     AS cancellationDate
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  WHERE documentIdentificationId = 'CT'
    AND IFNULL(TRIM(groupCompanyName), '') <> ''
    AND NOT REGEXP_CONTAINS(
          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),
          r'BLOKO')
  GROUP BY 1;

-- ####################################################################
-- INADIMPLENTES QUE VOLTAM A FICAR ADIMPLENTES
--
-- Pergunta: dos contratos que viraram INADIMPLENTES (90+ dias de
-- atraso), quantos % VOLTARAM A FICAR ADIMPLENTES (em dia)?
-- E quanto mais tempo inadimplente, menor a chance de voltar?
--
-- Mesmo modelo do "risco de rolagem" (looker_cobranca_risco_rolagem.sql),
-- um passo adiante:
--   rolagem  = atrasado -> virou inadimplente (ou regularizou)
--   aqui     = inadimplente -> voltou a ficar adimplente (ou nao voltou)
--
-- Episodio = dias seguidos com atraso (> 0) que chegaram a 90+ dias.
-- Resultado do episodio:
--   Voltou a ficar adimplente  pagou o atrasado e voltou a 0 dia de
--                              atraso (ou quitou o contrato)
--   Nao voltou                 continua inadimplente hoje, ou o contrato
--                              foi distratado sem voltar a ficar em dia
-- Faixas (quanto tempo de atraso o episodio chegou a ter):
--   90+ dias | 180+ dias (6 meses) | 365+ dias (1 ano) | 730+ dias (2 anos)
-- Maturidade: so entram episodios que chegaram a faixa ha 180 dias ou
-- mais (episodio recente ainda nao teve tempo de se regularizar e
-- puxaria a taxa para baixo). NAO e filtro de periodo: o periodo fica
-- livre no Looker (AnoInadimplencia / MesInadimplencia).
--
-- Cria 2 tabelas:
--   looker_studio.inadimplencia_regularizacao_curva
--     grupo x ano em que virou inadimplente x faixa -> episodios,
--     voltaram a ficar adimplentes, nao voltaram, dias ate voltar
--     Looker: SOMA(VoltaramAdimplentes)/SOMA(Episodios) = taxa de regularizacao
--             SOMA(NaoVoltaram)/SOMA(Episodios)         = taxa de nao regularizacao
--             (as duas somam 100%)
--   looker_studio.inadimplencia_regularizacao_contratos
--     1 linha por contrato INADIMPLENTE hoje, com a chance de voltar a
--     ficar adimplente (pela faixa em que ele esta) e o saldo recuperavel
--
-- Universo: CT, sem empresas Bloko. subJudicie vem como coluna (filtro).
-- Historico cortado na data do distrato (depois dele as parcelas
-- canceladas pareceriam "abertas"). "Hoje" = ultimo dia do historico.
--
-- Depende de: analytics.HistoricoInadimplencia, analytics.fato_titulos_totalizador
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.inadimplencia_regularizacao_curva`
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
    COUNTIF(h.DiasAtraso = 0) OVER (
      PARTITION BY h.ChaveGeral ORDER BY h.Data) AS grupo_zero
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h
  JOIN contrato c
    ON c.ChaveGeral = CAST(h.ChaveGeral AS STRING)
  WHERE h.Data < IFNULL(c.cancellationDate, DATE '9999-12-31')
),

episodio AS (
  SELECT
    ChaveGeral,
    grupo_zero,
    MIN(Data)                              AS inicio,
    MAX(Data)                              AS ultimo_dia,
    MAX(DiasAtraso)                        AS max_atraso,
    MIN(IF(DiasAtraso >= 90,  Data, NULL)) AS data_90,
    MIN(IF(DiasAtraso >= 180, Data, NULL)) AS data_180,
    MIN(IF(DiasAtraso >= 365, Data, NULL)) AS data_365,
    MIN(IF(DiasAtraso >= 730, Data, NULL)) AS data_730
  FROM marcado
  WHERE DiasAtraso > 0
  GROUP BY 1, 2
  HAVING MAX(DiasAtraso) >= 90
),

resultado AS (
  SELECT
    e.*,
    c.groupCompanyName,
    c.companyName,
    c.subJudicie,
    -- voltou a ficar adimplente: o episodio terminou antes de hoje e
    -- NAO terminou por distrato
    (e.ultimo_dia < h.d
     AND NOT IFNULL(e.ultimo_dia >= DATE_SUB(c.cancellationDate, INTERVAL 1 DAY), FALSE)
    ) AS voltou
  FROM episodio e
  JOIN contrato c USING (ChaveGeral)
  CROSS JOIN hoje h
),

por_faixa AS (
  SELECT r.*, f.FaixaDe, f.Faixa, f.data_faixa
  FROM resultado r,
  UNNEST([
    STRUCT(90  AS FaixaDe, '090+ dias' AS Faixa, r.data_90  AS data_faixa),
    STRUCT(180, '180+ dias', r.data_180),
    STRUCT(365, '365+ dias', r.data_365),
    STRUCT(730, '730+ dias', r.data_730)
  ]) AS f
  WHERE f.data_faixa IS NOT NULL
)
SELECT
  p.groupCompanyName,
  p.companyName,
  p.subJudicie,
  EXTRACT(YEAR FROM p.data_90)                                   AS AnoInadimplencia,
  DATE_TRUNC(p.data_90, MONTH)                                   AS MesInadimplencia,
  p.FaixaDe,
  p.Faixa,
  COUNT(*)                                                       AS Episodios,
  COUNTIF(p.voltou)                                              AS VoltaramAdimplentes,
  COUNTIF(NOT p.voltou)                                          AS NaoVoltaram,
  -- media no Looker = SOMA(SomaDiasAteVoltar) / SOMA(VoltaramAdimplentes)
  SUM(IF(p.voltou, DATE_DIFF(p.ultimo_dia, p.data_faixa, DAY) + 1, 0)) AS SomaDiasAteVoltar
FROM por_faixa p
CROSS JOIN hoje h
WHERE p.data_faixa <= DATE_SUB(h.d, INTERVAL 180 DAY)   -- maturidade (ver cabecalho)
GROUP BY 1, 2, 3, 4, 5, 6, 7;


-- ####################################################################
-- CONTRATOS INADIMPLENTES HOJE: chance de voltar a ficar adimplente
-- ####################################################################
CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.inadimplencia_regularizacao_contratos`
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
    ANY_VALUE(costCenterName)        AS costCenterName,
    ANY_VALUE(clientName)            AS clientName,
    ANY_VALUE(Telefone)              AS Telefone,
    ANY_VALUE(subJudicie)            AS subJudicie,
    ANY_VALUE(SaldoDevedorComJuros)  AS SaldoEmAberto
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  WHERE documentIdentificationId = 'CT'
    AND cancellationDate IS NULL
    AND IFNULL(TRIM(groupCompanyName), '') <> ''
    AND NOT REGEXP_CONTAINS(
          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),
          r'BLOKO')
  GROUP BY 1
),

curva_grupo AS (
  SELECT groupCompanyName, FaixaDe,
         SUM(Episodios) AS ep, SUM(VoltaramAdimplentes) AS vol
  FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_regularizacao_curva`
  GROUP BY 1, 2
),

curva_geral AS (
  SELECT FaixaDe,
         SUM(Episodios) AS ep, SUM(VoltaramAdimplentes) AS vol
  FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_regularizacao_curva`
  GROUP BY 1
),

atual AS (
  SELECT
    CAST(h.ChaveGeral AS STRING) AS ChaveGeral,
    h.DiasAtraso,
    h.QtdParcelas
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h, hoje
  WHERE h.Data = hoje.d
    AND h.DiasAtraso >= 90
),

base AS (
  SELECT
    a.*,
    c.* EXCEPT (ChaveGeral),
    CASE WHEN a.DiasAtraso >= 730 THEN 730
         WHEN a.DiasAtraso >= 365 THEN 365
         WHEN a.DiasAtraso >= 180 THEN 180
         ELSE 90 END AS FaixaDe
  FROM atual a
  JOIN contrato c USING (ChaveGeral)
)

SELECT
  b.ChaveGeral,
  b.groupCompanyName,
  b.companyName,
  b.costCenterName,
  b.clientName,
  b.Telefone,
  b.subJudicie,
  b.DiasAtraso,
  CASE b.FaixaDe WHEN 90 THEN '090+ dias' WHEN 180 THEN '180+ dias'
                 WHEN 365 THEN '365+ dias' ELSE '730+ dias' END            AS Faixa,
  b.QtdParcelas                                                            AS ParcelasVencidas,
  ROUND(b.SaldoEmAberto, 2)                                                AS SaldoEmAberto,
  IF(IFNULL(cg.ep, 0) >= 30, 'Grupo', 'Geral')                             AS BaseDaTaxa,
  ROUND(IF(IFNULL(cg.ep, 0) >= 30, SAFE_DIVIDE(cg.vol, cg.ep),
                                   SAFE_DIVIDE(gg.vol, gg.ep)), 4)         AS ProbVoltarAdimplente,
  ROUND(b.SaldoEmAberto * IF(IFNULL(cg.ep, 0) >= 30, SAFE_DIVIDE(cg.vol, cg.ep),
                                   SAFE_DIVIDE(gg.vol, gg.ep)), 2)         AS SaldoRecuperavelEsperado,
  RANK() OVER (ORDER BY b.SaldoEmAberto * IF(IFNULL(cg.ep, 0) >= 30,
           SAFE_DIVIDE(cg.vol, cg.ep), SAFE_DIVIDE(gg.vol, gg.ep)) DESC)  AS Prioridade,
  h.d                                                                      AS DataReferencia
FROM base b
CROSS JOIN hoje h
LEFT JOIN curva_grupo cg
  ON cg.groupCompanyName = b.groupCompanyName AND cg.FaixaDe = b.FaixaDe
LEFT JOIN curva_geral gg
  ON gg.FaixaDe = b.FaixaDe;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- RESULTADO RAPIDO
-- ####################################################################

-- (1) depois de chegar a X dias de atraso: % que voltou a ficar adimplente
-- SELECT
--   Faixa,
--   SUM(Episodios)                                                        AS episodios,
--   ROUND(100 * SAFE_DIVIDE(SUM(VoltaramAdimplentes), SUM(Episodios)), 1) AS pct_voltaram_adimplentes,
--   ROUND(100 * SAFE_DIVIDE(SUM(NaoVoltaram), SUM(Episodios)), 1)         AS pct_nao_voltaram,
--   ROUND(SAFE_DIVIDE(SUM(SomaDiasAteVoltar), SUM(VoltaramAdimplentes)))  AS dias_medios_ate_voltar
-- FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_regularizacao_curva`
-- GROUP BY 1
-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (2) inadimplentes hoje: quanto do saldo ainda da para recuperar
-- SELECT
--   groupCompanyName,
--   Faixa,
--   COUNT(*)                               AS contratos,
--   ROUND(SUM(SaldoEmAberto))              AS saldo_em_aberto,
--   ROUND(SUM(SaldoRecuperavelEsperado))   AS saldo_recuperavel_esperado
-- FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_regularizacao_contratos`
-- GROUP BY 1, 2
-- ORDER BY 1, 2;