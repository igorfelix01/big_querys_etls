-- ####################################################################

-- LOOKER_STUDIO.VENDAS_SEGMENTACAO_CONTRATOS_ATIVOS

--

-- Visual do BI: "Segmentacao de Contratos Ativos"

--   Eixo X   : Calendario (mes da venda = contractDate / DataVenda)

--   Colunas  : Contagem de ContratosAtivos[ChaveEmpreendimento]

--   Legenda  : ContratosAtivos[SituacaoContrato]  ('-', Adimplente,

--              Atrasado, Inadimplente)

--   Linha    : Soma de ContratosAtivos[ValorLiquidoAgregado]

--              ("Valor Recebido dos Contratos")

--

-- PQ ContratosAtivos (fiel):

--   db_vendas com situation = 'Emitido', DISTINCT ChaveGeral

--   + db_a_receber_totalizador (SituacaoContrato; sem A Receber -> '-')

--   + db_recebidas_totalizador (ValorLiquidoAgregado = SUM netAmount do

--     contrato = SUM(ValorBruto) da fato_recebidas, todas as datas)

--

-- SEM filtro de pagina (os totais batem com "Contratos Ativos" do grafico

-- Vendas vs Contratos Ativos). SEM limite de periodo: coluna Mes.

--

-- Looker: Grafico combinado | Dimensao = Mes | Detalhamento = SituacaoContrato

--   nao funciona em grafico combinado -> usar as colunas Qtd_* (barras

--   empilhadas) + ValorLiquidoAgregado (linha, eixo direito).

--

-- Depende de: analytics.fato_vendas, analytics.fato_areceber,

--             analytics.fato_recebidas, analytics.dim_nome_companhias

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.vendas_segmentacao_contratos_ativos`;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.vendas_segmentacao_contratos_ativos`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  SituacaoContrato,

  companyGroup



AS



WITH



nome_companhias AS (

  SELECT

    CAST(companyId AS STRING) AS companyId,

    companyGroup,

    companyName

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  WHERE companyId IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (PARTITION BY CAST(companyId AS STRING) ORDER BY companyGroup) = 1

),



-- ContratosAtivos: Emitido, DISTINCT ChaveGeral (1a ocorrencia)

contratos_ativos AS (

  SELECT

    v.ChaveGeral,

    DATE_TRUNC(DATE(v.contractDate), MONTH)  AS Mes,

    SPLIT(v.ChaveGeral, '-')[SAFE_OFFSET(0)] AS companyId

  FROM `dadosfinanceiro-501613.analytics.fato_vendas` v

  WHERE v.situation = 'Emitido'

    AND v.ChaveGeral IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (PARTITION BY v.ChaveGeral ORDER BY v.contractDate) = 1

),



-- db_a_receber_totalizador recalculado da fato_areceber (= db_a_receber):

--   por parcela: atrasoDias <= 30 Adimplente(1) / <= 90 Atrasado(2) /

--   senao Inadimplente(3); contrato = MAX -> SituacaoContrato

--   (a analytics.fato_a_receber_totalizador antiga nao casava as chaves)

ar_totalizador AS (

  SELECT

    ChaveGeral,

    CASE MAX(CASE

               WHEN atrasoDias <= 30 THEN 1

               WHEN atrasoDias <= 90 THEN 2

               ELSE 3

             END)

      WHEN 1 THEN 'Adimplente'

      WHEN 2 THEN 'Atrasado'

      WHEN 3 THEN 'Inadimplente'

    END AS SituacaoContrato

  FROM `dadosfinanceiro-501613.analytics.fato_areceber`

  WHERE ChaveGeral IS NOT NULL

  GROUP BY ChaveGeral

),



-- db_recebidas_totalizador: ValorLiquidoAgregado = SUM(netAmount)

recebidas_totalizador AS (

  SELECT

    ChaveGeral,

    SUM(ValorBruto) AS ValorLiquidoAgregado

  FROM `dadosfinanceiro-501613.analytics.fato_recebidas`

  WHERE ChaveGeral IS NOT NULL

  GROUP BY ChaveGeral

),



base AS (

  SELECT

    ca.Mes,

    ca.ChaveGeral,

    IFNULL(ar.SituacaoContrato, '-')     AS SituacaoContrato,

    IFNULL(nc.companyGroup, 'Sem grupo') AS companyGroup,

    nc.companyName,

    rt.ValorLiquidoAgregado

  FROM contratos_ativos ca

  LEFT JOIN ar_totalizador ar

    ON ar.ChaveGeral = ca.ChaveGeral

  LEFT JOIN recebidas_totalizador rt

    ON rt.ChaveGeral = ca.ChaveGeral

  LEFT JOIN nome_companhias nc

    ON nc.companyId = ca.companyId

  WHERE ca.Mes IS NOT NULL

)



SELECT

  Mes,

  SituacaoContrato,

  CASE SituacaoContrato

    WHEN '-'            THEN 1

    WHEN 'Adimplente'   THEN 2

    WHEN 'Atrasado'     THEN 3

    WHEN 'Inadimplente' THEN 4

    ELSE 5

  END AS OrdemSituacao,

  companyGroup,

  companyName,



  COUNT(ChaveGeral) AS QtdContratos,



  -- mesmas contagens em colunas (para barras empilhadas no grafico combinado)

  COUNTIF(SituacaoContrato = '-')            AS Qtd_SemAReceber,

  COUNTIF(SituacaoContrato = 'Adimplente')   AS Qtd_Adimplente,

  COUNTIF(SituacaoContrato = 'Atrasado')     AS Qtd_Atrasado,

  COUNTIF(SituacaoContrato = 'Inadimplente') AS Qtd_Inadimplente,



  ROUND(SUM(ValorLiquidoAgregado), 2) AS ValorLiquidoAgregado



FROM base

GROUP BY 1, 2, 3, 4, 5;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO (BI)

--   total: ago/25 65 | set 77 | out 85 | nov 122 | dez 64 | jan/26 84 |

--          fev 80 | mar 99 | abr 80 | mai 82 | jun 163 | jul 92 | ago 266

--   Adimplente: ago/25 35 | set 51 | out 67 | nov 75 | dez 30 | jan 57 |

--          fev 56 | mar 73 | abr 60 | mai 71 | jun 151 | jul 83 | ago 264

--   Valor recebido: ago/25 1,6 Mi | set 1,3 | nov 1,4 | dez 1,2 | abr 1,3 |

--          jun 2,7 | jul 2,3 | ago 0,3

-- ####################################################################



-- SELECT

--   Mes,

--   SUM(QtdContratos)     AS total,

--   SUM(Qtd_SemAReceber)  AS sem_a_receber,

--   SUM(Qtd_Adimplente)   AS adimplente,

--   SUM(Qtd_Atrasado)     AS atrasado,

--   SUM(Qtd_Inadimplente) AS inadimplente,

--   ROUND(SUM(ValorLiquidoAgregado), 2) AS valor_recebido

-- FROM `dadosfinanceiro-501613.looker_studio.vendas_segmentacao_contratos_ativos`

-- WHERE Mes >= '2025-08-01'

-- GROUP BY Mes

-- ORDER BY Mes;