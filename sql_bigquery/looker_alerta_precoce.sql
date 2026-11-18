-- [otimizacao] CTE 'contrato' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE contrato AS
  SELECT
    CAST(ChaveGeral AS STRING)  AS ChaveGeral,
    ANY_VALUE(groupCompanyName) AS groupCompanyName,
    ANY_VALUE(companyName)      AS companyName,
    ANY_VALUE(costCenterName)   AS costCenterName,
    ANY_VALUE(cancellationDate) AS cancellationDate
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  WHERE documentIdentificationId = 'CT'
    AND subJudicie = 'N'
    AND IFNULL(TRIM(groupCompanyName), '') <> ''
    AND NOT REGEXP_CONTAINS(
          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),
          r'BLOKO')
  GROUP BY 1;

-- [otimizacao] CTE 'pag_mes' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE pag_mes AS
WITH
pagamentos AS (
  SELECT DISTINCT
    CAST(r.ChaveGeral AS STRING)      AS ChaveGeral,
    CAST(r.ChaveEspecifica AS STRING) AS ChaveEspecifica,
    r.dueDate,
    r.paymentDate,
    r.ValorBruto
  FROM `dadosfinanceiro-501613.analytics.fato_recebidas` r
  JOIN contrato c
    ON c.ChaveGeral = CAST(r.ChaveGeral AS STRING)
  WHERE r.Conta = 'Efeito Caixa'
    AND r.paymentDate IS NOT NULL
    AND r.dueDate IS NOT NULL
    AND r.dueDate >= DATE '2000-01-01'
    AND r.paymentDate < IFNULL(c.cancellationDate, DATE '9999-12-31')
)
SELECT * FROM (

  SELECT
    ChaveGeral,
    DATE_TRUNC(paymentDate, MONTH)                            AS Mes,
    COUNT(*)                                                  AS n,
    SUM(GREATEST(DATE_DIFF(paymentDate, dueDate, DAY), 0))    AS soma_atraso,
    COUNTIF(DATE_DIFF(paymentDate, dueDate, DAY) > 5)         AS n_atrasados
  FROM pagamentos
  GROUP BY 1, 2

);

-- ####################################################################
-- ALERTA PRECOCE: CLIENTES EM DIA QUE ESTAO COMECANDO A PIORAR
--
-- Pergunta: quem ainda esta EM DIA, mas esta pagando cada vez mais
-- tarde? (esses costumam ser os proximos a atrasar)
--
-- Como: para cada contrato e cada mes, compara o comportamento de
-- pagamento dos ULTIMOS 3 MESES com os 12 MESES ANTERIORES:
--   atraso medio (dias entre vencimento e pagamento; antecipado = 0)
--   % de parcelas pagas com mais de 5 dias de atraso
-- e da um Sinal:
--   1. Piorando forte  atraso medio subiu 10+ dias, ou passou a pagar
--                      com atraso 50%+ das parcelas (antes < 20%)
--   2. Piorando        atraso medio subiu 3+ dias, ou % com atraso
--                      subiu 25+ pontos
--   3. Estavel
--   4. Melhorando      atraso medio caiu 3+ dias
--   5. Sem pagamento recente  nenhum pagamento nos ultimos 3 meses
--   6. Sem historico   menos de 3 pagamentos nos 12 meses anteriores
--
-- VALIDACAO (o sinal funciona?): para todos os meses do passado,
-- pega os contratos que estavam EM DIA no dia 1 e ve se atrasaram
-- 30+ dias (ou distrataram) nos 3 meses seguintes. Se "Piorando"
-- atrasa muito mais que "Estavel", o sinal preve atraso.
--
-- Cria 3 tabelas:
--   analytics.alerta_precoce_base           contrato x mes (sinal + resultado)
--   looker_studio.alerta_precoce_validacao  sinal x mes -> contratos, quantos
--                                           atrasaram 30+ dias em 3 meses
--                                           (Looker: SOMA(Atrasaram)/SOMA(Contratos))
--   looker_studio.alerta_precoce_contratos  contratos EM DIA hoje, com sinal,
--                                           chance de atrasar e prioridade
--
-- Universo: CT, sem sub judice, sem empresas Bloko, pagamentos da
-- Conta 'Efeito Caixa'. Historico cortado na data do distrato.
-- "Hoje" = ultimo dia do analytics.HistoricoInadimplencia.
-- Sem periodo fixo: o periodo e filtrado no Looker (MesReferencia).
--
-- Depende de: analytics.fato_recebidas, analytics.HistoricoInadimplencia,
--             analytics.fato_titulos_totalizador
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.analytics.alerta_precoce_base`
CLUSTER BY groupCompanyName, MesReferencia
AS
WITH
hoje AS (
  SELECT
    MAX(Data)                    AS d,
    DATE_TRUNC(MAX(Data), MONTH) AS mes_atual
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`
),

grade AS (
  SELECT l.ChaveGeral, m AS Mes
  FROM (SELECT ChaveGeral, MIN(Mes) AS primeiro FROM pag_mes GROUP BY 1) l
  CROSS JOIN hoje h,
  UNNEST(GENERATE_DATE_ARRAY(l.primeiro, h.mes_atual, INTERVAL 1 MONTH)) AS m
),

serie AS (
  SELECT
    g.ChaveGeral,
    g.Mes,
    IFNULL(p.n, 0)           AS n,
    IFNULL(p.soma_atraso, 0) AS soma_atraso,
    IFNULL(p.n_atrasados, 0) AS n_atrasados
  FROM grade g
  LEFT JOIN pag_mes p USING (ChaveGeral, Mes)
),

janelas AS (
  SELECT
    ChaveGeral,
    Mes AS MesReferencia,
    IFNULL(SUM(n)           OVER w_rec, 0) AS n_rec,
    IFNULL(SUM(soma_atraso) OVER w_rec, 0) AS soma_rec,
    IFNULL(SUM(n_atrasados) OVER w_rec, 0) AS atras_rec,
    IFNULL(SUM(n)           OVER w_ant, 0) AS n_ant,
    IFNULL(SUM(soma_atraso) OVER w_ant, 0) AS soma_ant,
    IFNULL(SUM(n_atrasados) OVER w_ant, 0) AS atras_ant
  FROM serie
  WINDOW
    w_rec AS (PARTITION BY ChaveGeral ORDER BY Mes ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING),
    w_ant AS (PARTITION BY ChaveGeral ORDER BY Mes ROWS BETWEEN 15 PRECEDING AND 4 PRECEDING)
),

medidas AS (
  SELECT
    *,
    SAFE_DIVIDE(soma_rec, n_rec)  AS atraso_rec,
    SAFE_DIVIDE(soma_ant, n_ant)  AS atraso_ant,
    SAFE_DIVIDE(atras_rec, n_rec) AS pct_rec,
    SAFE_DIVIDE(atras_ant, n_ant) AS pct_ant
  FROM janelas
),

hist_mes AS (
  SELECT
    CAST(h.ChaveGeral AS STRING)                              AS ChaveGeral,
    DATE_TRUNC(h.Data, MONTH)                                 AS Mes,
    MAX(h.DiasAtraso)                                         AS max_atraso,
    MAX(IF(EXTRACT(DAY FROM h.Data) = 1, h.DiasAtraso, NULL)) AS atraso_dia1
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h
  JOIN contrato c
    ON c.ChaveGeral = CAST(h.ChaveGeral AS STRING)
  WHERE h.Data < IFNULL(c.cancellationDate, DATE '9999-12-31')
  GROUP BY 1, 2
),

resultado AS (
  SELECT
    ChaveGeral,
    Mes,
    atraso_dia1,
    -- maior atraso no mes e nos 2 seguintes (~90 dias)
    MAX(max_atraso) OVER (
      PARTITION BY ChaveGeral
      ORDER BY DATE_DIFF(Mes, DATE '2000-01-01', MONTH)
      RANGE BETWEEN CURRENT ROW AND 2 FOLLOWING) AS max_atraso_3m
  FROM hist_mes
)
SELECT
  m.ChaveGeral,
  m.MesReferencia,
  EXTRACT(YEAR FROM m.MesReferencia)                      AS Ano,
  c.groupCompanyName,
  c.companyName,
  c.costCenterName,

  m.n_rec                                                 AS PagamentosRecentes,
  m.n_ant                                                 AS PagamentosAnteriores,
  ROUND(m.atraso_rec, 1)                                  AS AtrasoMedioRecente,
  ROUND(m.atraso_ant, 1)                                  AS AtrasoMedioAnterior,
  ROUND(m.pct_rec, 3)                                     AS PctAtrasadasRecente,
  ROUND(m.pct_ant, 3)                                     AS PctAtrasadasAnterior,

  CASE
    WHEN m.n_ant < 3                                       THEN '6. Sem histórico'
    WHEN m.n_rec = 0                                       THEN '5. Sem pagamento recente'
    WHEN m.atraso_rec >= m.atraso_ant + 10
      OR (m.pct_rec >= 0.5 AND m.pct_ant < 0.2)            THEN '1. Piorando forte'
    WHEN m.atraso_rec >= m.atraso_ant + 3
      OR m.pct_rec >= m.pct_ant + 0.25                     THEN '2. Piorando'
    WHEN m.atraso_rec <= m.atraso_ant - 3                  THEN '4. Melhorando'
    ELSE                                                        '3. Estável'
  END                                                     AS Sinal,

  r.atraso_dia1                                           AS DiasAtrasoDia1,
  IFNULL(r.atraso_dia1 = 0, FALSE)                        AS EmDiaNoDia1,

  -- resultado nos 3 meses seguintes
  m.MesReferencia <= DATE_SUB(h.mes_atual, INTERVAL 3 MONTH) AS JanelaCompleta,
  IFNULL(r.max_atraso_3m >= 30, FALSE)
    OR IFNULL(c.cancellationDate BETWEEN m.MesReferencia
                AND DATE_ADD(m.MesReferencia, INTERVAL 3 MONTH), FALSE) AS Atrasou30Em3Meses

FROM medidas m
JOIN contrato c USING (ChaveGeral)
CROSS JOIN hoje h
LEFT JOIN resultado r
  ON r.ChaveGeral = m.ChaveGeral AND r.Mes = m.MesReferencia;


-- ####################################################################
-- VALIDACAO: o sinal preve atraso?
-- ####################################################################
CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.alerta_precoce_validacao`
CLUSTER BY groupCompanyName
AS
SELECT
  groupCompanyName,
  companyName,
  MesReferencia,
  Ano,
  Sinal,
  COUNT(*)                          AS Contratos,
  COUNTIF(Atrasou30Em3Meses)        AS Atrasaram,
  COUNTIF(NOT Atrasou30Em3Meses)    AS SeguiramEmDia
FROM `dadosfinanceiro-501613.analytics.alerta_precoce_base`
WHERE EmDiaNoDia1
  AND JanelaCompleta
GROUP BY 1, 2, 3, 4, 5;


-- ####################################################################
-- CONTRATOS EM DIA HOJE, com sinal e chance de atrasar
-- ####################################################################
CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.alerta_precoce_contratos`
CLUSTER BY groupCompanyName
AS

WITH

hoje AS (
  SELECT MAX(Data) AS d, DATE_TRUNC(MAX(Data), MONTH) AS mes_atual
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`
),

titulo AS (
  SELECT
    CAST(ChaveGeral AS STRING)       AS ChaveGeral,
    ANY_VALUE(clientName)            AS clientName,
    ANY_VALUE(Telefone)              AS Telefone,
    ANY_VALUE(Email)                 AS Email,
    ANY_VALUE(SaldoDevedorComJuros)  AS SaldoEmAberto,
    ANY_VALUE(cancellationDate)      AS cancellationDate
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  GROUP BY 1
),

em_dia_hoje AS (
  SELECT CAST(h.ChaveGeral AS STRING) AS ChaveGeral
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h, hoje
  WHERE h.Data = hoje.d
    AND h.DiasAtraso = 0
),

taxa_grupo AS (
  SELECT groupCompanyName, Sinal,
         SUM(Contratos) AS ct, SUM(Atrasaram) AS atr
  FROM `dadosfinanceiro-501613.looker_studio.alerta_precoce_validacao`
  GROUP BY 1, 2
),

taxa_geral AS (
  SELECT Sinal, SUM(Contratos) AS ct, SUM(Atrasaram) AS atr
  FROM `dadosfinanceiro-501613.looker_studio.alerta_precoce_validacao`
  GROUP BY 1
),

base AS (
  SELECT
    b.*,
    t.clientName,
    t.Telefone,
    t.Email,
    IFNULL(t.SaldoEmAberto, 0)                          AS SaldoEmAberto,
    IF(IFNULL(tg.ct, 0) >= 30,
       SAFE_DIVIDE(tg.atr, tg.ct),
       SAFE_DIVIDE(tt.atr, tt.ct))                      AS prob,
    IF(IFNULL(tg.ct, 0) >= 30, 'Grupo', 'Geral')        AS BaseDaTaxa
  FROM `dadosfinanceiro-501613.analytics.alerta_precoce_base` b
  CROSS JOIN hoje h
  JOIN em_dia_hoje e USING (ChaveGeral)
  JOIN titulo t USING (ChaveGeral)
  LEFT JOIN taxa_grupo tg
    ON tg.groupCompanyName = b.groupCompanyName AND tg.Sinal = b.Sinal
  LEFT JOIN taxa_geral tt
    ON tt.Sinal = b.Sinal
  WHERE b.MesReferencia = h.mes_atual
    AND t.cancellationDate IS NULL
    AND IFNULL(t.SaldoEmAberto, 0) > 0
)

SELECT
  ChaveGeral,
  groupCompanyName,
  companyName,
  costCenterName,
  clientName,
  Telefone,
  Email,
  Sinal,
  PagamentosRecentes,
  AtrasoMedioRecente,
  AtrasoMedioAnterior,
  PctAtrasadasRecente,
  PctAtrasadasAnterior,
  ROUND(SaldoEmAberto, 2)                              AS SaldoEmAberto,
  BaseDaTaxa,
  ROUND(prob, 4)                                       AS ProbAtrasar30Dias,
  ROUND(prob * SaldoEmAberto, 2)                       AS SaldoSobAlerta,
  RANK() OVER (ORDER BY prob * SaldoEmAberto DESC)     AS Prioridade,
  MesReferencia                                        AS DataReferencia
FROM base;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- RESULTADO RAPIDO
-- ####################################################################

-- (1) o sinal funciona? % que atrasou 30+ dias nos 3 meses seguintes
-- SELECT
--   Sinal,
--   SUM(Contratos)                                               AS contratos_mes,
--   ROUND(100 * SAFE_DIVIDE(SUM(Atrasaram), SUM(Contratos)), 1)  AS pct_atrasaram
-- FROM `dadosfinanceiro-501613.looker_studio.alerta_precoce_validacao`
-- GROUP BY 1
-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (2) quantos clientes em dia estao piorando hoje, por grupo
-- SELECT
--   groupCompanyName,
--   Sinal,
--   COUNT(*)                     AS contratos,
--   ROUND(SUM(SaldoEmAberto))    AS saldo_em_aberto,
--   ROUND(SUM(SaldoSobAlerta))   AS saldo_sob_alerta
-- FROM `dadosfinanceiro-501613.looker_studio.alerta_precoce_contratos`
-- GROUP BY 1, 2
-- ORDER BY 1, 2;