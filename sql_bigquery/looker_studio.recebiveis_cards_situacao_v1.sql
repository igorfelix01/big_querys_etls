-- ####################################################################
-- LOOKER_STUDIO.RECEBIVEIS_CARDS_SITUACAO_V1
--
-- Mantem as MESMAS colunas da versao original (o painel do Looker usa
-- MediaRecebimentoMes, MediaContratos, MaxRecebimentoMes,
-- MinRecebimentoMes por DiaParametro x SituacaoParcelaVisual), mas com a
-- logica da DAX [RecebiveisMesPassado]:
--
--   - Mes pelo paymentYear/paymentMonth (DAX), nao pelo MesReferencia
--   - Acumulado ate o dia: NumeroDiaDaSemana <= DiaParametro (MaxWorkday)
--   - Filtros equivalentes aos filtros do painel do BI que o ALLEXCEPT
--     mantem: documentIdentificationId = 'CT', ContasBancarias =
--     'Efeito Caixa', NomeCompanhias sem 'Bloko Capital'
--
-- Correcoes que continuam:
--   - Fim do periodo = ultimo mes fechado (dinamico); inicio 2025-05-01
--   - Meses sem valor numa situacao entram como 0 (media/min corretos)
--   - 'Sem grupo' entra (BI inclui "(Em branco)")
--
-- Colunas novas (nao quebram o painel):
--   RecebiveisMesPassado, RecebiveisMesAtual  (por situacao; podem somar)
--   QtdMeses
--   MinRecebimentoMesTotal / MaxRecebimentoMesTotal / MediaRecebimentoMesTotal
--     (do total mensal, repetidos em cada linha -> agregacao MAX no Looker)
-- ####################################################################


DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.recebiveis_cards_situacao_v1`;


CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.recebiveis_cards_situacao_v1`

CLUSTER BY
  DiaParametro,
  SituacaoParcelaVisual

AS

WITH

periodo AS (
  SELECT
    DATE '2025-05-01'                                    AS inicio,
    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual,
    DATE_SUB(
      DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH),
      INTERVAL 1 MONTH
    )                                                    AS mes_passado
),

parametros AS (
  SELECT dia AS DiaParametro
  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS dia
),

-- meses fechados usados em media / min / max
meses AS (
  SELECT mes AS MesPagamento
  FROM periodo,
  UNNEST(GENERATE_DATE_ARRAY(periodo.inicio, periodo.mes_passado, INTERVAL 1 MONTH)) AS mes
),

situacoes AS (
  SELECT situacao AS SituacaoParcelaVisual
  FROM UNNEST([
    'Adimplente',
    'Atrasado',
    'Inadimplente',
    'Antecipado',
    'Quitação',
    'Venda à vista',
    'Ato'
  ]) AS situacao
),

base_filtrada AS (
  SELECT
    DATE(rsp.paymentYear, rsp.paymentMonth, 1) AS MesPagamento,
    rsp.SituacaoParcelaVisual,
    rsp.NumeroDiaDaSemana,
    rsp.ValorBruto_EfeitoCaixa,
    rsp.ChaveGeral
  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` rsp
  CROSS JOIN periodo p
  WHERE rsp.paymentYear IS NOT NULL
    AND rsp.paymentMonth IS NOT NULL
    AND DATE(rsp.paymentYear, rsp.paymentMonth, 1) BETWEEN p.inicio AND p.mes_atual
    AND rsp.documentIdentificationId = 'CT'
    AND rsp.Conta = 'Efeito Caixa'
    AND rsp.companyGroup IS NOT NULL
    AND TRIM(rsp.companyGroup) <> ''
    AND rsp.companyGroup <> 'Bloko Capital'
    AND rsp.SituacaoParcelaVisual IN (
      'Adimplente',
      'Atrasado',
      'Inadimplente',
      'Antecipado',
      'Quitação',
      'Venda à vista',
      'Ato'
    )
),

-- grade dia x mes fechado x situacao (garante os zeros)
grade AS (
  SELECT
    p.DiaParametro,
    m.MesPagamento,
    s.SituacaoParcelaVisual
  FROM parametros p
  CROSS JOIN meses m
  CROSS JOIN situacoes s
),

base_por_dia AS (
  SELECT
    g.DiaParametro,
    g.MesPagamento,
    g.SituacaoParcelaVisual,

    IFNULL(SUM(
      CASE
        WHEN bf.NumeroDiaDaSemana <= g.DiaParametro
        THEN bf.ValorBruto_EfeitoCaixa
        ELSE 0
      END
    ), 0) AS TotalMesSituacao,

    COUNT(DISTINCT
      CASE
        WHEN bf.NumeroDiaDaSemana <= g.DiaParametro
        THEN bf.ChaveGeral
      END
    ) AS ContratosSituacao

  FROM grade g
  LEFT JOIN base_filtrada bf
    ON  bf.MesPagamento          = g.MesPagamento
    AND bf.SituacaoParcelaVisual = g.SituacaoParcelaVisual

  GROUP BY
    g.DiaParametro,
    g.MesPagamento,
    g.SituacaoParcelaVisual
),

estatisticas AS (
  SELECT
    DiaParametro,
    SituacaoParcelaVisual,

    ROUND(AVG(TotalMesSituacao), 2)  AS MediaRecebimentoMes,
    ROUND(AVG(ContratosSituacao), 2) AS MediaContratos,
    ROUND(MAX(TotalMesSituacao), 2)  AS MaxRecebimentoMes,
    ROUND(MIN(TotalMesSituacao), 2)  AS MinRecebimentoMes,
    COUNT(*)                         AS QtdMeses

  FROM base_por_dia
  GROUP BY
    DiaParametro,
    SituacaoParcelaVisual
),

-- min / max do TOTAL mensal (todas as situacoes somadas)
-- repetido em todas as linhas do dia -> usar agregacao MAX no Looker
totais_mes AS (
  SELECT
    DiaParametro,
    MesPagamento,
    SUM(TotalMesSituacao) AS TotalMes
  FROM base_por_dia
  GROUP BY
    DiaParametro,
    MesPagamento
),

estatisticas_total AS (
  SELECT
    DiaParametro,
    ROUND(MIN(TotalMes), 2) AS MinRecebimentoMesTotal,
    ROUND(MAX(TotalMes), 2) AS MaxRecebimentoMesTotal,
    ROUND(AVG(TotalMes), 2) AS MediaRecebimentoMesTotal
  FROM totais_mes
  GROUP BY
    DiaParametro
),

-- RecebiveisMesPassado / MesAtual (DAX) por dia e situacao
mes_passado_atual AS (
  SELECT
    p.DiaParametro,
    bf.SituacaoParcelaVisual,

    ROUND(SUM(
      CASE
        WHEN bf.MesPagamento = pr.mes_passado
         AND bf.NumeroDiaDaSemana <= p.DiaParametro
        THEN bf.ValorBruto_EfeitoCaixa
        ELSE 0
      END
    ), 2) AS RecebiveisMesPassado,

    ROUND(SUM(
      CASE
        WHEN bf.MesPagamento = pr.mes_atual
         AND bf.NumeroDiaDaSemana <= p.DiaParametro
        THEN bf.ValorBruto_EfeitoCaixa
        ELSE 0
      END
    ), 2) AS RecebiveisMesAtual

  FROM parametros p
  CROSS JOIN base_filtrada bf
  CROSS JOIN periodo pr
  GROUP BY
    p.DiaParametro,
    bf.SituacaoParcelaVisual
)

SELECT
  e.DiaParametro,
  e.SituacaoParcelaVisual,

  e.MediaRecebimentoMes,
  e.MediaContratos,
  e.MaxRecebimentoMes,
  e.MinRecebimentoMes,

  IFNULL(m.RecebiveisMesPassado, 0) AS RecebiveisMesPassado,
  IFNULL(m.RecebiveisMesAtual, 0)   AS RecebiveisMesAtual,
  e.QtdMeses,

  -- totais do mes (todas as situacoes): usar agregacao MAX no Looker
  t.MinRecebimentoMesTotal,
  t.MaxRecebimentoMesTotal,
  t.MediaRecebimentoMesTotal

FROM estatisticas e
LEFT JOIN mes_passado_atual m
  ON  m.DiaParametro          = e.DiaParametro
  AND m.SituacaoParcelaVisual = e.SituacaoParcelaVisual
LEFT JOIN estatisticas_total t
  ON  t.DiaParametro          = e.DiaParametro;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- VALIDACAO (dia 31 = mes inteiro)
-- soma das situacoes: Media e MesPassado podem somar; Min/Max NAO
-- ####################################################################

-- SELECT
--   DiaParametro,
--   SUM(MediaRecebimentoMes)      AS media_total,
--   SUM(RecebiveisMesPassado)     AS mes_passado_total,
--   SUM(RecebiveisMesAtual)       AS mes_atual_total,
--   MAX(MinRecebimentoMesTotal)   AS minimo_total,
--   MAX(MaxRecebimentoMesTotal)   AS maximo_total,
--   MAX(MediaRecebimentoMesTotal) AS media_total_conferencia,
--   MAX(QtdMeses)                 AS qtd_meses
-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_situacao_v1`
-- WHERE DiaParametro IN (10, 20, 31)
-- GROUP BY DiaParametro
-- ORDER BY DiaParametro;