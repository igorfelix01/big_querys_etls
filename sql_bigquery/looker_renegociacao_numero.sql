-- ####################################################################

-- LOOKER_STUDIO.RENEGOCIACAO_NUMERO

-- Pagina Renegociacao - grafico por mes:

--   "Primeira / Segunda / Terceira ou Quarta / Quinta ou mais Renegociacao"

--

-- MESMOS CONTRATOS E MESMO MES do grafico "Contratos Renegociados -

-- Situacao" (looker_studio.renegociacao_base = Reparcelamento_Analise):

--   1 linha por contrato (ChaveGeral), no mes da ULTIMA renegociacao

--   (DataReparcelamento). Assim o total de cada mes e IGUAL nos dois

--   graficos.

--

-- A cor = quantas vezes o contrato ja foi renegociado ate essa data:

--   conta as datas de Reparcelamento (CT) do contrato nas recebidas

--   (analytics.fato_renegociacoes) ate a DataReparcelamento.

--   Se o contrato nao tem nenhuma nas recebidas (ex.: renegociado antes

--   do 1o pagamento), conta como 1 (Primeira).

--     1     -> Primeira Renegociacao

--     2     -> Segunda Renegociacao

--     3 e 4 -> Terceira ou Quarta Renegociacao

--     5+    -> Quinta ou mais Renegociacao

--

-- Filtros/colunas iguais aos da renegociacao_base (companyGroup sem Bloko,

-- Cobranca 3P fora, StatusPerf, documentIdentificationId para o CT).

-- SEM periodo no SQL (Looker: DataReparcelamento).

--

-- Depende de: looker_studio.renegociacao_base, analytics.fato_renegociacoes

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.renegociacao_numero`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.renegociacao_numero`

CLUSTER BY companyGroup, FaixaRenegociacao

AS



WITH



-- datas de renegociacao (Reparcelamento CT) de cada contrato nas recebidas

datas_reneg AS (

  SELECT DISTINCT

    ChaveGeral,

    SAFE_CAST(paymentDate AS DATE) AS DataReneg

  FROM `dadosfinanceiro-501613.analytics.fato_renegociacoes`

  WHERE paymentDate IS NOT NULL

),



-- quantas datas de renegociacao o contrato tem ate a DataReparcelamento

contagem AS (

  SELECT

    b.ChaveGeral,

    COUNT(d.DataReneg) AS qtd

  FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base` b

  LEFT JOIN datas_reneg d

    ON  d.ChaveGeral = b.ChaveGeral

    AND d.DataReneg <= b.DataReparcelamento

  GROUP BY b.ChaveGeral

),



base AS (

  SELECT

    b.ChaveGeral,

    b.DataReparcelamento,

    b.MesReparcelamento,

    b.Ano,

    b.companyGroup,

    b.companyName,

    b.projectName,

    b.StatusPerf,

    b.SituacaoContrato,

    b.documentIdentificationId,

    b.NomeCliente,

    b.enterpriseId,

    GREATEST(1, IFNULL(c.qtd, 0)) AS NumeroRenegociacao   -- minimo 1

  FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base` b

  LEFT JOIN contagem c

    ON c.ChaveGeral = b.ChaveGeral

)



SELECT

  ChaveGeral,

  DataReparcelamento,

  MesReparcelamento,                               -- eixo X

  Ano,

  NumeroRenegociacao,

  CASE

    WHEN NumeroRenegociacao = 1       THEN 'Primeira Renegociação'

    WHEN NumeroRenegociacao = 2       THEN 'Segunda Renegociação'

    WHEN NumeroRenegociacao IN (3, 4) THEN 'Terceira ou Quarta Renegociação'

    ELSE                                   'Quinta ou mais Renegociação'

  END                                            AS FaixaRenegociacao,  -- legenda

  CASE

    WHEN NumeroRenegociacao = 1       THEN 1

    WHEN NumeroRenegociacao = 2       THEN 2

    WHEN NumeroRenegociacao IN (3, 4) THEN 3

    ELSE                                   4

  END                                            AS OrdemFaixa,         -- ordem da legenda

  companyGroup,

  companyName,

  projectName,

  StatusPerf,

  SituacaoContrato,

  documentIdentificationId,

  NomeCliente,

  enterpriseId,

  1                                              AS Contratos           -- no Looker: SOMA

FROM base;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO: total por mes tem que ser IGUAL ao grafico de Situacao

-- (looker_studio.renegociacao_base) - coluna diferenca = 0 em todos

-- ####################################################################

-- WITH n AS (

--   SELECT MesReparcelamento AS mes,

--          SUM(Contratos) AS total_numero,

--          SUM(IF(OrdemFaixa = 1, Contratos, 0)) AS primeira,

--          SUM(IF(OrdemFaixa = 2, Contratos, 0)) AS segunda,

--          SUM(IF(OrdemFaixa = 3, Contratos, 0)) AS terceira_ou_quarta,

--          SUM(IF(OrdemFaixa = 4, Contratos, 0)) AS quinta_ou_mais

--   FROM `dadosfinanceiro-501613.looker_studio.renegociacao_numero`

--   WHERE documentIdentificationId = 'CT'

--   GROUP BY 1

-- ),

-- s AS (

--   SELECT MesReparcelamento AS mes, SUM(Contratos) AS total_situacao

--   FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base`

--   WHERE documentIdentificationId = 'CT'

--   GROUP BY 1

-- )

-- SELECT n.mes, s.total_situacao, n.total_numero,

--        n.total_numero - s.total_situacao AS diferenca,

--        n.primeira, n.segunda, n.terceira_ou_quarta, n.quinta_ou_mais

-- FROM n JOIN s USING (mes)

-- WHERE n.mes >= DATE '2025-05-01'

-- ORDER BY n.mes;