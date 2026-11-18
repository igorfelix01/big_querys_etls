-- meses completos desde a venda ate a data d (data da venda + k meses <= d)
CREATE TEMP FUNCTION meses_completos(venda DATE, d DATE) AS (
  IF(DATE_ADD(venda, INTERVAL DATE_DIFF(d, venda, MONTH) MONTH) > d,
     DATE_DIFF(d, venda, MONTH) - 1,
     DATE_DIFF(d, venda, MONTH))
);

CREATE OR REPLACE TEMP TABLE parcela AS
WITH
empresa AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup, companyName, enterpriseName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName) = 1
),
linhas AS (
  SELECT
    CAST(s.ChaveGeral AS STRING)       AS ChaveGeral,
    CAST(s.ChaveEspecifica AS STRING)  AS ChaveEspecifica,
    s.dueDate,
    s.paymentDate,
    s.OrigemBase,
    COALESCE(CAST(s.originalAmount AS FLOAT64), CAST(s.ValorBruto AS FLOAT64)) AS valor,
    s.contractDate,
    s.cancellationDate,
    s.subJudicie,
    e.companyGroup, e.companyName, e.enterpriseName
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor` s
  JOIN empresa e
    ON e.enterpriseId = SAFE_CAST(SAFE_CAST(CAST(s.costCenterId AS STRING) AS FLOAT64) AS INT64)
  WHERE s.documentIdentificationId = 'CT'
    AND s.ChaveGeral IS NOT NULL
    AND s.ChaveEspecifica IS NOT NULL
    AND s.dueDate >= DATE '2000-01-01'
    AND IFNULL(TRIM(e.companyGroup), '') <> ''
    AND e.companyGroup <> 'Bloko Capital'
)
SELECT
  ChaveGeral,
  ChaveEspecifica,
  dueDate,
  MAX(valor)                                                       AS valor,
  IF(COUNTIF(OrigemBase = 'A Receber') > 0, NULL, MAX(paymentDate)) AS paga_em,
  ANY_VALUE(contractDate)                                          AS contractDate,
  ANY_VALUE(cancellationDate)                                      AS cancellationDate,
  MAX(subJudicie)                                                  AS subJudicie,
  ANY_VALUE(companyGroup)                                          AS companyGroup,
  ANY_VALUE(companyName)                                           AS companyName,
  ANY_VALUE(enterpriseName)                                        AS enterpriseName
FROM linhas
GROUP BY 1, 2, 3;

-- dados do contrato e ultima idade observada
CREATE OR REPLACE TEMP TABLE contrato_obs AS
WITH
hoje AS (SELECT CURRENT_DATE('America/Sao_Paulo') AS d),
contrato AS (
  SELECT
    ChaveGeral,
    ANY_VALUE(contractDate)     AS venda,
    ANY_VALUE(cancellationDate) AS distrato,
    MAX(subJudicie)             AS subJudicie,
    ANY_VALUE(companyGroup)     AS companyGroup,
    ANY_VALUE(companyName)      AS companyName,
    ANY_VALUE(enterpriseName)   AS enterpriseName
  FROM parcela
  GROUP BY 1
)
SELECT
  c.*,
  meses_completos(c.venda,
    LEAST(h.d, IFNULL(DATE_SUB(c.distrato, INTERVAL 1 DAY), h.d))) AS k_max
FROM contrato c, hoje h
WHERE c.venda IS NOT NULL
  AND c.venda <= h.d;

-- intervalo de idades em que cada parcela conta
CREATE OR REPLACE TEMP TABLE intervalos AS
SELECT
  o.ChaveGeral,
  o.companyGroup, o.companyName, o.enterpriseName, o.subJudicie,
  EXTRACT(YEAR FROM o.venda) AS AnoVenda,
  p.valor,
  o.k_max,
  IF(p.paga_em IS NULL, o.k_max,
     LEAST(o.k_max, meses_completos(o.venda, DATE_SUB(p.paga_em, INTERVAL 1 DAY)))) AS fim_aberto,
  GREATEST(1, meses_completos(o.venda, DATE_ADD(p.dueDate, INTERVAL 59 DAY)) + 1)   AS ini_60
FROM parcela p
JOIN contrato_obs o USING (ChaveGeral)
WHERE o.k_max >= 1
  AND p.dueDate >= o.venda;      -- parcela que vence antes da venda fica de fora

-- idades em que o CONTRATO tem pelo menos 1 parcela com 60+
CREATE OR REPLACE TEMP TABLE contrato_60 AS
WITH
p60 AS (
  SELECT ChaveGeral, companyGroup, companyName, enterpriseName, subJudicie, AnoVenda,
         ini_60 AS ini, fim_aberto AS fim
  FROM intervalos
  WHERE ini_60 <= fim_aberto
),
marcado AS (
  SELECT
    *,
    IF(MAX(fim) OVER (PARTITION BY ChaveGeral ORDER BY ini, fim
                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) >= ini - 1,
       0, 1) AS novo
  FROM p60
),
ilha AS (
  SELECT *, SUM(novo) OVER (PARTITION BY ChaveGeral ORDER BY ini, fim
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS id_ilha
  FROM marcado
)
SELECT
  ChaveGeral,
  ANY_VALUE(companyGroup)   AS companyGroup,
  ANY_VALUE(companyName)    AS companyName,
  ANY_VALUE(enterpriseName) AS enterpriseName,
  ANY_VALUE(subJudicie)     AS subJudicie,
  ANY_VALUE(AnoVenda)       AS AnoVenda,
  MIN(ini)                  AS ini,
  MAX(fim)                  AS fim
FROM ilha
GROUP BY ChaveGeral, id_ilha;

-- "+ valor" quando comeca a contar e "- valor" no mes seguinte ao fim
CREATE OR REPLACE TEMP TABLE por_k AS
WITH
deltas AS (
  SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda,
         1 AS k, valor AS d_aberto, 0.0 AS d_60, 0 AS d_contratos, 0 AS d_c60
  FROM intervalos WHERE fim_aberto >= 1
  UNION ALL
  SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda,
         fim_aberto + 1, -valor, 0.0, 0, 0
  FROM intervalos WHERE fim_aberto >= 1
  UNION ALL
  SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda,
         ini_60, 0.0, valor, 0, 0
  FROM intervalos WHERE ini_60 <= fim_aberto
  UNION ALL
  SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda,
         fim_aberto + 1, 0.0, -valor, 0, 0
  FROM intervalos WHERE ini_60 <= fim_aberto
  UNION ALL
  SELECT companyGroup, companyName, enterpriseName, subJudicie,
         EXTRACT(YEAR FROM venda), 1, 0.0, 0.0, 1, 0
  FROM contrato_obs WHERE k_max >= 1
  UNION ALL
  SELECT companyGroup, companyName, enterpriseName, subJudicie,
         EXTRACT(YEAR FROM venda), k_max + 1, 0.0, 0.0, -1, 0
  FROM contrato_obs WHERE k_max >= 1
  UNION ALL
  SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda,
         ini, 0.0, 0.0, 0, 1
  FROM contrato_60
  UNION ALL
  SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda,
         fim + 1, 0.0, 0.0, 0, -1
  FROM contrato_60
)
SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda, k,
       SUM(d_aberto) AS d_aberto, SUM(d_60) AS d_60,
       SUM(d_contratos) AS d_contratos, SUM(d_c60) AS d_c60
FROM deltas
GROUP BY 1, 2, 3, 4, 5, 6;

DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.inadimplencia_safra`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.inadimplencia_safra`
CLUSTER BY companyGroup, AnoVenda
AS
WITH
grade AS (
  SELECT g.companyGroup, g.companyName, g.enterpriseName, g.subJudicie, g.AnoVenda, k
  FROM (
    SELECT companyGroup, companyName, enterpriseName, subJudicie, AnoVenda, MAX(k) - 1 AS k_fim
    FROM por_k
    GROUP BY 1, 2, 3, 4, 5
  ) g,
  UNNEST(GENERATE_ARRAY(1, GREATEST(g.k_fim, 1))) AS k
),
acumulado AS (
  SELECT
    gr.companyGroup, gr.companyName, gr.enterpriseName, gr.subJudicie, gr.AnoVenda, gr.k,
    SUM(IFNULL(p.d_aberto, 0))    OVER w AS SaldoAberto,
    SUM(IFNULL(p.d_60, 0))        OVER w AS SaldoVencido60,
    SUM(IFNULL(p.d_contratos, 0)) OVER w AS Contratos,
    SUM(IFNULL(p.d_c60, 0))       OVER w AS Contratos60
  FROM grade gr
  LEFT JOIN por_k p
    ON  p.companyGroup = gr.companyGroup
    AND IFNULL(p.companyName, '')    = IFNULL(gr.companyName, '')
    AND IFNULL(p.enterpriseName, '') = IFNULL(gr.enterpriseName, '')
    AND IFNULL(p.subJudicie, '')     = IFNULL(gr.subJudicie, '')
    AND p.AnoVenda = gr.AnoVenda
    AND p.k = gr.k
  WINDOW w AS (
    PARTITION BY gr.companyGroup, gr.companyName, gr.enterpriseName, gr.subJudicie, gr.AnoVenda
    ORDER BY gr.k
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  companyGroup,
  companyName,
  enterpriseName,
  subJudicie,
  AnoVenda,
  CONCAT('Safra ', CAST(AnoVenda AS STRING))   AS Safra,
  DATE(AnoVenda, 1, 1)                         AS DataVenda,
  k                                            AS MesesDesdeVenda,
  ROUND(SaldoAberto, 2)                        AS SaldoAberto,
  ROUND(SaldoVencido60, 2)                     AS SaldoVencido60,
  Contratos,
  Contratos60
FROM acumulado
WHERE Contratos > 0;