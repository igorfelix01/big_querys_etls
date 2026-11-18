DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.recebiveis_diario_acumulado`;-- [otimizacao] CTE 'base' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base AS
  SELECT

    ChaveEspecifica,

    ChaveGeral,



    OrigemBase,

    Conta,

    SituacaoParcela,

    SituacaoParcelaVisual,



    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,



    companyId,

    companyName,

    costCenterId,

    costCenterName,



    paymentDate,

    dueDate,



    ValorBruto,

    ValorBloko,

    ValorParceiro,

    originalAmount



  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

  WHERE documentIdentificationId = 'CT'

    AND companyGroup IS NOT NULL

    AND TRIM(companyGroup) <> ''

    AND companyGroup <> 'Bloko Capital';

-- [otimizacao] CTE 'eventos_diarios' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE eventos_diarios AS
WITH
eventos_recebidas AS (

  SELECT

    paymentDate AS DataReferencia,

    DATE_TRUNC(paymentDate, MONTH) AS MesReferencia,



    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,



    companyId,

    companyName,

    costCenterId,

    costCenterName,



    SUM(CASE WHEN SituacaoParcela = 'Adimplente' THEN ValorBruto ELSE 0 END) AS Adimplente_ValorBruto,

    SUM(CASE WHEN SituacaoParcela = 'Atrasado' THEN ValorBruto ELSE 0 END) AS Atrasado_ValorBruto,

    SUM(CASE WHEN SituacaoParcela = 'Inadimplente' THEN ValorBruto ELSE 0 END) AS Inadimplente_ValorBruto,

    SUM(CASE WHEN SituacaoParcela = 'Antecipado' THEN ValorBruto ELSE 0 END) AS Antecipado_ValorBruto,

    SUM(CASE WHEN SituacaoParcela = 'Quitação' THEN ValorBruto ELSE 0 END) AS Quitacao_ValorBruto,

    SUM(CASE WHEN SituacaoParcela = 'Venda à vista' THEN ValorBruto ELSE 0 END) AS VendaAVista_ValorBruto,

    SUM(CASE WHEN SituacaoParcela = 'Ato' THEN ValorBruto ELSE 0 END) AS Ato_ValorBruto,



    SUM(CASE WHEN SituacaoParcela = 'Adimplente' THEN ValorBloko ELSE 0 END) AS Adimplente_ValorBloko,

    SUM(CASE WHEN SituacaoParcela = 'Atrasado' THEN ValorBloko ELSE 0 END) AS Atrasado_ValorBloko,

    SUM(CASE WHEN SituacaoParcela = 'Inadimplente' THEN ValorBloko ELSE 0 END) AS Inadimplente_ValorBloko,

    SUM(CASE WHEN SituacaoParcela = 'Antecipado' THEN ValorBloko ELSE 0 END) AS Antecipado_ValorBloko,

    SUM(CASE WHEN SituacaoParcela = 'Quitação' THEN ValorBloko ELSE 0 END) AS Quitacao_ValorBloko,

    SUM(CASE WHEN SituacaoParcela = 'Venda à vista' THEN ValorBloko ELSE 0 END) AS VendaAVista_ValorBloko,

    SUM(CASE WHEN SituacaoParcela = 'Ato' THEN ValorBloko ELSE 0 END) AS Ato_ValorBloko,



    SUM(CASE WHEN SituacaoParcela = 'Adimplente' THEN ValorParceiro ELSE 0 END) AS Adimplente_ValorParceiro,

    SUM(CASE WHEN SituacaoParcela = 'Atrasado' THEN ValorParceiro ELSE 0 END) AS Atrasado_ValorParceiro,

    SUM(CASE WHEN SituacaoParcela = 'Inadimplente' THEN ValorParceiro ELSE 0 END) AS Inadimplente_ValorParceiro,

    SUM(CASE WHEN SituacaoParcela = 'Antecipado' THEN ValorParceiro ELSE 0 END) AS Antecipado_ValorParceiro,

    SUM(CASE WHEN SituacaoParcela = 'Quitação' THEN ValorParceiro ELSE 0 END) AS Quitacao_ValorParceiro,

    SUM(CASE WHEN SituacaoParcela = 'Venda à vista' THEN ValorParceiro ELSE 0 END) AS VendaAVista_ValorParceiro,

    SUM(CASE WHEN SituacaoParcela = 'Ato' THEN ValorParceiro ELSE 0 END) AS Ato_ValorParceiro,



    SUM(ValorBruto) AS Recebidas_ValorBruto,

    SUM(ValorBloko) AS Recebidas_ValorBloko,

    SUM(ValorParceiro) AS Recebidas_ValorParceiro,



    CAST(0 AS NUMERIC) AS AReceber_OriginalAmount



  FROM base

  WHERE OrigemBase = 'Recebidas'

    AND Conta = 'Efeito Caixa'

    AND paymentDate IS NOT NULL

  GROUP BY

    DataReferencia,

    MesReferencia,

    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,

    companyId,

    companyName,

    costCenterId,

    costCenterName

),

eventos_a_receber AS (

  SELECT

    dueDate AS DataReferencia,

    DATE_TRUNC(dueDate, MONTH) AS MesReferencia,



    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,



    companyId,

    companyName,

    costCenterId,

    costCenterName,



    CAST(0 AS NUMERIC) AS Adimplente_ValorBruto,

    CAST(0 AS NUMERIC) AS Atrasado_ValorBruto,

    CAST(0 AS NUMERIC) AS Inadimplente_ValorBruto,

    CAST(0 AS NUMERIC) AS Antecipado_ValorBruto,

    CAST(0 AS NUMERIC) AS Quitacao_ValorBruto,

    CAST(0 AS NUMERIC) AS VendaAVista_ValorBruto,

    CAST(0 AS NUMERIC) AS Ato_ValorBruto,



    CAST(0 AS NUMERIC) AS Adimplente_ValorBloko,

    CAST(0 AS NUMERIC) AS Atrasado_ValorBloko,

    CAST(0 AS NUMERIC) AS Inadimplente_ValorBloko,

    CAST(0 AS NUMERIC) AS Antecipado_ValorBloko,

    CAST(0 AS NUMERIC) AS Quitacao_ValorBloko,

    CAST(0 AS NUMERIC) AS VendaAVista_ValorBloko,

    CAST(0 AS NUMERIC) AS Ato_ValorBloko,



    CAST(0 AS NUMERIC) AS Adimplente_ValorParceiro,

    CAST(0 AS NUMERIC) AS Atrasado_ValorParceiro,

    CAST(0 AS NUMERIC) AS Inadimplente_ValorParceiro,

    CAST(0 AS NUMERIC) AS Antecipado_ValorParceiro,

    CAST(0 AS NUMERIC) AS Quitacao_ValorParceiro,

    CAST(0 AS NUMERIC) AS VendaAVista_ValorParceiro,

    CAST(0 AS NUMERIC) AS Ato_ValorParceiro,



    CAST(0 AS NUMERIC) AS Recebidas_ValorBruto,

    CAST(0 AS NUMERIC) AS Recebidas_ValorBloko,

    CAST(0 AS NUMERIC) AS Recebidas_ValorParceiro,



    SUM(originalAmount) AS AReceber_OriginalAmount



  FROM base

  WHERE OrigemBase = 'A Receber'

    AND dueDate IS NOT NULL

  GROUP BY

    DataReferencia,

    MesReferencia,

    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,

    companyId,

    companyName,

    costCenterId,

    costCenterName

),

eventos_unificados AS (

  SELECT * FROM eventos_recebidas

  UNION ALL

  SELECT * FROM eventos_a_receber

)
SELECT * FROM (


  SELECT

    DataReferencia,

    MesReferencia,



    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,



    companyId,

    companyName,

    costCenterId,

    costCenterName,



    SUM(Adimplente_ValorBruto) AS Adimplente_ValorBruto,

    SUM(Atrasado_ValorBruto) AS Atrasado_ValorBruto,

    SUM(Inadimplente_ValorBruto) AS Inadimplente_ValorBruto,

    SUM(Antecipado_ValorBruto) AS Antecipado_ValorBruto,

    SUM(Quitacao_ValorBruto) AS Quitacao_ValorBruto,

    SUM(VendaAVista_ValorBruto) AS VendaAVista_ValorBruto,

    SUM(Ato_ValorBruto) AS Ato_ValorBruto,



    SUM(Adimplente_ValorBloko) AS Adimplente_ValorBloko,

    SUM(Atrasado_ValorBloko) AS Atrasado_ValorBloko,

    SUM(Inadimplente_ValorBloko) AS Inadimplente_ValorBloko,

    SUM(Antecipado_ValorBloko) AS Antecipado_ValorBloko,

    SUM(Quitacao_ValorBloko) AS Quitacao_ValorBloko,

    SUM(VendaAVista_ValorBloko) AS VendaAVista_ValorBloko,

    SUM(Ato_ValorBloko) AS Ato_ValorBloko,



    SUM(Adimplente_ValorParceiro) AS Adimplente_ValorParceiro,

    SUM(Atrasado_ValorParceiro) AS Atrasado_ValorParceiro,

    SUM(Inadimplente_ValorParceiro) AS Inadimplente_ValorParceiro,

    SUM(Antecipado_ValorParceiro) AS Antecipado_ValorParceiro,

    SUM(Quitacao_ValorParceiro) AS Quitacao_ValorParceiro,

    SUM(VendaAVista_ValorParceiro) AS VendaAVista_ValorParceiro,

    SUM(Ato_ValorParceiro) AS Ato_ValorParceiro,



    SUM(Recebidas_ValorBruto) AS Recebidas_ValorBruto,

    SUM(Recebidas_ValorBloko) AS Recebidas_ValorBloko,

    SUM(Recebidas_ValorParceiro) AS Recebidas_ValorParceiro,



    SUM(AReceber_OriginalAmount) AS AReceber_OriginalAmount



  FROM eventos_unificados

  GROUP BY

    DataReferencia,

    MesReferencia,

    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,

    companyId,

    companyName,

    costCenterId,

    costCenterName


);





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.looker_studio.recebiveis_diario_acumulado`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY documentIdentificationId, companyGroup, companyName, DataReferencia

AS
WITH
dimensoes_mes AS (

  SELECT DISTINCT

    MesReferencia,

    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,

    companyId,

    companyName,

    costCenterId,

    costCenterName

  FROM eventos_diarios

),

calendario_dias AS (

  SELECT

    dm.MesReferencia,

    dia AS DataReferencia,



    dm.documentIdentificationId,

    dm.subJudicie,

    dm.companyGroup,

    dm.anoPeriodoVenda,

    dm.companyId,

    dm.companyName,

    dm.costCenterId,

    dm.costCenterName



  FROM dimensoes_mes dm,

  UNNEST(

    GENERATE_DATE_ARRAY(

      dm.MesReferencia,

      LAST_DAY(dm.MesReferencia),

      INTERVAL 1 DAY

    )

  ) AS dia

),

base_diaria_completa AS (

  SELECT

    cd.DataReferencia,

    cd.MesReferencia,



    EXTRACT(YEAR FROM cd.DataReferencia) AS Ano,

    EXTRACT(MONTH FROM cd.DataReferencia) AS Mes,

    EXTRACT(DAY FROM cd.DataReferencia) AS Dia,



    cd.documentIdentificationId,

    cd.subJudicie,

    cd.companyGroup,

    cd.anoPeriodoVenda,

    cd.companyId,

    cd.companyName,

    cd.costCenterId,

    cd.costCenterName,



    IFNULL(ed.Adimplente_ValorBruto, 0) AS Adimplente_ValorBruto,

    IFNULL(ed.Atrasado_ValorBruto, 0) AS Atrasado_ValorBruto,

    IFNULL(ed.Inadimplente_ValorBruto, 0) AS Inadimplente_ValorBruto,

    IFNULL(ed.Antecipado_ValorBruto, 0) AS Antecipado_ValorBruto,

    IFNULL(ed.Quitacao_ValorBruto, 0) AS Quitacao_ValorBruto,

    IFNULL(ed.VendaAVista_ValorBruto, 0) AS VendaAVista_ValorBruto,

    IFNULL(ed.Ato_ValorBruto, 0) AS Ato_ValorBruto,



    IFNULL(ed.Adimplente_ValorBloko, 0) AS Adimplente_ValorBloko,

    IFNULL(ed.Atrasado_ValorBloko, 0) AS Atrasado_ValorBloko,

    IFNULL(ed.Inadimplente_ValorBloko, 0) AS Inadimplente_ValorBloko,

    IFNULL(ed.Antecipado_ValorBloko, 0) AS Antecipado_ValorBloko,

    IFNULL(ed.Quitacao_ValorBloko, 0) AS Quitacao_ValorBloko,

    IFNULL(ed.VendaAVista_ValorBloko, 0) AS VendaAVista_ValorBloko,

    IFNULL(ed.Ato_ValorBloko, 0) AS Ato_ValorBloko,



    IFNULL(ed.Adimplente_ValorParceiro, 0) AS Adimplente_ValorParceiro,

    IFNULL(ed.Atrasado_ValorParceiro, 0) AS Atrasado_ValorParceiro,

    IFNULL(ed.Inadimplente_ValorParceiro, 0) AS Inadimplente_ValorParceiro,

    IFNULL(ed.Antecipado_ValorParceiro, 0) AS Antecipado_ValorParceiro,

    IFNULL(ed.Quitacao_ValorParceiro, 0) AS Quitacao_ValorParceiro,

    IFNULL(ed.VendaAVista_ValorParceiro, 0) AS VendaAVista_ValorParceiro,

    IFNULL(ed.Ato_ValorParceiro, 0) AS Ato_ValorParceiro,



    IFNULL(ed.Recebidas_ValorBruto, 0) AS Recebidas_ValorBruto,

    IFNULL(ed.Recebidas_ValorBloko, 0) AS Recebidas_ValorBloko,

    IFNULL(ed.Recebidas_ValorParceiro, 0) AS Recebidas_ValorParceiro,



    IFNULL(ed.AReceber_OriginalAmount, 0) AS AReceber_OriginalAmount



  FROM calendario_dias cd

  LEFT JOIN eventos_diarios ed

    ON cd.DataReferencia = ed.DataReferencia

   AND cd.MesReferencia = ed.MesReferencia

   AND IFNULL(cd.documentIdentificationId, '') = IFNULL(ed.documentIdentificationId, '')

   AND IFNULL(cd.subJudicie, '') = IFNULL(ed.subJudicie, '')

   AND IFNULL(cd.companyGroup, '') = IFNULL(ed.companyGroup, '')

   AND IFNULL(cd.anoPeriodoVenda, '') = IFNULL(ed.anoPeriodoVenda, '')

   AND IFNULL(CAST(cd.companyId AS STRING), '') = IFNULL(CAST(ed.companyId AS STRING), '')

   AND IFNULL(cd.companyName, '') = IFNULL(ed.companyName, '')

   AND IFNULL(CAST(cd.costCenterId AS STRING), '') = IFNULL(CAST(ed.costCenterId AS STRING), '')

   AND IFNULL(cd.costCenterName, '') = IFNULL(ed.costCenterName, '')

)
SELECT

  DataReferencia,

  MesReferencia,

  Ano,

  Mes,

  Dia,



  documentIdentificationId,

  subJudicie,

  companyGroup,

  anoPeriodoVenda,

  companyId,

  companyName,

  costCenterId,

  costCenterName,



  SUM(Adimplente_ValorBruto) OVER w AS acumAdimplente_ValorBruto,

  SUM(Atrasado_ValorBruto) OVER w AS acumAtrasado_ValorBruto,

  SUM(Inadimplente_ValorBruto) OVER w AS acumInadimplente_ValorBruto,

  SUM(Antecipado_ValorBruto) OVER w AS acumAntecipado_ValorBruto,

  SUM(Quitacao_ValorBruto) OVER w AS acumQuitacao_ValorBruto,

  SUM(VendaAVista_ValorBruto) OVER w AS acumVendaAVista_ValorBruto,

  SUM(Ato_ValorBruto) OVER w AS acumAto_ValorBruto,



  SUM(Adimplente_ValorBloko) OVER w AS acumAdimplente_ValorBloko,

  SUM(Atrasado_ValorBloko) OVER w AS acumAtrasado_ValorBloko,

  SUM(Inadimplente_ValorBloko) OVER w AS acumInadimplente_ValorBloko,

  SUM(Antecipado_ValorBloko) OVER w AS acumAntecipado_ValorBloko,

  SUM(Quitacao_ValorBloko) OVER w AS acumQuitacao_ValorBloko,

  SUM(VendaAVista_ValorBloko) OVER w AS acumVendaAVista_ValorBloko,

  SUM(Ato_ValorBloko) OVER w AS acumAto_ValorBloko,



  SUM(Adimplente_ValorParceiro) OVER w AS acumAdimplente_ValorParceiro,

  SUM(Atrasado_ValorParceiro) OVER w AS acumAtrasado_ValorParceiro,

  SUM(Inadimplente_ValorParceiro) OVER w AS acumInadimplente_ValorParceiro,

  SUM(Antecipado_ValorParceiro) OVER w AS acumAntecipado_ValorParceiro,

  SUM(Quitacao_ValorParceiro) OVER w AS acumQuitacao_ValorParceiro,

  SUM(VendaAVista_ValorParceiro) OVER w AS acumVendaAVista_ValorParceiro,

  SUM(Ato_ValorParceiro) OVER w AS acumAto_ValorParceiro,



  SUM(AReceber_OriginalAmount) OVER w AS acumAReceber,

  SUM(Recebidas_ValorBruto) OVER w AS acumRecebidas_ValorBruto,

  SUM(Recebidas_ValorBloko) OVER w AS acumRecebidas_ValorBloko,

  SUM(Recebidas_ValorParceiro) OVER w AS acumRecebidas_ValorParceiro



FROM base_diaria_completa

WINDOW w AS (

  PARTITION BY

    MesReferencia,

    documentIdentificationId,

    subJudicie,

    companyGroup,

    anoPeriodoVenda,

    companyId,

    companyName,

    costCenterId,

    costCenterName

  ORDER BY

    DataReferencia

  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

);