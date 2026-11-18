DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.recebiveis_cards_gauge_v4`;-- [otimizacao] CTE 'base_filtrada' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base_filtrada AS
  SELECT

    rsp.*

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` rsp

  WHERE rsp.MesReferencia BETWEEN DATE '2025-05-01' AND DATE '2026-07-01'

    AND rsp.documentIdentificationId = 'CT'

    AND rsp.companyGroup IS NOT NULL

    AND TRIM(rsp.companyGroup) <> ''

    AND rsp.companyGroup <> 'Bloko Capital';





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.looker_studio.recebiveis_cards_gauge_v4`

CLUSTER BY DiaParametro

AS
WITH
parametros AS (

  SELECT

    dia AS DiaParametro,

    DATE '2026-07-28' AS DataReferenciaBI,

    DATE_TRUNC(DATE '2026-07-28', MONTH) AS MesAtual,

    DATE_TRUNC(DATE_SUB(DATE '2026-07-28', INTERVAL 1 MONTH), MONTH) AS MesPassado

  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS dia

),

base_por_dia AS (

  SELECT

    p.DiaParametro,

    bf.MesReferencia,

    bf.SituacaoParcelaVisual,

    bf.ChaveGeral,



    SUM(

      CASE

        WHEN bf.NumeroDiaDaSemana <= p.DiaParametro

        THEN bf.ValorBruto_EfeitoCaixa

        ELSE 0

      END

    ) AS ValorRecebidoDia



  FROM parametros p

  CROSS JOIN base_filtrada bf

  GROUP BY

    p.DiaParametro,

    bf.MesReferencia,

    bf.SituacaoParcelaVisual,

    bf.ChaveGeral

),

mensal_por_dia AS (

  SELECT

    DiaParametro,

    MesReferencia,



    SUM(ValorRecebidoDia) AS TotalMes,



    SUM(

      CASE

        WHEN SituacaoParcelaVisual = 'Adimplente'

        THEN ValorRecebidoDia

        ELSE 0

      END

    ) AS TotalAdimplente,



    SUM(

      CASE

        WHEN SituacaoParcelaVisual = 'Atrasado'

        THEN ValorRecebidoDia

        ELSE 0

      END

    ) AS TotalAtrasado,



    SUM(

      CASE

        WHEN SituacaoParcelaVisual = 'Inadimplente'

        THEN ValorRecebidoDia

        ELSE 0

      END

    ) AS TotalInadimplente,



    COUNT(DISTINCT ChaveGeral) AS Contratos



  FROM base_por_dia

  GROUP BY

    DiaParametro,

    MesReferencia

),

metricas_por_dia AS (

  SELECT

    DiaParametro,



    MAX(TotalMes) AS MaxRevenue,

    AVG(TotalMes) AS MediaRecebidoMes,

    MIN(TotalMes) AS MinRevenue,



    AVG(TotalAdimplente) AS MediaAdimplente,

    AVG(TotalAtrasado) AS MediaAtrasado,

    AVG(TotalInadimplente) AS MediaInadimplente,



    AVG(Contratos) AS MediaContratos



  FROM mensal_por_dia

  GROUP BY

    DiaParametro

),

recebiveis_mes_atual AS (

  SELECT

    p.DiaParametro,



    SUM(

      CASE

        WHEN bf.NumeroDiaDaSemana <= p.DiaParametro

        THEN bf.ValorBruto_EfeitoCaixa

        ELSE 0

      END

    ) AS RecebiveisMesAtual



  FROM parametros p

  LEFT JOIN base_filtrada bf

    ON bf.MesReferencia = p.MesAtual

  GROUP BY

    p.DiaParametro

),

recebiveis_mes_passado AS (

  SELECT

    p.DiaParametro,



    SUM(

      CASE

        WHEN bf.NumeroDiaDaSemana <= p.DiaParametro

        THEN bf.ValorBruto_EfeitoCaixa

        ELSE 0

      END

    ) AS RecebiveisMesPassado



  FROM parametros p

  LEFT JOIN base_filtrada bf

    ON bf.MesReferencia = p.MesPassado

  GROUP BY

    p.DiaParametro

)
SELECT

  m.DiaParametro,



  ROUND(a.RecebiveisMesAtual, 2) AS RecebiveisMesAtual,

  ROUND(r.RecebiveisMesPassado, 2) AS RecebiveisMesPassado,



  ROUND(m.MinRevenue, 2) AS MinRevenue,

  ROUND(m.MediaRecebidoMes, 2) AS MediaRecebidoMes,

  ROUND(m.MaxRevenue, 2) AS MaxRevenue,



  ROUND(m.MediaAdimplente, 2) AS MediaAdimplente,

  ROUND(m.MediaAtrasado, 2) AS MediaAtrasado,

  ROUND(m.MediaInadimplente, 2) AS MediaInadimplente,



  ROUND(m.MediaContratos, 2) AS MediaContratos



FROM metricas_por_dia m

LEFT JOIN recebiveis_mes_atual a

  ON m.DiaParametro = a.DiaParametro

LEFT JOIN recebiveis_mes_passado r

  ON m.DiaParametro = r.DiaParametro;