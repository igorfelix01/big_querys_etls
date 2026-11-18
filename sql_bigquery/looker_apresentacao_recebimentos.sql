-- ####################################################################

-- LOOKER_STUDIO.APRESENTACAO_RECEBIMENTOS

-- Pagina Apresentacao:

--   1. grafico colunas empilhadas  "Recebiveis" por mes x companyGroup

--   2. barras "Recebimento 2025 - R$" (2025_YTD_Comparativo) + Total

--   3. barras "Recebimento 2026 - R$" (2026YTD)              + Total

--

-- DAX -> REGRA

--   VisaoRecebiveis = SUM(SaldoDevedor[ValorBruto | ValorBloko |

--                     ValorParceiro]) com SaldoDevedor[Conta] = "Efeito Caixa"

--   Recebiveis      = VisaoRecebiveis com

--                     SaldoDevedor[NumeroDiaDaSemana] (= dia do mes do

--                     pagamento) <= dia escolhido em CalendarioDiasUteis

--   2025_YTD        = 01/01/2025 ate o mesmo dia/mes do FIM do periodo

--   2026YTD         = pagamentos de 2026 ate hoje (respeita o periodo)

--

-- Empresa: SaldoDevedor[costCenterId] -> NomeCompanhias[enterpriseId]

-- JA FILTRADO (filtros da pagina):

--   Conta = Efeito Caixa  (a medida so soma Efeito Caixa)

--   companyGroup nao e Bloko Capital e nao e em branco

-- No Looker: filtro documentIdentificationId = CT.

--

-- SEM periodo no SQL. Campos de data:

--   MesAnoPagamento      -> EIXO X do grafico de colunas (ja e o mes)

--   DataPagamento        -> dimensao de PERIODO (controle de periodo)

--   DataPagamentoMais1Ano-> Recebimento 2025: com o periodo da pagina,

--                           mostra o mesmo trecho 1 ano antes

--                           (ex.: periodo ate 31/07/2026 -> 2025 ate 31/07/2025)

--

-- SituacaoParcelaVisual (Adimplente, Atrasado, Inadimplente, Antecipado,

--   Quitacao, Venda a vista, Ato): para os graficos "Recebimento 2025/2026"

--   por SITUACAO. Vem da looker_studio.recebiveis_situacao_parcela, que tem

--   as MESMAS linhas do saldo_devedor (so acrescenta a classificacao);

--   valores, filtros e empresa continuam iguais.

--

-- Depende de: looker_studio.recebiveis_situacao_parcela (saldo_devedor

--             classificado), analytics.dim_nome_companhias

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos`

CLUSTER BY companyGroup, documentIdentificationId, SituacaoParcelaVisual

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

)



SELECT

  SAFE_CAST(sd.paymentDate AS DATE)                              AS DataPagamento,

  DATE_TRUNC(SAFE_CAST(sd.paymentDate AS DATE), MONTH)           AS MesAnoPagamento,   -- eixo X do grafico (1 barra por mes)

  DATE_ADD(SAFE_CAST(sd.paymentDate AS DATE), INTERVAL 1 YEAR)   AS DataPagamentoMais1Ano,

  EXTRACT(YEAR  FROM SAFE_CAST(sd.paymentDate AS DATE))          AS AnoPagamento,

  EXTRACT(MONTH FROM SAFE_CAST(sd.paymentDate AS DATE))          AS MesPagamento,

  EXTRACT(DAY   FROM SAFE_CAST(sd.paymentDate AS DATE))          AS NumeroDiaDaSemana,  -- dia do mes (igual BI)



  nc.companyGroup,

  nc.companyName,

  nc.enterpriseName,



  CAST(sd.documentIdentificationId AS STRING)                    AS documentIdentificationId,

  CAST(sd.subJudicie AS STRING)                                  AS subJudicie,

  -- igual ao saldo_devedor: recebidas = NULL

  IF(sd.OrigemBase = 'Recebidas', NULL, sd.OrigemBase)          AS OrigemBase,

  sd.SituacaoParcelaVisual,



  ROUND(SUM(CAST(sd.ValorBruto     AS FLOAT64)), 2)              AS Valor_Bruto,

  ROUND(SUM(CAST(sd.ValorBloko     AS FLOAT64)), 2)              AS Valor_Bloko,

  ROUND(SUM(CAST(sd.ValorParceiro  AS FLOAT64)), 2)              AS Valor_Parceiro



FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` sd

JOIN nome_companhias nc

  ON nc.enterpriseId = SAFE_CAST(sd.costCenterId AS INT64)

WHERE sd.Conta = 'Efeito Caixa'

  AND sd.paymentDate IS NOT NULL

  AND nc.companyGroup IS NOT NULL

  AND TRIM(nc.companyGroup) <> ''

  AND nc.companyGroup <> 'Bloko Capital'

GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13;

-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:

--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]







-- ####################################################################

-- VALIDACAO contra o BI (CT, visao Bruto)

-- BI grafico: 2025 mai 5.123.882 | jun 5.185.961 | jul 5.514.499 |

--             ago 5.555.450 | set 5.621.033 | out 5.003.959 |

--             nov 4.180.335 | dez 5.657.033

--             2026 jan 4.834.297 | fev 4.327.640 | mar 5.159.994 |

--             abr 3.752.797 | mai 3.589.005 | jun 4.120.854 | jul 6.464.408

-- BI Recebimento 2025 (ate 31/07/2025): 35.244.236

-- BI Recebimento 2026 (jan-jul/2026)  : 32.248.993

-- ####################################################################

-- SELECT

--   DATE_TRUNC(DataPagamento, MONTH) AS mes,

--   ROUND(SUM(Valor_Bruto))          AS recebiveis

-- FROM `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos`

-- WHERE documentIdentificationId = 'CT'

--   AND DataPagamento BETWEEN DATE '2025-01-01' AND DATE '2026-07-31'

-- GROUP BY mes

-- UNION ALL

-- SELECT DATE '2025-12-31', ROUND(SUM(Valor_Bruto))   -- linha "2025-12-31" = total 2025 ate 31/07

-- FROM `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos`

-- WHERE documentIdentificationId = 'CT'

--   AND DataPagamento BETWEEN DATE '2025-01-01' AND DATE '2025-07-31'

-- UNION ALL

-- SELECT DATE '2026-12-31', ROUND(SUM(Valor_Bruto))   -- linha "2026-12-31" = total 2026 jan-jul

-- FROM `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos`

-- WHERE documentIdentificationId = 'CT'

--   AND DataPagamento BETWEEN DATE '2026-01-01' AND DATE '2026-07-31'

-- ORDER BY mes;





-- ####################################################################

-- CONFERENCIA (rodar na mao): recebido por situacao em 2025 e 2026 (CT)

-- ####################################################################

-- SELECT AnoPagamento, SituacaoParcelaVisual, ROUND(SUM(Valor_Bruto)) AS valor

-- FROM `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos`

-- WHERE documentIdentificationId = 'CT' AND AnoPagamento IN (2025, 2026)

-- GROUP BY 1, 2

-- ORDER BY 1, 3 DESC;