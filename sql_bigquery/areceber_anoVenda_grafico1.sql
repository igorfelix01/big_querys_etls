-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_ARECEBER_ANO_VENDA

--

-- Visual do BI: "Valor A Receber por Ano de Venda"

--   Eixo X  : mes

--   Legenda : anoPeriodoVenda

--   Valor   : [ValorOriginal (Dinamico)]

--

-- DAX [ValorOriginal (Dinamico)]  (visao padrao = ValorBloko):

--   ValorBloko    -> SUM(SaldoDevedor[ValorBloko])

--   ValorBruto    -> SUM(SaldoDevedor[originalAmount])   <- originalAmount!

--   ValorParceiro -> SUM(SaldoDevedor[ValorParceiro])

--

-- JA FILTRADO NO SQL (premissas - conferir com os filtros do visual no BI):

--   OrigemBase = 'A Receber'           ("Valor A Receber")

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital'

--   companyGroup nao vazio (sem 'Sem grupo'): conferido - mai/25 no BI

--   = 1,1 Mi = CT A Receber sem 'Sem grupo' (1.106.050); com 'Sem grupo'

--   daria 1.363.606

--   SEM limite de periodo: o periodo e controlado pelo filtro do Looker

--   Mes = mes do paymentDate (no A Receber, paymentDate = vencimento)

--

-- companyGroup / companyName / subJudicie ficam como colunas para os

-- filtros de Empresa / subJudicie do painel.

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_areceber_ano_venda`;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_areceber_ano_venda`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  anoPeriodoVenda,

  companyGroup



AS



SELECT

  DATE_TRUNC(sd.paymentDate, MONTH) AS Mes,



  IFNULL(sd.anoPeriodoVenda, '(Em branco)') AS anoPeriodoVenda,



  -- ordem da legenda: faixas antigas primeiro, depois os anos

  CASE sd.anoPeriodoVenda

    WHEN '<= 2015'     THEN 1

    WHEN '2016 - 2019' THEN 2

    WHEN '2020 - 2022' THEN 3

    ELSE IFNULL(SAFE_CAST(sd.anoPeriodoVenda AS INT64), 9999)

  END AS OrdemAnoVenda,



  sd.companyGroup,

  sd.companyName,

  sd.subJudicie,



  ROUND(SUM(sd.ValorBloko), 2)     AS ValorOriginal_Bloko,

  ROUND(SUM(sd.originalAmount), 2) AS ValorOriginal_Bruto,

  ROUND(SUM(sd.ValorParceiro), 2)  AS ValorOriginal_Parceiro



FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` sd



WHERE sd.OrigemBase = 'A Receber'

  AND sd.documentIdentificationId = 'CT'

  AND IFNULL(sd.companyGroup, '') <> 'Bloko Capital'

  AND sd.companyGroup IS NOT NULL

  AND sd.companyGroup <> 'Sem grupo'

  AND sd.paymentDate IS NOT NULL



GROUP BY 1, 2, 3, 4, 5, 6;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO: total por mes. No print do BI a Visao e ValorBruto

-- (= originalAmount): comparar a coluna bruto_original.

-- BI: mai/25 1,1 | jun 1,0 | jul 1,0 | ago 1,1 | set 1,1 | out 1,2 |

--     nov 1,7 | dez 1,4 | jan/26 1,3 | fev 1,3 | mar 1,4 | abr 2,0 |

--     mai 1,8 | jun 1,9 | jul 2,0 | ago 2,8 | set 3,3 | out 5,9 |

--     nov 6,0 | dez 6,2 (Mi)

-- ####################################################################



-- SELECT

--   Mes,

--   ROUND(SUM(ValorOriginal_Bloko), 2)    AS bloko,

--   ROUND(SUM(ValorOriginal_Bruto), 2)    AS bruto_original,

--   ROUND(SUM(ValorOriginal_Parceiro), 2) AS parceiro

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_areceber_ano_venda`

-- GROUP BY Mes

-- ORDER BY Mes;