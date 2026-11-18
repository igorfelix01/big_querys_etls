-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_CONTRATOS_NAO_PAGOS

--

-- Visual do BI: "Contratos nao Pagos" (colunas empilhadas)

--   Eixo X  : Calendario (mes do paymentDate; no A Receber = vencimento)

--   Eixo Y  : Contagem de SaldoDevedor[ChaveGeral]  (CONTAGEM, nao distinta

--             -> conta parcelas A Receber)

--   Legenda : SaldoDevedor[SituacaoContrato]

--   Filtro  : OrigemBase = 'A Receber'

--

-- DAX (coluna calculada no SaldoDevedor):

--   SituacaoContrato = RELATED(db_titulos_totalizador[SituacaoContrato])

--   -> LEFT JOIN com analytics.fato_titulos_totalizador por ChaveGeral

--

-- SEM limite de periodo: filtro do Looker pela coluna Mes.

-- JA FILTRADO NO SQL (conferido com o BI):

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital'

--   companyGroup em branco ('Sem grupo') FORA - igual ao grafico

--     "Valor A Receber por Ano de Venda"

--   SituacaoContrato IN ('Atrasado', 'Inadimplente')  ("nao pagos")

--

-- Looker: Dimensao = Mes | Detalhamento = SituacaoContrato |

--         Metrica = QtdParcelas (SUM) | colunas empilhadas |

--         classificar por Mes crescente | sem filtro de situacao (ja vem no SQL)

--

-- Depende de: looker_studio.recebiveis_situacao_parcela,

--             analytics.fato_titulos_totalizador (etapa 2.3)

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_contratos_nao_pagos`;-- [otimizacao] CTE 'ar' usada 10x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE ar AS
  SELECT

    s.ChaveGeral,

    s.paymentDate,

    s.documentIdentificationId,

    s.companyGroup,

    s.companyName,

    s.subJudicie,

    s.anoPeriodoVenda

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` s

  WHERE s.OrigemBase = 'A Receber'

    AND s.paymentDate IS NOT NULL

    AND s.documentIdentificationId = 'CT'

    AND s.companyGroup IS NOT NULL

    AND s.companyGroup NOT IN ('Bloko Capital', 'Sem grupo');







CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_contratos_nao_pagos`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  SituacaoContrato,

  companyGroup



AS
WITH
totalizador AS (

  SELECT

    ChaveGeral,

    SituacaoContrato

  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral ORDER BY ChaveGeral) = 1

)
SELECT

  DATE_TRUNC(ar.paymentDate, MONTH) AS Mes,



  t.SituacaoContrato,



  ar.documentIdentificationId,

  ar.companyGroup,

  ar.companyName,

  ar.subJudicie,

  ar.anoPeriodoVenda,



  -- Contagem de ChaveGeral (nao distinta, ignora ChaveGeral nula)

  COUNT(ar.ChaveGeral)          AS QtdParcelas,

  COUNT(DISTINCT ar.ChaveGeral) AS QtdContratos



FROM ar

JOIN totalizador t

  ON t.ChaveGeral = ar.ChaveGeral



WHERE t.SituacaoContrato IN ('Atrasado', 'Inadimplente')



GROUP BY 1, 2, 3, 4, 5, 6, 7;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO

-- BI: ago/24 874 | ago/25 980 | jul/26 2.098 |

--     ago/26 Atrasado 759 + Inadimplente 1.758 = 2.517

-- Banco em 30/09: ago/24 881 | ago/25 989 | jul/26 ~2.099

--   (sobra de 7 a 9 parcelas = diferenca de data de atualizacao BI x banco)

-- ####################################################################



-- SELECT

--   Mes,

--   SUM(IF(SituacaoContrato = 'Atrasado',     QtdParcelas, 0)) AS atrasado,

--   SUM(IF(SituacaoContrato = 'Inadimplente', QtdParcelas, 0)) AS inadimplente,

--   SUM(QtdParcelas)                                           AS total

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_contratos_nao_pagos`

-- WHERE Mes IN ('2024-08-01', '2025-08-01', '2026-07-01', '2026-08-01')

-- GROUP BY Mes

-- ORDER BY Mes;