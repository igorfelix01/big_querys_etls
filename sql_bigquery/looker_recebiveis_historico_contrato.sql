-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_HISTORICO_CONTRATO

--

-- Visual do BI: matriz "Historico de Recebimento por Contrato"

--   Linhas  : ID = SaldoDevedor[ChaveGeral]

--   Colunas : Ano / Mes (Calendario aplicado no dueDate)

--   Valor   : [CohortSaldoDevedor]

--   Cor     : [Cor Cohort]

--

-- DAX -> REGRA

--   [CohortSaldoDevedor] = SUM(ValorBruto) do contrato com dueDate no mes,

--     TODAS as origens (recebidas + A Receber). ALLEXCEPT mantem so

--     operationTypeId, documentIdentificationId, subJudicie e NomeCompanhias

--     -> sem filtro de Conta nem de OrigemBase.

--     Contratos = os selecionados na pagina (db_titulos_totalizador),

--     aqui: Atrasado / Inadimplente, igual aos outros visuais da pagina.

--   [Cor Cohort], por contrato x mes (dueDate no mes):

--     1o tem parcela A Receber                        -> #F28B98 Em Aberto

--     2o tem recebida com paymentDate > dueDate       -> #B7D7F0 Paga com Atraso

--     3o tem recebida com paymentDate <= dueDate      -> #C6E0CA Paga

--

-- JA FILTRADO NO SQL (mesmos filtros da pagina):

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital' e sem 'Sem grupo'

--   SituacaoContrato (totalizador) IN ('Atrasado', 'Inadimplente')

--   SEM limite de periodo: coluna Mes = mes do dueDate

--

-- Uma linha por Mes x contrato.

-- Looker: Tabela dinamica | Linha = ID | Coluna = Mes |

--         Metricas = Valor_EmAberto, Valor_PagoAtraso, Valor_Pago (SUM)

--         cada metrica com formatacao condicional de cor fixa

--         (vermelho / azul / verde). So uma das 3 tem valor por mes.

--

-- Depende de: looker_studio.recebiveis_situacao_parcela,

--             analytics.fato_titulos_totalizador (etapa 2.3)

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_historico_contrato`;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_historico_contrato`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  ID,

  companyGroup



AS



WITH



totalizador AS (

  SELECT

    ChaveGeral,

    SituacaoContrato

  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral ORDER BY ChaveGeral) = 1

),



sd AS (

  SELECT

    s.ChaveGeral,

    s.clientName,

    s.OrigemBase,

    s.dueDate,

    s.paymentDate,

    s.ValorBruto,

    s.ValorBloko,

    s.ValorParceiro,

    s.companyGroup,

    s.companyName,

    s.subJudicie,

    t.SituacaoContrato

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` s

  JOIN totalizador t

    ON t.ChaveGeral = s.ChaveGeral

  WHERE s.dueDate IS NOT NULL

    AND s.documentIdentificationId = 'CT'

    AND s.companyGroup IS NOT NULL

    AND s.companyGroup NOT IN ('Bloko Capital', 'Sem grupo')

    AND t.SituacaoContrato IN ('Atrasado', 'Inadimplente')

),



agrupado AS (

  SELECT

    DATE_TRUNC(dueDate, MONTH) AS Mes,

    ChaveGeral,

    MAX(clientName)        AS clientName,

    MAX(SituacaoContrato)  AS SituacaoContrato,

    MAX(companyGroup)      AS companyGroup,

    MAX(companyName)       AS companyName,

    MAX(subJudicie)        AS subJudicie,



    SUM(ValorBruto)        AS Valor_Bruto,

    SUM(ValorBloko)        AS Valor_Bloko,

    SUM(ValorParceiro)     AS Valor_Parceiro,



    -- TemAberto

    COUNTIF(OrigemBase = 'A Receber') AS QtdAberto,



    -- TemPagoAtrasado (OrigemBase <> 'A Receber' inclui as recebidas)

    COUNTIF(OrigemBase <> 'A Receber'

            AND paymentDate IS NOT NULL

            AND paymentDate > dueDate)  AS QtdPagoAtrasado,



    -- TemPagoEmDia

    COUNTIF(OrigemBase <> 'A Receber'

            AND paymentDate IS NOT NULL

            AND paymentDate <= dueDate) AS QtdPagoEmDia

  FROM sd

  GROUP BY 1, 2

)



SELECT

  Mes,

  ChaveGeral AS ID,

  clientName AS Nome,

  SituacaoContrato,

  companyGroup,

  companyName,

  subJudicie,



  ROUND(Valor_Bruto, 2)    AS Valor_Bruto,

  ROUND(Valor_Bloko, 2)    AS Valor_Bloko,

  ROUND(Valor_Parceiro, 2) AS Valor_Parceiro,



  QtdAberto,

  QtdPagoAtrasado,

  QtdPagoEmDia,



  -- Valor separado pela cor (so uma das 3 colunas tem valor por mes):

  -- no Looker cada metrica recebe a sua cor fixa

  IF(QtdAberto > 0, ROUND(Valor_Bruto, 2), NULL)                          AS Valor_EmAberto,

  IF(QtdAberto = 0 AND QtdPagoAtrasado > 0, ROUND(Valor_Bruto, 2), NULL)  AS Valor_PagoAtraso,

  IF(QtdAberto = 0 AND QtdPagoAtrasado = 0 AND QtdPagoEmDia > 0,

     ROUND(Valor_Bruto, 2), NULL)                                         AS Valor_Pago,



  CASE

    WHEN QtdAberto       > 0 THEN 3

    WHEN QtdPagoAtrasado > 0 THEN 2

    WHEN QtdPagoEmDia    > 0 THEN 1

  END AS CodigoCor,



  CASE

    WHEN QtdAberto       > 0 THEN 'Parcelas em Aberto'

    WHEN QtdPagoAtrasado > 0 THEN 'Parcelas Pagas com Atraso'

    WHEN QtdPagoEmDia    > 0 THEN 'Parcelas Pagas'

  END AS StatusCohort,



  CASE

    WHEN QtdAberto       > 0 THEN '#F28B98'

    WHEN QtdPagoAtrasado > 0 THEN '#B7D7F0'

    WHEN QtdPagoEmDia    > 0 THEN '#C6E0CA'

  END AS CorCohort



FROM agrupado;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO: contratos do print do BI (2024)

-- esperado: 101-16055 set/24 540,61 vermelho | 101-16056 set/24 618,26 verde

--           101-16054 ago/24 505,16 azul     | 101-16067 ago/24 312,56 azul

-- ####################################################################



-- SELECT

--   ID,

--   Mes,

--   Valor_Bruto,

--   StatusCohort,

--   QtdAberto,

--   QtdPagoAtrasado,

--   QtdPagoEmDia

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_historico_contrato`

-- WHERE ID IN ('101-16054', '101-16055', '101-16056', '101-16067', '101-16069')

--   AND Mes BETWEEN '2024-08-01' AND '2024-12-01'

-- ORDER BY ID, Mes;