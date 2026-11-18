-- ####################################################################

-- LOOKER_STUDIO.DISTRATOS_VGV_RECEBIDO

-- Graficos do BI:

--  1) "VGV x Valor Total Recebido"

--  3) tabela "Detalhamento Distratos Realizados" (Origem = 'Sienge'):

--     Empreendimento (enterpriseName), Cliente (names), Distratos,

--     DataReferencia (cancellationDate), Titulo (receivableBillId),

--     Quadra_Lote (name), Valor_Total_Recebido (ValorLiquidoAgregado),

--     Descricao (db_unidades)

--  2) "Distratos por Data da Venda": Contagem de Distratos[ChaveGeral]

--     por mes (cancellationDate) x Distratos[anoPeriodoVenda]

--     -> metrica Distratos (SOMA), detalhamento anoPeriodoVenda,

--        filtro Origem = 'Sienge'

--

-- Grafico 1:

--   Eixo X  : Calendario (Ano > Month Name)

--   Colunas : Valor Distrato       = SUM(Base_Distratos_Operacoes[VALOR DISTRATO])

--             Valor Total Recebido = SUM(Distratos[ValorLiquidoAgregado])

--   Linha   : VGV Distrato         = SUM(Distratos[value])

--

-- Duas tabelas diferentes no mesmo eixo de data -> aqui viram UMA tabela

-- (UNION), cada linha com o valor da sua origem e as outras metricas NULL:

--   Origem = 'Controle Operacoes' (planilha DISTRATOS - CONTROLE OPERACOES)

--            data = MES_CANCELAMENTO

--   Origem = 'Sienge'             (analytics.fato_distratos, situation Cancelado)

--            data = cancellationDate

-- No Looker: SOMA de cada metrica; o periodo pelo campo DataReferencia.

--

-- Empresa: enterpriseId -> NomeCompanhias (companyGroup / companyName)

-- SEM periodo e SEM filtro de empresa no SQL (ficam no Looker).

--

-- Depende de: analytics.fato_distratos_controle_operacoes,

--             analytics.fato_distratos, analytics.dim_nome_companhias

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.distratos_vgv_recebido`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.distratos_vgv_recebido`

CLUSTER BY Origem, companyGroup

AS



WITH



nome_companhias AS (

  SELECT

    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,

    companyGroup,

    companyName,

    enterpriseName

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  WHERE enterpriseId IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (

    PARTITION BY SAFE_CAST(enterpriseId AS INT64)

    ORDER BY companyGroup, companyName

  ) = 1

),



-- db_unidades: 1 Descricao por lote (ChaveLote = companyId-enterpriseId-name)

unidades AS (

  SELECT ChaveLote, `Descrição` AS Descricao

  FROM `dadosfinanceiro-501613.analytics.dim_unidades`

  WHERE ChaveLote IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveLote ORDER BY `Descrição`) = 1

),



-- planilha de controle (Base_Distratos_Operacoes)

controle AS (

  SELECT

    'Controle Operacoes'                         AS Origem,

    CAST(NULL AS STRING)                         AS ChaveGeral,

    CAST(NULL AS STRING)                         AS anoPeriodoVenda,

    0                                            AS Distratos,

    CAST(NULL AS STRING)                         AS Empreendimento,

    CAST(NULL AS STRING)                         AS Quadra_Lote,

    CAST(NULL AS STRING)                         AS Descricao,

    MES_CANCELAMENTO                             AS DataReferencia,

    Data                                         AS DataLancamento,

    SAFE_CAST(TRIM(enterpriseId) AS INT64)       AS enterpriseId,

    CAST(Titulo AS STRING)                       AS Titulo,

    Cliente,

    TIPO_DE_CANCELAMENTO,

    VALOR_DISTRATO                               AS Valor_Distrato,

    CAST(NULL AS FLOAT64)                        AS Valor_Total_Recebido,

    CAST(NULL AS FLOAT64)                        AS VGV_Distrato

  FROM `dadosfinanceiro-501613.analytics.fato_distratos_controle_operacoes`

),



-- distratos do Sienge (Distratos)

sienge AS (

  SELECT

    'Sienge'                                     AS Origem,

    CAST(ChaveGeral AS STRING)                   AS ChaveGeral,

    CAST(anoPeriodoVenda AS STRING)              AS anoPeriodoVenda,     -- legenda "Periodo Venda"

    IF(ChaveGeral IS NULL, 0, 1)                 AS Distratos,           -- Contagem de Distratos[ChaveGeral]

    CAST(enterpriseName AS STRING)               AS Empreendimento,      -- Distratos[enterpriseName]

    CAST(name AS STRING)                         AS Quadra_Lote,         -- Distratos[name]

    un.Descricao                                 AS Descricao,           -- db_unidades[Descricao]

    SAFE_CAST(cancellationDate AS DATE)          AS DataReferencia,

    SAFE_CAST(cancellationDate AS DATE)          AS DataLancamento,

    SAFE_CAST(enterpriseId AS INT64)             AS enterpriseId,

    CAST(receivableBillId AS STRING)             AS Titulo,

    CAST(names AS STRING)                        AS Cliente,             -- Distratos[names]

    CAST(cancellationReason AS STRING)           AS TIPO_DE_CANCELAMENTO,

    CAST(NULL AS FLOAT64)                        AS Valor_Distrato,

    CAST(ValorLiquidoAgregado AS FLOAT64)        AS Valor_Total_Recebido,

    CAST(value AS FLOAT64)                       AS VGV_Distrato

  FROM `dadosfinanceiro-501613.analytics.fato_distratos` d

  LEFT JOIN unidades un

    ON un.ChaveLote = d.ChaveLote

),



uniao AS (

  SELECT * FROM controle

  UNION ALL

  SELECT * FROM sienge

)



SELECT

  u.Origem,

  u.ChaveGeral,

  u.anoPeriodoVenda,

  u.Distratos,

  u.Empreendimento,

  u.Quadra_Lote,

  u.Descricao,

  u.DataReferencia,

  DATE_TRUNC(u.DataReferencia, MONTH)            AS MesReferencia,   -- eixo X (1 barra por mes)

  EXTRACT(YEAR FROM u.DataReferencia)            AS Ano,

  u.DataLancamento,

  u.enterpriseId,

  nc.companyGroup,

  nc.companyName,

  nc.enterpriseName,

  u.Titulo,

  u.Cliente,

  u.TIPO_DE_CANCELAMENTO,

  ROUND(u.Valor_Distrato, 2)                     AS Valor_Distrato,

  ROUND(u.Valor_Total_Recebido, 2)               AS Valor_Total_Recebido,

  ROUND(u.VGV_Distrato, 2)                       AS VGV_Distrato

FROM uniao u

LEFT JOIN nome_companhias nc

  ON nc.enterpriseId = u.enterpriseId;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO contra o BI (mai/2025 a jun/2026)

-- BI Valor Distrato: mai 824 mil | jun 900 | jul 512 | ago 548 | set 813 |

--                    out 1.391 | nov 689 | dez 1.811 | jan/26 775 |

--                    fev 1.155 | mar 1.420 | abr 1.202 | mai 1.393 | jun 547

-- BI VGV Distrato  : mai 3.498 mil | jun 3.529 | jul 3.513 | ago 5.138 |

--                    set 4.765 | out 4.549 | nov 6.107 | dez 4.924 |

--                    jan/26 6.043 | fev 5.951 | mar 5.216 | abr 5.280 |

--                    mai 3.928 | jun 2.326

-- valor_distrato_por_data = mesmo valor pela coluna "Data" da planilha

--   (se este bater e o outro nao, o BI liga a planilha pela "Data")

-- ####################################################################

-- WITH v AS (

--   SELECT MesReferencia AS mes,

--          SUM(Valor_Distrato)       AS valor_distrato,

--          SUM(Valor_Total_Recebido) AS valor_total_recebido,

--          SUM(VGV_Distrato)         AS vgv_distrato

--   FROM `dadosfinanceiro-501613.looker_studio.distratos_vgv_recebido`

--   GROUP BY 1

-- ),

-- d AS (

--   SELECT DATE_TRUNC(DataLancamento, MONTH) AS mes,

--          SUM(Valor_Distrato) AS valor_distrato_por_data

--   FROM `dadosfinanceiro-501613.looker_studio.distratos_vgv_recebido`

--   WHERE Origem = 'Controle Operacoes'

--   GROUP BY 1

-- )

-- SELECT

--   v.mes,

--   ROUND(v.valor_distrato)          AS valor_distrato,

--   ROUND(d.valor_distrato_por_data) AS valor_distrato_por_data,

--   ROUND(v.valor_total_recebido)    AS valor_total_recebido,

--   ROUND(v.vgv_distrato)            AS vgv_distrato

-- FROM v

-- LEFT JOIN d ON d.mes = v.mes

-- WHERE v.mes BETWEEN DATE '2025-05-01' AND DATE '2026-06-01'

-- ORDER BY v.mes;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO grafico "Distratos por Data da Venda" (mai/2025 a jun/2026)

-- BI: mai 51 | jun 54 | jul 46 | ago 71 | set 64 | out 64 | nov 72 |

--     dez 74 | jan/26 86 | fev 83 | mar 79 | abr 66 | mai 57 | jun 40

-- ####################################################################

-- SELECT

--   MesReferencia                              AS mes,

--   SUM(Distratos)                             AS distratos,

--   SUM(IF(anoPeriodoVenda = '2025', Distratos, 0)) AS venda_2025,

--   SUM(IF(anoPeriodoVenda = '2026', Distratos, 0)) AS venda_2026

-- FROM `dadosfinanceiro-501613.looker_studio.distratos_vgv_recebido`

-- WHERE Origem = 'Sienge'

--   AND MesReferencia BETWEEN DATE '2025-05-01' AND DATE '2026-06-01'

-- GROUP BY 1

-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO tabela "Detalhamento Distratos Realizados"

-- BI (mesmo periodo do grafico): 907 distratos | Valor Recebido 15.609.669,65

--   ex.: Alta Villa Betim 8 / 206.876,99 | Cidade Verde Esmeraldas 2 / 89.099,89

--        Cidade Verde Prudente de Morais 11 / 479.384,03

-- ####################################################################

-- SELECT

--   Empreendimento,

--   SUM(Distratos)                      AS distratos,

--   MAX(DataReferencia)                 AS data_distrato,

--   MAX(Titulo)                         AS titulo,

--   ROUND(SUM(Valor_Total_Recebido), 2) AS valor_recebido

-- FROM `dadosfinanceiro-501613.looker_studio.distratos_vgv_recebido`

-- WHERE Origem = 'Sienge'

--   AND DataReferencia BETWEEN DATE '2025-05-01' AND DATE '2026-06-30'

-- GROUP BY ROLLUP(Empreendimento)

-- ORDER BY Empreendimento NULLS LAST;