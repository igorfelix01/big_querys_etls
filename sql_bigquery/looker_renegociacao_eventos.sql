-- ####################################################################
-- LOOKER_STUDIO.RENEGOCIACAO_EVENTOS
-- 1 linha por RENEGOCIACAO (contrato x data do reparcelamento).
-- Cada renegociacao conta no PROPRIO mes: um contrato renegociado em
-- mar/2025 e em out/2026 aparece nos dois meses (1a e 2a renegociacao),
-- e o historico dos meses nao muda depois.
--
-- Fonte (igual ao BI): o extrato de reparcelamento
--   raw.reparcelamento_analise (EXTRATO_GERAL_Reparcelamento_Analise.csv)
--   renegociacao = linhas com receipt_type = 'Reparcelamento';
--   data = receipt_date; cada data distinta do contrato = 1 renegociacao.
-- Universo = os contratos da analytics.fato_reparcelamento_analise
--   (mesma regra da pagina: SEM os contratos da Cobranca 3P), com
--   companyGroup valido e sem Bloko Capital. Filtro CT fica no Looker.
--
-- Colunas principais:
--   NumeroRenegociacao      1a, 2a, 3a... do contrato (ordem das datas)
--   FaixaRenegociacao       legenda: Primeira / Segunda / Terceira ou
--                           Quarta / Quinta ou mais
--   QtdParcelasRenegociadas parcelas baixadas por reparcelamento na data
--   ValorRenegociado        valor dessas parcelas (receipt_value)
--   SituacaoNaRenegociacao  como o contrato estava NO DIA ANTERIOR
--                           (HistoricoInadimplencia): Adimplente (0 dias),
--                           Atrasado (1-89), Inadimplente (90+),
--                           Sem historico (sem linha naquele dia)
--   AtrasoNaRenegociacao    dias de atraso no dia anterior
--   SituacaoContrato        como o contrato esta HOJE (titulos totalizador)
--   EhUltimaRenegociacao    'Sim' na renegociacao mais recente do contrato
--   ConfirmadoNoSienge      'Sim' se o reparcelamento desta data tambem
--                           existe hoje no Sienge (fato_renegociacoes).
--                           'Nao' = provavelmente excluido depois que o
--                           extrato foi gerado (so filtro; nao tira nada)
-- SEM periodo no SQL (Looker: DataReparcelamento).
--
-- Depende de: raw.reparcelamento_analise, analytics.fato_reparcelamento_analise,
--             analytics.dim_nome_companhias, analytics.dim_perfomados,
--             analytics.fato_titulos_totalizador, analytics.HistoricoInadimplencia,
--             analytics.fato_renegociacoes
-- ####################################################################

CREATE TEMP FUNCTION para_data(v STRING) AS (
  COALESCE(
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(TRIM(v), 1, 10)),
    SAFE.PARSE_DATE('%d/%m/%Y', SUBSTR(TRIM(v), 1, 10)),
    IF(REGEXP_CONTAINS(TRIM(v), r'^\d{13}$'),
       DATE(TIMESTAMP_MILLIS(SAFE_CAST(TRIM(v) AS INT64))), NULL),
    IF(REGEXP_CONTAINS(TRIM(v), r'^\d{10}$'),
       DATE(TIMESTAMP_SECONDS(SAFE_CAST(TRIM(v) AS INT64))), NULL)
  )
);

CREATE TEMP FUNCTION para_num(v STRING) AS (
  SAFE_CAST(
    IF(STRPOS(TRIM(v), ',') > 0,
       REPLACE(REPLACE(TRIM(v), '.', ''), ',', '.'),
       TRIM(v)) AS FLOAT64)
);

-- renegociacoes do extrato: 1 por contrato x data
CREATE OR REPLACE TEMP TABLE eventos AS
SELECT
  REPLACE(CAST(chave AS STRING), '_', '-')                AS ChaveGeral,
  para_data(CAST(receipt_date AS STRING))                 AS DataReparcelamento,
  COUNT(*)                                                AS QtdParcelasRenegociadas,
  SUM(IFNULL(para_num(CAST(receipt_value AS STRING)), 0)) AS ValorRenegociado
FROM `dadosfinanceiro-501613.raw.reparcelamento_analise`
WHERE TRIM(CAST(receipt_type AS STRING)) = 'Reparcelamento'
  AND chave IS NOT NULL
  AND para_data(CAST(receipt_date AS STRING)) IS NOT NULL
GROUP BY 1, 2;


DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.renegociacao_eventos`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.renegociacao_eventos`
CLUSTER BY companyGroup, FaixaRenegociacao
AS
WITH
-- universo da pagina (sem Cobranca 3P) + dados do cliente
contrato AS (
  SELECT
    ChaveGeral,
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    NomeCliente,
    Unidade
  FROM `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise`
  WHERE ChaveGeral IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral
                             ORDER BY UltimaDataReparcelamento DESC) = 1
),
nome_companhias AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup, companyName, projectName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName) = 1
),
performados AS (
  SELECT SAFE_CAST(enterpriseId AS INT64) AS enterpriseId, StatusPerf
  FROM `dadosfinanceiro-501613.analytics.dim_perfomados`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64) ORDER BY StatusPerf) = 1
),
titulos AS (
  SELECT
    CAST(ChaveGeral AS STRING)          AS ChaveGeral,
    ANY_VALUE(SituacaoContrato)         AS SituacaoContrato,
    ANY_VALUE(documentIdentificationId) AS documentIdentificationId,
    ANY_VALUE(subJudicie)               AS subJudicie
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  GROUP BY 1
),
ev AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (PARTITION BY e.ChaveGeral ORDER BY e.DataReparcelamento) AS NumeroRenegociacao,
    COUNT(*)     OVER (PARTITION BY e.ChaveGeral)                               AS TotalRenegociacoes
  FROM eventos e
  JOIN contrato c USING (ChaveGeral)
),
-- situacao no dia anterior a renegociacao
historico AS (
  SELECT ev.ChaveGeral, ev.DataReparcelamento, h.DiasAtraso
  FROM ev
  JOIN `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h
    ON  CAST(h.ChaveGeral AS STRING) = ev.ChaveGeral
    AND h.Data = DATE_SUB(ev.DataReparcelamento, INTERVAL 1 DAY)
),
sienge AS (
  SELECT DISTINCT
    CAST(ChaveGeral AS STRING)     AS ChaveGeral,
    SAFE_CAST(paymentDate AS DATE) AS DataReneg
  FROM `dadosfinanceiro-501613.analytics.fato_renegociacoes`
  WHERE ChaveGeral IS NOT NULL
)
SELECT
  ev.ChaveGeral,
  ev.DataReparcelamento,
  DATE_TRUNC(ev.DataReparcelamento, MONTH)              AS MesReparcelamento,
  EXTRACT(YEAR FROM ev.DataReparcelamento)              AS Ano,
  ev.NumeroRenegociacao,
  CASE
    WHEN ev.NumeroRenegociacao = 1       THEN 'Primeira Renegociação'
    WHEN ev.NumeroRenegociacao = 2       THEN 'Segunda Renegociação'
    WHEN ev.NumeroRenegociacao IN (3, 4) THEN 'Terceira ou Quarta Renegociação'
    ELSE                                      'Quinta ou mais Renegociação'
  END                                                   AS FaixaRenegociacao,
  CASE
    WHEN ev.NumeroRenegociacao = 1       THEN 1
    WHEN ev.NumeroRenegociacao = 2       THEN 2
    WHEN ev.NumeroRenegociacao IN (3, 4) THEN 3
    ELSE                                      4
  END                                                   AS OrdemFaixa,
  ev.TotalRenegociacoes,
  IF(ev.NumeroRenegociacao = ev.TotalRenegociacoes, 'Sim', 'Não') AS EhUltimaRenegociacao,
  ev.QtdParcelasRenegociadas,
  ROUND(ev.ValorRenegociado, 2)                         AS ValorRenegociado,

  -- situacao no dia anterior a renegociacao
  h.DiasAtraso                                          AS AtrasoNaRenegociacao,
  CASE
    WHEN h.DiasAtraso IS NULL THEN 'Sem histórico'
    WHEN h.DiasAtraso = 0     THEN 'Adimplente'
    WHEN h.DiasAtraso < 90    THEN 'Atrasado'
    ELSE                           'Inadimplente'
  END                                                   AS SituacaoNaRenegociacao,
  -- situacao hoje
  t.SituacaoContrato,

  IF(s.ChaveGeral IS NOT NULL, 'Sim', 'Não')            AS ConfirmadoNoSienge,

  nc.companyGroup,
  nc.companyName,
  nc.projectName,
  p.StatusPerf,
  t.documentIdentificationId,
  t.subJudicie,
  c.enterpriseId,
  c.NomeCliente,
  c.Unidade,
  1                                                     AS Renegociacoes   -- no Looker: SOMA
FROM ev
JOIN contrato c          USING (ChaveGeral)
JOIN nome_companhias nc  ON nc.enterpriseId = c.enterpriseId
LEFT JOIN performados p  ON p.enterpriseId = c.enterpriseId
LEFT JOIN titulos t      ON t.ChaveGeral = ev.ChaveGeral
LEFT JOIN historico h
  ON h.ChaveGeral = ev.ChaveGeral AND h.DataReparcelamento = ev.DataReparcelamento
LEFT JOIN sienge s
  ON s.ChaveGeral = ev.ChaveGeral AND s.DataReneg = ev.DataReparcelamento
WHERE nc.companyGroup IS NOT NULL
  AND TRIM(nc.companyGroup) <> ''
  AND nc.companyGroup <> 'Bloko Capital';


-- ####################################################################
-- CONFERENCIA (rodar na mao)
-- ####################################################################
-- renegociacoes por mes, por numero e por situacao na data (CT)
-- SELECT MesReparcelamento, FaixaRenegociacao, SituacaoNaRenegociacao,
--        COUNT(*) AS renegociacoes, COUNT(DISTINCT ChaveGeral) AS contratos,
--        ROUND(SUM(ValorRenegociado)) AS valor_renegociado
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eventos`
-- WHERE documentIdentificationId = 'CT'
--   AND MesReparcelamento >= DATE '2025-01-01'
-- GROUP BY 1, 2, 3
-- ORDER BY 1, 2, 3;
--
-- renegociacoes do extrato que nao existem mais no Sienge
-- SELECT ChaveGeral, DataReparcelamento, NomeCliente
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eventos`
-- WHERE ConfirmadoNoSienge = 'Não'
-- ORDER BY DataReparcelamento DESC;
