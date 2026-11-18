-- ####################################################################
-- LOOKER_STUDIO.INADIMPLENCIA_ANO_VENDA_MENSAL
--
-- Pergunta (Fabio): "em janeiro/2026, quanto % do que ainda esta em
-- aberto das vendas de 2023 esta inadimplente? e das vendas de 2025?"
--   -> 1 linha por safra (anoPeriodoVenda), eixo = mes do calendario.
--   Mostra quais vendas estao performando pior.
--
-- Mesma base e mesmo agrupamento do grafico "Valor A Receber por Ano de
-- Venda" (looker_studio.recebiveis_situacao_parcela):
--   CT, sem Bloko Capital, sem 'Sem grupo', anoPeriodoVenda
--   (<= 2015 | 2016 - 2019 | 2020 - 2022 | 2023 | 2024 | 2025 | 2026),
--   valor da parcela = originalAmount (Visao ValorBruto).
--
-- Para cada mes, olha a carteira no FIM do mes (no mes atual: hoje):
--   SaldoAberto       = parcelas ainda nao pagas naquela data
--                       (vencidas + a vencer), de contratos ja vendidos
--                       e nao distratados ate a data
--   SaldoVencido      = dessas, as vencidas (1+ dia de atraso)
--   SaldoInadimplente = dessas, as vencidas ha 90+ dias
--   SaldoAtrasado     = vencidas de 1 a 89 dias
-- Looker:
--   % Inadimplente = SUM(SaldoInadimplente) / SUM(SaldoAberto)
--   % Vencido      = SUM(SaldoVencido)      / SUM(SaldoAberto)
--
-- Parcelas que vencem ANTES da data da venda ficam de fora (contrato
-- cedido/transferido: criavam um pico falso, ex.: nov/2024 na Inlot).
-- Parcela = ChaveGeral + ChaveEspecifica + dueDate; paga em = ultimo
-- pagamento (se ainda esta no A Receber, nao foi paga).
-- Sem periodo fixo: o periodo e o filtro de Mes no Looker.
--
-- Calculo rapido: cada parcela entra "+valor" no mes em que comeca a
-- contar e "-valor" no mes seguinte ao ultimo mes em aberto; a soma
-- acumulada mes a mes da o saldo.
--
-- Depende de: looker_studio.recebiveis_situacao_parcela
-- ####################################################################

CREATE OR REPLACE TEMP TABLE parcela AS
SELECT
  CAST(ChaveGeral AS STRING)                                       AS ChaveGeral,
  CAST(ChaveEspecifica AS STRING)                                  AS ChaveEspecifica,
  dueDate,
  MAX(COALESCE(originalAmount, ValorBruto))                        AS valor,
  IF(COUNTIF(OrigemBase = 'A Receber') > 0, NULL, MAX(paymentDate)) AS paga_em,
  MIN(contractDate)                                                AS venda,
  MIN(cancellationDate)                                            AS distrato,
  MAX(anoPeriodoVenda)                                             AS anoPeriodoVenda,
  MAX(companyGroup)                                                AS companyGroup,
  MAX(companyName)                                                 AS companyName,
  MAX(costCenterName)                                              AS costCenterName,
  MAX(subJudicie)                                                  AS subJudicie
FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`
WHERE documentIdentificationId = 'CT'
  AND IFNULL(companyGroup, '') <> 'Bloko Capital'
  AND companyGroup IS NOT NULL
  AND companyGroup <> 'Sem grupo'
  AND ChaveGeral IS NOT NULL
  AND ChaveEspecifica IS NOT NULL
  AND dueDate IS NOT NULL
GROUP BY 1, 2, 3;


DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.inadimplencia_ano_venda_mensal`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.inadimplencia_ano_venda_mensal`
CLUSTER BY anoPeriodoVenda, companyGroup
AS
WITH
hoje AS (
  SELECT
    CURRENT_DATE('America/Sao_Paulo')                    AS d,
    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual
),

-- meses em que cada parcela conta (mes = data de referencia no fim do mes)
intervalos AS (
  SELECT
    p.companyGroup, p.companyName, p.costCenterName, p.subJudicie,
    IFNULL(p.anoPeriodoVenda, '(Em branco)') AS anoPeriodoVenda,
    p.valor,
    -- comeca no mes da venda
    DATE_TRUNC(p.venda, MONTH) AS ini,
    -- ultimo mes em aberto: antes do mes do pagamento / do distrato
    LEAST(
      h.mes_atual,
      IFNULL(DATE_SUB(DATE_TRUNC(p.paga_em,  MONTH), INTERVAL 1 MONTH), h.mes_atual),
      IFNULL(DATE_SUB(DATE_TRUNC(p.distrato, MONTH), INTERVAL 1 MONTH), h.mes_atual)
    ) AS fim,
    -- 1+ dia de atraso: fim do mes > vencimento (no mes atual: hoje > vencimento)
    IF(DATE_TRUNC(DATE_ADD(p.dueDate, INTERVAL 1 DAY), MONTH) = h.mes_atual
         AND DATE_ADD(p.dueDate, INTERVAL 1 DAY) > h.d,
       DATE_ADD(h.mes_atual, INTERVAL 1 MONTH),
       DATE_TRUNC(DATE_ADD(p.dueDate, INTERVAL 1 DAY), MONTH))   AS ini_vencido,
    -- 90+ dias de atraso
    IF(DATE_TRUNC(DATE_ADD(p.dueDate, INTERVAL 90 DAY), MONTH) = h.mes_atual
         AND DATE_ADD(p.dueDate, INTERVAL 90 DAY) > h.d,
       DATE_ADD(h.mes_atual, INTERVAL 1 MONTH),
       DATE_TRUNC(DATE_ADD(p.dueDate, INTERVAL 90 DAY), MONTH))  AS ini_90
  FROM parcela p, hoje h
  WHERE p.venda IS NOT NULL
    AND p.venda <= h.d
    AND p.dueDate >= p.venda     -- parcela que vence antes da venda fica de fora
),

iv AS (
  SELECT
    * EXCEPT (ini_vencido, ini_90),
    GREATEST(ini, ini_vencido) AS ini_v,
    GREATEST(ini, ini_90)      AS ini_9
  FROM intervalos
  WHERE fim >= ini
),

deltas AS (
  SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda,
         ini AS Mes, valor AS d_aberto, 0.0 AS d_venc, 0.0 AS d_90
  FROM iv
  UNION ALL
  SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda,
         DATE_ADD(fim, INTERVAL 1 MONTH), -valor, 0.0, 0.0
  FROM iv
  UNION ALL
  SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda,
         ini_v, 0.0, valor, 0.0
  FROM iv WHERE ini_v <= fim
  UNION ALL
  SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda,
         DATE_ADD(fim, INTERVAL 1 MONTH), 0.0, -valor, 0.0
  FROM iv WHERE ini_v <= fim
  UNION ALL
  SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda,
         ini_9, 0.0, 0.0, valor
  FROM iv WHERE ini_9 <= fim
  UNION ALL
  SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda,
         DATE_ADD(fim, INTERVAL 1 MONTH), 0.0, 0.0, -valor
  FROM iv WHERE ini_9 <= fim
),

por_mes AS (
  SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda, Mes,
         SUM(d_aberto) AS d_aberto, SUM(d_venc) AS d_venc, SUM(d_90) AS d_90
  FROM deltas
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- todos os meses do primeiro ate o mes atual de cada grupo
grade AS (
  SELECT g.companyGroup, g.companyName, g.costCenterName, g.subJudicie, g.anoPeriodoVenda, Mes
  FROM (
    SELECT companyGroup, companyName, costCenterName, subJudicie, anoPeriodoVenda,
           MIN(Mes) AS mes_ini
    FROM por_mes
    GROUP BY 1, 2, 3, 4, 5
  ) g
  CROSS JOIN hoje h,
  UNNEST(GENERATE_DATE_ARRAY(g.mes_ini, h.mes_atual, INTERVAL 1 MONTH)) AS Mes
),

acumulado AS (
  SELECT
    gr.companyGroup, gr.companyName, gr.costCenterName, gr.subJudicie, gr.anoPeriodoVenda, gr.Mes,
    SUM(IFNULL(p.d_aberto, 0)) OVER w AS SaldoAberto,
    SUM(IFNULL(p.d_venc, 0))   OVER w AS SaldoVencido,
    SUM(IFNULL(p.d_90, 0))     OVER w AS SaldoInadimplente
  FROM grade gr
  LEFT JOIN por_mes p
    ON  p.companyGroup = gr.companyGroup
    AND IFNULL(p.companyName, '')    = IFNULL(gr.companyName, '')
    AND IFNULL(p.costCenterName, '') = IFNULL(gr.costCenterName, '')
    AND IFNULL(p.subJudicie, '')     = IFNULL(gr.subJudicie, '')
    AND p.anoPeriodoVenda = gr.anoPeriodoVenda
    AND p.Mes = gr.Mes
  WINDOW w AS (
    PARTITION BY gr.companyGroup, gr.companyName, gr.costCenterName, gr.subJudicie, gr.anoPeriodoVenda
    ORDER BY gr.Mes
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)

SELECT
  Mes,
  anoPeriodoVenda,
  -- ordem da legenda: faixas antigas primeiro, depois os anos
  CASE anoPeriodoVenda
    WHEN '<= 2015'     THEN 1
    WHEN '2016 - 2019' THEN 2
    WHEN '2020 - 2022' THEN 3
    ELSE IFNULL(SAFE_CAST(anoPeriodoVenda AS INT64), 9999)
  END                                                AS OrdemAnoVenda,
  companyGroup,
  companyName,
  costCenterName,
  subJudicie,
  ROUND(SaldoAberto, 2)                              AS SaldoAberto,
  ROUND(SaldoVencido, 2)                             AS SaldoVencido,
  ROUND(SaldoInadimplente, 2)                        AS SaldoInadimplente,
  ROUND(SaldoVencido - SaldoInadimplente, 2)         AS SaldoAtrasado,
  ROUND(SaldoAberto - SaldoVencido, 2)               AS SaldoAVencer
FROM acumulado
WHERE ROUND(SaldoAberto, 2) <> 0;


-- ####################################################################
-- CONFERENCIA (rodar na mao): % inadimplente por safra, ultimos 12 meses
-- ####################################################################
-- SELECT
--   Mes,
--   anoPeriodoVenda,
--   ROUND(SUM(SaldoAberto), 2)                                         AS saldo_aberto,
--   ROUND(SUM(SaldoInadimplente), 2)                                   AS inadimplente_90,
--   ROUND(100 * SAFE_DIVIDE(SUM(SaldoInadimplente), SUM(SaldoAberto)), 2) AS pct_inadimplente,
--   ROUND(100 * SAFE_DIVIDE(SUM(SaldoVencido), SUM(SaldoAberto)), 2)      AS pct_vencido
-- FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_ano_venda_mensal`
-- WHERE Mes >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 11 MONTH)
-- GROUP BY 1, 2
-- ORDER BY 1, 2;
