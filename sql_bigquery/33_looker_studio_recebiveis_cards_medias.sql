DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.recebiveis_cards_medias`;



DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.recebiveis_cards_contratos`;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.looker_studio.recebiveis_cards_medias`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY DiaParametro, SituacaoParcelaVisual

AS

WITH dias AS (

  SELECT DiaParametro

  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS DiaParametro

),



base AS (

  SELECT

    MesReferencia,

    SituacaoParcelaVisual,

    NumeroDiaDaSemana,



    ValorBruto_EfeitoCaixa,

    ValorBloko_EfeitoCaixa,

    ValorParceiro_EfeitoCaixa



  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

  WHERE documentIdentificationId = 'CT'

    AND companyGroup IS NOT NULL

    AND TRIM(companyGroup) <> ''

    AND companyGroup <> 'Bloko Capital'

    AND SituacaoParcelaVisual IN (

      'Adimplente',

      'Atrasado',

      'Inadimplente'

    )

)



SELECT

  b.MesReferencia,

  d.DiaParametro,

  b.SituacaoParcelaVisual,



  SUM(

    CASE

      WHEN b.NumeroDiaDaSemana <= d.DiaParametro THEN b.ValorBruto_EfeitoCaixa

      ELSE 0

    END

  ) AS ValorBruto_Mes,



  SUM(

    CASE

      WHEN b.NumeroDiaDaSemana <= d.DiaParametro THEN b.ValorBloko_EfeitoCaixa

      ELSE 0

    END

  ) AS ValorBloko_Mes,



  SUM(

    CASE

      WHEN b.NumeroDiaDaSemana <= d.DiaParametro THEN b.ValorParceiro_EfeitoCaixa

      ELSE 0

    END

  ) AS ValorParceiro_Mes



FROM base b

CROSS JOIN dias d

GROUP BY

  b.MesReferencia,

  d.DiaParametro,

  b.SituacaoParcelaVisual;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.looker_studio.recebiveis_cards_contratos`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY DiaParametro

AS

WITH dias AS (

  SELECT DiaParametro

  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS DiaParametro

),



base AS (

  SELECT

    MesReferencia,

    NumeroDiaDaSemana,

    ChaveGeral,

    ChaveEspecifica

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

  WHERE documentIdentificationId = 'CT'

    AND companyGroup IS NOT NULL

    AND TRIM(companyGroup) <> ''

    AND companyGroup <> 'Bloko Capital'

    AND Conta = 'Efeito Caixa'

)



SELECT

  b.MesReferencia,

  d.DiaParametro,



  COUNT(DISTINCT CASE

    WHEN b.NumeroDiaDaSemana <= d.DiaParametro THEN b.ChaveGeral

  END) AS Contratos_ChaveGeral_Mes,



  COUNT(DISTINCT CASE

    WHEN b.NumeroDiaDaSemana <= d.DiaParametro THEN b.ChaveEspecifica

  END) AS Contratos_ChaveEspecifica_Mes



FROM base b

CROSS JOIN dias d

GROUP BY

  b.MesReferencia,

  d.DiaParametro;