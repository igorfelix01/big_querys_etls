CREATE OR REPLACE TABLE `dadosfinanceiro-501613.looker_studio.recebiveis_cards_gauge_v2`
AS
WITH parametros_dias AS (
  SELECT dia AS DiaParametro
  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS dia
),

base AS (
  SELECT
    MesReferencia,
    SituacaoParcelaVisual,
    ChaveGeral,
    ChaveEspecifica,

    SAFE_CAST(NumeroDiaDaSemana AS INT64) AS NumeroDiaDaSemana,

    documentIdentificationId,
    companyGroup,
    subJudicie,
    anoPeriodoVenda,
    Conta,

    ValorBruto_EfeitoCaixa,
    ValorBloko_EfeitoCaixa,
    ValorParceiro_EfeitoCaixa

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`
  WHERE MesReferencia BETWEEN DATE '2025-05-01' AND DATE '2026-07-01'
    AND documentIdentificationId = 'CT'
    AND companyGroup IS NOT NULL
    AND TRIM(companyGroup) <> ''
    AND companyGroup <> 'Bloko Capital'
),

mensal_total AS (
  SELECT
    p.DiaParametro,
    b.MesReferencia,

    SUM(
      CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
        THEN b.ValorBruto_EfeitoCaixa
        ELSE 0
      END
    ) AS ValorBruto_Mes,

    SUM(
      CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
        THEN b.ValorBloko_EfeitoCaixa
        ELSE 0
      END
    ) AS ValorBloko_Mes,

    SUM(
      CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
        THEN b.ValorParceiro_EfeitoCaixa
        ELSE 0
      END
    ) AS ValorParceiro_Mes

  FROM parametros_dias p
  CROSS JOIN base b
  GROUP BY
    p.DiaParametro,
    b.MesReferencia
),

mensal_situacao AS (
  SELECT
    p.DiaParametro,
    b.MesReferencia,
    b.SituacaoParcelaVisual,

    SUM(
      CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
        THEN b.ValorBruto_EfeitoCaixa
        ELSE 0
      END
    ) AS ValorBruto_Mes,

    SUM(
      CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
        THEN b.ValorBloko_EfeitoCaixa
        ELSE 0
      END
    ) AS ValorBloko_Mes,

    SUM(
      CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
        THEN b.ValorParceiro_EfeitoCaixa
        ELSE 0
      END
    ) AS ValorParceiro_Mes

  FROM parametros_dias p
  CROSS JOIN base b
  WHERE b.SituacaoParcelaVisual IN (
    'Adimplente',
    'Atrasado',
    'Inadimplente'
  )
  GROUP BY
    p.DiaParametro,
    b.MesReferencia,
    b.SituacaoParcelaVisual
),

mensal_contratos AS (
  SELECT
    p.DiaParametro,
    b.MesReferencia,

    COUNT(
      DISTINCT CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
          AND b.Conta = 'Efeito Caixa'
        THEN b.ChaveGeral
        ELSE NULL
      END
    ) AS Contratos_ChaveGeral_Mes,

    COUNT(
      DISTINCT CASE
        WHEN b.NumeroDiaDaSemana <= p.DiaParametro
          AND b.Conta = 'Efeito Caixa'
        THEN b.ChaveEspecifica
        ELSE NULL
      END
    ) AS Contratos_ChaveEspecifica_Mes

  FROM parametros_dias p
  CROSS JOIN base b
  GROUP BY
    p.DiaParametro,
    b.MesReferencia
),

resumo_total AS (
  SELECT
    DiaParametro,

    MIN(ValorBruto_Mes) AS MinRevenue_ValorBruto,
    AVG(ValorBruto_Mes) AS MediaRecebidoMes_ValorBruto,
    MAX(ValorBruto_Mes) AS MaxRevenue_ValorBruto,

    MIN(ValorBloko_Mes) AS MinRevenue_ValorBloko,
    AVG(ValorBloko_Mes) AS MediaRecebidoMes_ValorBloko,
    MAX(ValorBloko_Mes) AS MaxRevenue_ValorBloko,

    MIN(ValorParceiro_Mes) AS MinRevenue_ValorParceiro,
    AVG(ValorParceiro_Mes) AS MediaRecebidoMes_ValorParceiro,
    MAX(ValorParceiro_Mes) AS MaxRevenue_ValorParceiro

  FROM mensal_total
  GROUP BY DiaParametro
),

mes_passado AS (
  SELECT
    DiaParametro,

    SUM(
      CASE
        WHEN MesReferencia = DATE_TRUNC(
          DATE_SUB(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 1 MONTH),
          MONTH
        )
        THEN ValorBruto_Mes
        ELSE 0
      END
    ) AS RecebiveisMesPassado_ValorBruto,

    SUM(
      CASE
        WHEN MesReferencia = DATE_TRUNC(
          DATE_SUB(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 1 MONTH),
          MONTH
        )
        THEN ValorBloko_Mes
        ELSE 0
      END
    ) AS RecebiveisMesPassado_ValorBloko,

    SUM(
      CASE
        WHEN MesReferencia = DATE_TRUNC(
          DATE_SUB(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 1 MONTH),
          MONTH
        )
        THEN ValorParceiro_Mes
        ELSE 0
      END
    ) AS RecebiveisMesPassado_ValorParceiro

  FROM mensal_total
  GROUP BY DiaParametro
),

resumo_situacao AS (
  SELECT
    DiaParametro,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Adimplente'
        THEN ValorBruto_Mes
        ELSE NULL
      END
    ) AS MediaAdimplente_ValorBruto,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Atrasado'
        THEN ValorBruto_Mes
        ELSE NULL
      END
    ) AS MediaAtrasado_ValorBruto,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Inadimplente'
        THEN ValorBruto_Mes
        ELSE NULL
      END
    ) AS MediaInadimplente_ValorBruto,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Adimplente'
        THEN ValorBloko_Mes
        ELSE NULL
      END
    ) AS MediaAdimplente_ValorBloko,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Atrasado'
        THEN ValorBloko_Mes
        ELSE NULL
      END
    ) AS MediaAtrasado_ValorBloko,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Inadimplente'
        THEN ValorBloko_Mes
        ELSE NULL
      END
    ) AS MediaInadimplente_ValorBloko,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Adimplente'
        THEN ValorParceiro_Mes
        ELSE NULL
      END
    ) AS MediaAdimplente_ValorParceiro,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Atrasado'
        THEN ValorParceiro_Mes
        ELSE NULL
      END
    ) AS MediaAtrasado_ValorParceiro,

    AVG(
      CASE
        WHEN SituacaoParcelaVisual = 'Inadimplente'
        THEN ValorParceiro_Mes
        ELSE NULL
      END
    ) AS MediaInadimplente_ValorParceiro

  FROM mensal_situacao
  GROUP BY DiaParametro
),

resumo_contratos AS (
  SELECT
    DiaParametro,

    AVG(Contratos_ChaveGeral_Mes) AS MediaContratos_ChaveGeral,
    AVG(Contratos_ChaveEspecifica_Mes) AS MediaContratos_ChaveEspecifica

  FROM mensal_contratos
  GROUP BY DiaParametro
)

SELECT
  rt.DiaParametro,

  mp.RecebiveisMesPassado_ValorBruto,
  mp.RecebiveisMesPassado_ValorBloko,
  mp.RecebiveisMesPassado_ValorParceiro,

  rt.MinRevenue_ValorBruto,
  rt.MediaRecebidoMes_ValorBruto,
  rt.MaxRevenue_ValorBruto,

  rt.MinRevenue_ValorBloko,
  rt.MediaRecebidoMes_ValorBloko,
  rt.MaxRevenue_ValorBloko,

  rt.MinRevenue_ValorParceiro,
  rt.MediaRecebidoMes_ValorParceiro,
  rt.MaxRevenue_ValorParceiro,

  rs.MediaAdimplente_ValorBruto,
  rs.MediaAtrasado_ValorBruto,
  rs.MediaInadimplente_ValorBruto,

  rs.MediaAdimplente_ValorBloko,
  rs.MediaAtrasado_ValorBloko,
  rs.MediaInadimplente_ValorBloko,

  rs.MediaAdimplente_ValorParceiro,
  rs.MediaAtrasado_ValorParceiro,
  rs.MediaInadimplente_ValorParceiro,

  rc.MediaContratos_ChaveGeral,
  rc.MediaContratos_ChaveEspecifica

FROM resumo_total rt
LEFT JOIN mes_passado mp
  ON rt.DiaParametro = mp.DiaParametro
LEFT JOIN resumo_situacao rs
  ON rt.DiaParametro = rs.DiaParametro
LEFT JOIN resumo_contratos rc
  ON rt.DiaParametro = rc.DiaParametro;