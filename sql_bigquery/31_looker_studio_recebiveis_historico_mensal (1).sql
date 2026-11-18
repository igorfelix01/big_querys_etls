-- SEM particao (validade de particao de 60 dias apagava os meses antigos)
-- DiaDoMes = dia do pagamento (1-31; em aberto = 1): filtro "Dias" do Looker
DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.recebiveis_historico_mensal`;

CREATE OR REPLACE TABLE `dadosfinanceiro-501613.looker_studio.recebiveis_historico_mensal`
CLUSTER BY documentIdentificationId, companyGroup, subJudicie, companyName
AS
SELECT
  MesReferencia,
  paymentYear,
  paymentMonth,

  SituacaoParcela,
  SituacaoParcelaVisual,

  documentIdentificationId,
  subJudicie,
  companyGroup,
  anoPeriodoVenda,

  OrigemBase,
  Conta,

  companyId,
  companyName,

  costCenterId,
  costCenterName,

  NumeroDiaDaSemana,
  -- filtro "Dias" do Looker (dia do mes do pagamento; em aberto = 1)
  IFNULL(NumeroDiaDaSemana, 1) AS DiaDoMes,

  SUM(ValorBruto_EfeitoCaixa) AS ValorBruto_EfeitoCaixa,
  SUM(ValorBloko_EfeitoCaixa) AS ValorBloko_EfeitoCaixa,
  SUM(ValorParceiro_EfeitoCaixa) AS ValorParceiro_EfeitoCaixa,

  SUM(ValorBruto) AS ValorBruto_Total,
  SUM(ValorBloko) AS ValorBloko_Total,
  SUM(ValorParceiro) AS ValorParceiro_Total,

  SUM(
    CASE
      WHEN SituacaoParcelaVisual = 'Em Aberto'
        AND IFNULL(costCenterName, '') NOT IN (
          'Villas Park - Obra',
          'Gran Park Bom Despacho - Obra',
          'Alta Villa Betim - Obra',
          'Gran Royalle Ipatinga - Obra'
        )
      THEN ValorBruto
      ELSE 0
    END
  ) AS ValorEmAberto,

  SUM(
    CASE
      WHEN SituacaoParcelaVisual = 'Em Aberto'
        AND IFNULL(costCenterName, '') NOT IN (
          'Villas Park - Obra',
          'Gran Park Bom Despacho - Obra',
          'Alta Villa Betim - Obra',
          'Gran Royalle Ipatinga - Obra'
        )
      THEN ValorBloko
      ELSE 0
    END
  ) AS ValorEmAbertoBloko,

  SUM(
    CASE
      WHEN SituacaoParcelaVisual = 'Em Aberto'
        AND IFNULL(costCenterName, '') NOT IN (
          'Villas Park - Obra',
          'Gran Park Bom Despacho - Obra',
          'Alta Villa Betim - Obra',
          'Gran Royalle Ipatinga - Obra'
        )
      THEN ValorParceiro
      ELSE 0
    END
  ) AS ValorEmAbertoParceiro,

  COUNT(*) AS linhas,
  COUNT(ChaveEspecifica) AS contagem_chave_especifica,
  COUNT(DISTINCT ChaveEspecifica) AS chaves_distintas,
  COUNT(DISTINCT ChaveGeral) AS contratos

FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`
GROUP BY
  MesReferencia,
  paymentYear,
  paymentMonth,
  SituacaoParcela,
  SituacaoParcelaVisual,
  documentIdentificationId,
  subJudicie,
  companyGroup,
  anoPeriodoVenda,
  OrigemBase,
  Conta,
  companyId,
  companyName,
  costCenterId,
  costCenterName,
  NumeroDiaDaSemana,
  DiaDoMes;