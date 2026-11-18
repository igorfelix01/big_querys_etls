-- [otimizacao] CTE 'parcela' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE parcela AS
WITH
emp AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName) = 1
)
SELECT * FROM (

  SELECT
    e.companyGroup,
    DATE_TRUNC(s.dueDate, MONTH) AS M,
    s.paymentDate,
    s.OrigemBase,
    s.Conta,
    s.ValorBruto
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor` s
  JOIN emp e
    ON e.enterpriseId = SAFE_CAST(SAFE_CAST(CAST(s.costCenterId AS STRING) AS FLOAT64) AS INT64)
  WHERE s.documentIdentificationId = 'CT'
    AND s.dueDate >= DATE '2000-01-01'
    AND IFNULL(TRIM(e.companyGroup), '') <> ''
    AND e.companyGroup <> 'Bloko Capital'

);

-- [otimizacao] CTE 'taxa' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE taxa AS
WITH
hoje AS (
  SELECT
    CURRENT_DATE('America/Sao_Paulo')                    AS d,
    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual
),

comp AS (
  SELECT companyGroup, M, SUM(ValorBruto) AS valor
  FROM parcela
  GROUP BY 1, 2
),

pago AS (
  SELECT
    companyGroup,
    M,
    LEAST(GREATEST(DATE_DIFF(DATE_TRUNC(paymentDate, MONTH), M, MONTH), 0), 99) AS k,
    SUM(ValorBruto) AS valor
  FROM parcela
  WHERE OrigemBase IS NULL
    AND Conta = 'Efeito Caixa'
    AND paymentDate IS NOT NULL
  GROUP BY 1, 2, 3
),

lags AS (
  SELECT k FROM UNNEST(GENERATE_ARRAY(0, 12)) AS k
),

amostra AS (
  SELECT c.companyGroup, c.M, l.k, c.valor
  FROM comp c
  CROSS JOIN lags l
  CROSS JOIN hoje h
  WHERE c.M BETWEEN DATE_SUB(h.mes_atual, INTERVAL l.k + 12 MONTH)
                AND DATE_SUB(h.mes_atual, INTERVAL l.k + 1 MONTH)
)
SELECT * FROM (

  SELECT
    a.companyGroup,
    a.k,
    SUM(a.valor)              AS valor_amostra,
    SUM(IFNULL(p.valor, 0))   AS pago_no_k
  FROM amostra a
  LEFT JOIN pago p
    ON p.companyGroup = a.companyGroup AND p.M = a.M AND p.k = a.k
  GROUP BY 1, 2

);

-- ####################################################################
-- PROJECAO DE CAIXA: QUANTO VAI ENTRAR DE VERDADE NOS PROXIMOS 12 MESES
--
-- Pergunta: do que esta para vencer (e do que ja esta vencido), quanto
-- deve virar dinheiro em cada um dos proximos 12 meses?
-- O A Receber mostra o valor de face; esta projecao aplica o
-- comportamento real de pagamento da carteira.
--
-- 1) CURVA DE RECEBIMENTO (historico)
--    Para cada mes de vencimento (competencia), quanto % do valor entrou
--    no caixa (Conta 'Efeito Caixa') no proprio mes (0), 1 mes depois,
--    2 meses depois... ate 12. Antecipado conta no mes 0.
--    Taxa de cada atraso k = media das 12 competencias mais recentes
--    que ja tem k meses completos (curva sempre atualizada).
--
-- 2) PROJECAO
--    A vencer:   parcela que vence no mes M entra em M+k com a taxa k.
--    Vencidos:   estoque JA vencido (antes de hoje) em aberto x taxa mensal de
--                recuperacao (historico dos ultimos 12 meses fechados),
--                separado em vencido ate 90 dias e acima de 90 dias.
--                Mes n: estoque x (1 - taxa)^(n-1) x taxa.
--
--    Taxas por grupo; se o grupo tiver menos de R$ 50 mil na amostra,
--    usa a taxa da carteira inteira.
--
-- Cria:
--   looker_studio.projecao_caixa_curva
--     grupo x meses depois do vencimento -> % recebido no mes e acumulado
--   looker_studio.projecao_caixa
--     grupo x empresa x mes projetado x origem (A vencer / Vencidos ate
--     90 dias / Vencidos 90+ dias) -> ValorFace e ValorProjetado
--
-- Universo: CT, sem empresas Bloko (companyGroup via dim_nome_companhias,
-- centro de custo = enterpriseId). subJudicie vem como coluna.
-- Observacao: parcelas substituidas em renegociacao saem do A Receber e
-- nao entram na amostra.
--
-- Depende de: analytics.saldo_devedor, analytics.dim_nome_companhias
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.projecao_caixa_curva`
CLUSTER BY companyGroup
AS
WITH
taxa_geral AS (
  SELECT k, SUM(valor_amostra) AS valor_amostra, SUM(pago_no_k) AS pago_no_k
  FROM taxa
  GROUP BY 1
)
SELECT
  t.companyGroup,
  t.k                                                           AS MesesDepoisDoVencimento,
  IF(t.valor_amostra >= 50000, 'Grupo', 'Geral')                AS BaseDaTaxa,
  ROUND(IF(t.valor_amostra >= 50000,
           SAFE_DIVIDE(t.pago_no_k, t.valor_amostra),
           SAFE_DIVIDE(g.pago_no_k, g.valor_amostra)), 6)       AS TaxaNoMes,
  ROUND(SUM(IF(t.valor_amostra >= 50000,
           SAFE_DIVIDE(t.pago_no_k, t.valor_amostra),
           SAFE_DIVIDE(g.pago_no_k, g.valor_amostra))) OVER (
        PARTITION BY t.companyGroup ORDER BY t.k), 6)           AS TaxaAcumulada,
  ROUND(t.valor_amostra, 2)                                     AS ValorAmostra
FROM taxa t
JOIN taxa_geral g USING (k);-- [otimizacao] CTE 'parcela' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE parcela AS
WITH
emp AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup,
    companyName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName) = 1
)
SELECT * FROM (

  SELECT
    e.companyGroup,
    e.companyName,
    s.subJudicie,
    s.dueDate,
    s.paymentDate,
    s.OrigemBase,
    s.Conta,
    s.ValorBruto
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor` s
  JOIN emp e
    ON e.enterpriseId = SAFE_CAST(SAFE_CAST(CAST(s.costCenterId AS STRING) AS FLOAT64) AS INT64)
  WHERE s.documentIdentificationId = 'CT'
    AND s.dueDate >= DATE '2000-01-01'
    AND IFNULL(TRIM(e.companyGroup), '') <> ''
    AND e.companyGroup <> 'Bloko Capital'

);

-- [otimizacao] CTE 'estoque_hist' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE estoque_hist AS
WITH
hoje AS (
  SELECT
    CURRENT_DATE('America/Sao_Paulo')                    AS d,
    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 1 MONTH) AS prox_mes
),

meses_amostra AS (
  SELECT X
  FROM hoje h,
  UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(h.mes_atual, INTERVAL 12 MONTH),
                             DATE_SUB(h.mes_atual, INTERVAL 1 MONTH),
                             INTERVAL 1 MONTH)) AS X
)
SELECT * FROM (

  SELECT
    p.companyGroup,
    IF(p.dueDate >= DATE_SUB(m.X, INTERVAL 90 DAY),
       'Vencidos até 90 dias', 'Vencidos 90+ dias')                AS Origem,
    SUM(p.ValorBruto)                                              AS estoque,
    SUM(IF(p.OrigemBase IS NULL AND p.Conta = 'Efeito Caixa'
           AND p.paymentDate >= m.X
           AND p.paymentDate <  DATE_ADD(m.X, INTERVAL 1 MONTH),
           p.ValorBruto, 0))                                       AS recuperado
  FROM parcela p
  JOIN meses_amostra m
    ON p.dueDate < m.X
   AND (p.OrigemBase = 'A Receber' OR p.paymentDate >= m.X)
  GROUP BY 1, 2

);




-- ####################################################################
-- PROJECAO DOS PROXIMOS 12 MESES
-- ####################################################################
CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.projecao_caixa`
CLUSTER BY companyGroup, MesProjecao
AS
WITH
hoje AS (
  SELECT
    CURRENT_DATE('America/Sao_Paulo')                    AS d,
    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 1 MONTH) AS prox_mes
),

curva AS (
  SELECT companyGroup, MesesDepoisDoVencimento AS k, TaxaNoMes
  FROM `dadosfinanceiro-501613.looker_studio.projecao_caixa_curva`
),

a_vencer AS (
  SELECT
    p.companyGroup, p.companyName, p.subJudicie,
    DATE_TRUNC(p.dueDate, MONTH) AS M,
    SUM(p.ValorBruto)            AS valor
  FROM parcela p, hoje h
  WHERE p.OrigemBase = 'A Receber'
    AND p.dueDate >= h.d
  GROUP BY 1, 2, 3, 4
),

proj_a_vencer AS (
  SELECT
    a.companyGroup, a.companyName, a.subJudicie,
    DATE_ADD(a.M, INTERVAL c.k MONTH)   AS MesProjecao,
    'A vencer'                          AS Origem,
    SUM(IF(c.k = 0 AND a.M >= DATE_TRUNC(DATE_ADD(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 1 MONTH), MONTH),
           a.valor, 0))                 AS ValorFace,
    SUM(a.valor * c.TaxaNoMes)          AS ValorProjetado
  FROM a_vencer a
  JOIN curva c
    ON c.companyGroup = a.companyGroup
  GROUP BY 1, 2, 3, 4, 5
),

taxa_rec AS (
  SELECT
    e.companyGroup,
    e.Origem,
    IF(e.estoque >= 50000,
       SAFE_DIVIDE(e.recuperado, e.estoque),
       SAFE_DIVIDE(g.recuperado, g.estoque))                       AS taxa
  FROM estoque_hist e
  JOIN (SELECT Origem, SUM(estoque) AS estoque, SUM(recuperado) AS recuperado
        FROM estoque_hist GROUP BY 1) g USING (Origem)
),

estoque_hoje AS (
  SELECT
    p.companyGroup, p.companyName, p.subJudicie,
    IF(p.dueDate >= DATE_SUB(h.d, INTERVAL 90 DAY),
       'Vencidos até 90 dias', 'Vencidos 90+ dias') AS Origem,
    SUM(p.ValorBruto)                               AS estoque
  FROM parcela p, hoje h
  WHERE p.OrigemBase = 'A Receber'
    AND p.dueDate < h.d          -- so o que JA venceu e nao foi pago
  GROUP BY 1, 2, 3, 4
),

proj_vencidos AS (
  SELECT
    e.companyGroup, e.companyName, e.subJudicie,
    DATE_ADD(h.mes_atual, INTERVAL n MONTH)                     AS MesProjecao,
    e.Origem,
    IF(n = 1, e.estoque, 0)                                     AS ValorFace,
    e.estoque * POW(1 - IFNULL(t.taxa, 0), n - 1) * IFNULL(t.taxa, 0) AS ValorProjetado
  FROM estoque_hoje e
  CROSS JOIN hoje h
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, 12)) AS n
  LEFT JOIN taxa_rec t
    ON t.companyGroup = e.companyGroup AND t.Origem = e.Origem
)
SELECT
  x.companyGroup,
  x.companyName,
  x.subJudicie,
  x.MesProjecao,
  x.Origem,
  ROUND(SUM(x.ValorFace), 2)       AS ValorFace,
  ROUND(SUM(x.ValorProjetado), 2)  AS ValorProjetado,
  (SELECT d FROM hoje)             AS DataReferencia
FROM (
  SELECT * FROM proj_a_vencer
  UNION ALL
  SELECT * FROM proj_vencidos
) x
CROSS JOIN hoje h
WHERE x.MesProjecao BETWEEN h.prox_mes AND DATE_ADD(h.mes_atual, INTERVAL 12 MONTH)
GROUP BY 1, 2, 3, 4, 5;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- RESULTADO RAPIDO
-- ####################################################################

-- (1) curva da carteira: % do valor que entra ate X meses depois do vencimento
-- SELECT
--   MesesDepoisDoVencimento,
--   ROUND(100 * SAFE_DIVIDE(SUM(TaxaNoMes * ValorAmostra), SUM(ValorAmostra)), 1) AS pct_no_mes
-- FROM `dadosfinanceiro-501613.looker_studio.projecao_caixa_curva`
-- GROUP BY 1
-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (2) proximos 12 meses: valor de face x projetado
-- SELECT
--   MesProjecao,
--   ROUND(SUM(IF(Origem = 'A vencer', ValorFace, 0)))  AS a_vencer_face,
--   ROUND(SUM(ValorProjetado))                         AS entrada_projetada,
--   ROUND(SUM(IF(Origem <> 'A vencer', ValorProjetado, 0))) AS dos_vencidos
-- FROM `dadosfinanceiro-501613.looker_studio.projecao_caixa`
-- GROUP BY 1
-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (3) DE ONDE VEM A "RECUPERACAO DE ATRASADOS/INADIMPLENTES" DO 1o MES
--     estoque vencido hoje x taxa mensal de recuperacao (por grupo)
-- SELECT
--   companyGroup,
--   Origem,
--   ROUND(SUM(ValorFace))                                       AS estoque_vencido_hoje,
--   ROUND(SUM(ValorProjetado))                                  AS entra_no_1o_mes,
--   ROUND(100 * SAFE_DIVIDE(SUM(ValorProjetado), SUM(ValorFace)), 1) AS taxa_mensal_pct
-- FROM `dadosfinanceiro-501613.looker_studio.projecao_caixa`
-- WHERE Origem <> 'A vencer'
--   AND MesProjecao = DATE_TRUNC(DATE_ADD(CURRENT_DATE('America/Sao_Paulo'), INTERVAL 1 MONTH), MONTH)
-- GROUP BY 1, 2
-- ORDER BY 1, 2;