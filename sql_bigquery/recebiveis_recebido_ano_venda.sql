-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_RECEBIDO_ANO_VENDA

--

-- Visual do BI: "Valor Recebido por Ano de Venda"

--   Eixo X  : mes (Calendario -> paymentDate)

--   Legenda : anoPeriodoVenda

--   Valor   : [VisaoRecebiveis]

--

-- DAX [VisaoRecebiveis]:

--   ValorBruto    -> SUM(ValorBruto)    com Conta = "Efeito Caixa"

--   ValorBloko    -> SUM(ValorBloko)    com Conta = "Efeito Caixa"

--   ValorParceiro -> SUM(ValorParceiro) com Conta = "Efeito Caixa"

--

-- JA FILTRADO NO SQL (mesmos filtros de pagina do grafico mensal):

--   Conta = 'Efeito Caixa'  (dentro da propria medida)

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital'   ('Sem grupo' ENTRA, igual ao BI)

--   SEM limite de periodo: filtro do Looker pela coluna Mes

--

-- Os totais por mes devem ser iguais ao grafico "Valor Recebido vs.

-- Previsto - Mensal" (ex.: jul/26 6.464.408 | ago/26 5.148.311).

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_recebido_ano_venda`;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_recebido_ano_venda`



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



  ROUND(SUM(sd.ValorBruto), 2)    AS ValorRecebido_Bruto,

  ROUND(SUM(sd.ValorBloko), 2)    AS ValorRecebido_Bloko,

  ROUND(SUM(sd.ValorParceiro), 2) AS ValorRecebido_Parceiro



FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` sd



WHERE sd.OrigemBase = 'Recebidas'

  AND sd.Conta = 'Efeito Caixa'

  AND sd.documentIdentificationId = 'CT'

  AND IFNULL(sd.companyGroup, '') <> 'Bloko Capital'

  AND sd.paymentDate IS NOT NULL



GROUP BY 1, 2, 3, 4, 5, 6;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO: total por mes (visao Bruto)

-- BI: mai/25 5,1 | jun 5,2 | jul 5,5 | ago 5,6 | set 5,6 | out 5,0 |

--     nov 4,2 | dez 5,7 | jan/26 4,8 | fev 4,3 | mar 5,2 | abr 3,8 |

--     mai 3,6 | jun 4,1 | jul 6,5 | ago 5,1 | set 4,1 (Mi)

-- ####################################################################



-- SELECT

--   Mes,

--   ROUND(SUM(ValorRecebido_Bruto), 2)    AS bruto,

--   ROUND(SUM(ValorRecebido_Bloko), 2)    AS bloko,

--   ROUND(SUM(ValorRecebido_Parceiro), 2) AS parceiro

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_recebido_ano_venda`

-- WHERE Mes >= '2025-05-01'

-- GROUP BY Mes

-- ORDER BY Mes;