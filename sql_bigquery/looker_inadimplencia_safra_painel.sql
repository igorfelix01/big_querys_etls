-- ####################################################################
-- PAINEL DE SAFRAS (versao facil de ler da inadimplencia por safra)
--
-- Pergunta do Fabio: "quais vendas estao performando pior?"
-- 3 visuais, todos com a MESMA regra da inadimplencia_safra:
--   % inadimplencia 60+ = saldo vencido ha 60+ dias / saldo em aberto
--   % contratos 60+     = Contratos60 / Contratos
--   INADIMPLENTE = 90+ dias:
--   % parcelas 90+      = SaldoVencido90 / SaldoAberto
--   % contratos 90+     = Contratos90 / Contratos
--   % carteira 90+      = SaldoContratos90 / SaldoAberto (saldo inteiro
--                         dos contratos inadimplentes)
--   parcelas que vencem antes da data da venda ficam de fora
--   (CT, empresa pelo centro de custo, sem Bloko, sem distratados)
--
-- Agrupamento das safras igual ao da analise de recebiveis:
--   <= 2015 | 2016 - 2019 | 2020 - 2022 | 2023 | 2024 | 2025 | 2026
--   (AnoVenda continua como coluna, para quem quiser ano a ano)
--
-- Cria:
--   looker_studio.inadimplencia_safra_hoje
--     a FOTO DE HOJE de cada safra: saldo em aberto, saldo 60+ e
--     contratos (barras + cards)
--   looker_studio.inadimplencia_safra_visual
--     a mesma inadimplencia_safra, com:
--       IdadeTexto / OrdemIdade  -> marcos 6, 12, 18, 24, 36, 48, 60 meses
--                                   (matriz de calor safra x idade)
--       EhFimTrimestre / AnosDesdeVenda -> curva com 1 ponto por
--                                   trimestre (linha mais limpa)
--
-- Sem periodo fixo: filtros no Looker.
-- Depende de: looker_studio.inadimplencia_safra, analytics.saldo_devedor,
--             analytics.dim_nome_companhias
-- ####################################################################

CREATE TEMP FUNCTION grupo_safra(ano INT64) AS (
  CASE
    WHEN ano IS NULL THEN '(sem venda)'
    WHEN ano <= 2015 THEN '<= 2015'
    WHEN ano <= 2019 THEN '2016 - 2019'
    WHEN ano <= 2022 THEN '2020 - 2022'
    ELSE CAST(ano AS STRING)
  END
);

CREATE TEMP FUNCTION ordem_safra(ano INT64) AS (
  CASE
    WHEN ano IS NULL THEN 9999
    WHEN ano <= 2015 THEN 1
    WHEN ano <= 2019 THEN 2
    WHEN ano <= 2022 THEN 3
    ELSE ano
  END
);


-- ====================================================================
-- 1. CURVA E MATRIZ (a partir da inadimplencia_safra)
-- ====================================================================
DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.inadimplencia_safra_visual`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.inadimplencia_safra_visual`
CLUSTER BY GrupoSafra, companyGroup
AS
SELECT
  companyGroup,
  companyName,
  enterpriseName,
  subJudicie,
  AnoVenda,
  grupo_safra(AnoVenda)                         AS GrupoSafra,
  ordem_safra(AnoVenda)                         AS OrdemSafra,
  MesesDesdeVenda,
  ROUND(MesesDesdeVenda / 12, 2)                AS AnosDesdeVenda,
  MOD(MesesDesdeVenda, 3) = 0                   AS EhFimTrimestre,
  CASE MesesDesdeVenda
    WHEN 6  THEN '06 meses'
    WHEN 12 THEN '12 meses (1 ano)'
    WHEN 18 THEN '18 meses'
    WHEN 24 THEN '24 meses (2 anos)'
    WHEN 36 THEN '36 meses (3 anos)'
    WHEN 48 THEN '48 meses (4 anos)'
    WHEN 60 THEN '60 meses (5 anos)'
  END                                           AS IdadeTexto,
  CASE MesesDesdeVenda
    WHEN 6 THEN 1 WHEN 12 THEN 2 WHEN 18 THEN 3 WHEN 24 THEN 4
    WHEN 36 THEN 5 WHEN 48 THEN 6 WHEN 60 THEN 7
  END                                           AS OrdemIdade,
  SaldoAberto,
  SaldoVencido60,
  Contratos,
  Contratos60,
  SaldoVencido90,
  Contratos90,
  SaldoContratos90
FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_safra`;


-- ====================================================================
-- 2. FOTO DE HOJE POR SAFRA (mesma regra de parcela da inadimplencia_safra)
-- ====================================================================
DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.inadimplencia_safra_hoje`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.inadimplencia_safra_hoje`
CLUSTER BY GrupoSafra, companyGroup
AS
WITH
hoje AS (
  SELECT CURRENT_DATE('America/Sao_Paulo') AS d
),
empresa AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup,
    companyName,
    enterpriseName
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
    s.OrigemBase,
    COALESCE(CAST(s.originalAmount AS FLOAT64), CAST(s.ValorBruto AS FLOAT64)) AS valor,
    s.contractDate,
    s.cancellationDate,
    s.subJudicie,
    e.companyGroup,
    e.companyName,
    e.enterpriseName
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor` s
  JOIN empresa e
    ON e.enterpriseId = SAFE_CAST(SAFE_CAST(CAST(s.costCenterId AS STRING) AS FLOAT64) AS INT64)
  WHERE s.documentIdentificationId = 'CT'
    AND s.ChaveGeral IS NOT NULL
    AND s.ChaveEspecifica IS NOT NULL
    AND s.dueDate >= DATE '2000-01-01'
    AND IFNULL(TRIM(e.companyGroup), '') <> ''
    AND e.companyGroup <> 'Bloko Capital'
),
parcela AS (
  SELECT
    ChaveGeral,
    ChaveEspecifica,
    dueDate,
    MAX(valor)                          AS valor,
    COUNTIF(OrigemBase = 'A Receber') > 0 AS em_aberto,
    ANY_VALUE(contractDate)             AS contractDate,
    ANY_VALUE(cancellationDate)         AS cancellationDate,
    MAX(subJudicie)                     AS subJudicie,
    ANY_VALUE(companyGroup)             AS companyGroup,
    ANY_VALUE(companyName)              AS companyName,
    ANY_VALUE(enterpriseName)           AS enterpriseName
  FROM linhas
  GROUP BY 1, 2, 3
),
contrato AS (
  -- dados do contrato iguais para todas as parcelas (como na safra)
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
),
aberto AS (
  SELECT
    c.companyGroup, c.companyName, c.enterpriseName, c.subJudicie,
    EXTRACT(YEAR FROM c.venda)                              AS AnoVenda,
    p.ChaveGeral,
    p.valor,
    p.dueDate <= DATE_SUB(h.d, INTERVAL 60 DAY)            AS vencido60,
    p.dueDate <= DATE_SUB(h.d, INTERVAL 90 DAY)            AS vencido90,
    p.dueDate <  h.d                                        AS vencido
  FROM parcela p
  JOIN contrato c USING (ChaveGeral)
  CROSS JOIN hoje h
  WHERE p.em_aberto
    AND p.dueDate >= c.venda     -- parcela que vence antes da venda fica de fora
    AND c.venda IS NOT NULL
    AND c.venda <= h.d
    AND (c.distrato IS NULL OR c.distrato > h.d)
)
SELECT
  companyGroup,
  companyName,
  enterpriseName,
  subJudicie,
  AnoVenda,
  grupo_safra(AnoVenda)                                     AS GrupoSafra,
  ordem_safra(AnoVenda)                                     AS OrdemSafra,
  ROUND(SUM(valor), 2)                                      AS SaldoAberto,
  ROUND(SUM(IF(vencido60, valor, 0)), 2)                    AS SaldoVencido60,
  ROUND(SUM(IF(vencido, valor, 0)), 2)                      AS SaldoVencido,
  COUNT(DISTINCT ChaveGeral)                                AS Contratos,
  COUNT(DISTINCT IF(vencido60, ChaveGeral, NULL))           AS Contratos60,
  ROUND(SUM(IF(vencido90, valor, 0)), 2)                    AS SaldoVencido90,
  COUNT(DISTINCT IF(vencido90, ChaveGeral, NULL))           AS Contratos90,
  ROUND(SUM(IF(contrato90, valor, 0)), 2)                   AS SaldoContratos90,
  (SELECT d FROM hoje)                                      AS DataReferencia
FROM (
  SELECT *, LOGICAL_OR(vencido90) OVER (PARTITION BY ChaveGeral) AS contrato90
  FROM aberto
)
GROUP BY 1, 2, 3, 4, 5, 6, 7;


-- ####################################################################
-- CONFERENCIA (rodar na mao)
-- ####################################################################
-- hoje por safra
-- SELECT GrupoSafra, ROUND(SUM(SaldoAberto)) AS saldo, ROUND(SUM(SaldoVencido60)) AS v60,
--        ROUND(100 * SAFE_DIVIDE(SUM(SaldoVencido60), SUM(SaldoAberto)), 2) AS pct_60,
--        SUM(Contratos) AS contratos
-- FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_safra_hoje`
-- WHERE subJudicie = 'N'
-- GROUP BY 1 ORDER BY MIN(OrdemSafra);
--
-- matriz safra x idade
-- SELECT GrupoSafra, IdadeTexto,
--        ROUND(100 * SAFE_DIVIDE(SUM(SaldoVencido60), SUM(SaldoAberto)), 2) AS pct_60
-- FROM `dadosfinanceiro-501613.looker_studio.inadimplencia_safra_visual`
-- WHERE IdadeTexto IS NOT NULL AND subJudicie = 'N'
-- GROUP BY 1, 2 ORDER BY MIN(OrdemSafra), MIN(OrdemIdade);
