-- ####################################################################
-- LOOKER_STUDIO.RECEBIVEIS_CARTEIRA_ATRASADA
--
-- Visual do BI: "Carteira Atrasada e Inadimplente (R$)"
--   Eixo X  : Calendario[Ano]
--   Colunas : Inadimplente = [relativoInadimplente]
--             Atrasado     = [relativoAtrasado]
--   Linha   : Contratos Em Aberto = Contagem de db_a_receber[ChaveGeral]
--   Dica    : Valor Corrigido = [relativoCorrigido]
--
-- DAX -> REGRA
--   relativoInadimplente = VisaoCarteiraOriginal (originalAmount /
--       ValorOriginalBloko / ValorOriginalParceiro) das parcelas do
--       A Receber com dueDate <= fim do ano e situacaoInicialAR='Inadimplente'
--   relativoAtrasado     = idem com situacaoInicialAR = 'Atrasado'
--   relativoCorrigido    = VisaoCarteira (ValorBruto / ValorBloko /
--       ValorParceiro) com dueDate <= fim do ano (todas as situacoes)
--   ALLEXCEPT(documentIdentificationId, subJudicie, NomeCompanhias):
--       o acumulado SOMA DESDE O COMECO e ignora o filtro de periodo.
--       O filtro "CT" da pagina e de 'db_recebidas'[documentIdentificationId]
--       (outra tabela), entao NAO filtra o db_a_receber: Inadimplente,
--       Atrasado, Valor Corrigido e Contratos Em Aberto usam TODOS os tipos
--       de documento (CT, DL, EMP, REC, NTRI...). Conferido centro de custo
--       a centro de custo (ex.: 30100 DL 3.717.080 entra no BI).
--   Contratos Em Aberto = contratos DISTINTOS (ChaveGeral) do A Receber
--       com vencimento no ano (NAO acumulado) - conferido: 2024 = 541
--
-- Empresa: relacao do BI = db_a_receber[costCenterId] -> NomeCompanhias[enterpriseId]
--
-- PERIODO FIXO NO SQL: anos de 2010 a 2024 (pedido do usuario).
--   O acumulado de 2010 ja inclui tudo o que venceu antes de 2010.
-- No Looker: filtro de SubJudice = N (seletor do BI) fica no relatorio.
--
-- 1 linha por ANO x empresa x subjudice, com o acumulado ate 31/12 do ano
-- ja calculado (todos os anos, mesmo sem parcela vencendo no ano).
-- No Looker basta SOMA: soma entre empresas e certa; nao ha soma entre
-- meses. Filtro de periodo pelo campo Ano NAO muda o acumulado (igual BI).
--
-- JA FILTRADO: companyGroup <> 'Bloko Capital' e centro de custo sem
--   cadastro na planilha fica fora (igual ao grafico do BI).
--
-- Depende de: analytics.fato_areceber (db_a_receber),
--             analytics.dim_nome_companhias
-- ####################################################################

DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.recebiveis_carteira_atrasada`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.recebiveis_carteira_atrasada`
CLUSTER BY companyGroup, companyName
AS

WITH

-- NomeCompanhias: 1 linha por enterpriseId (chave da relacao no BI)
nome_companhias AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup,
    companyName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName
  ) = 1
),

ar AS (
  SELECT
    EXTRACT(YEAR FROM a.dueDate)                    AS Ano,
    nc.companyGroup,
    nc.companyName,
    CAST(a.subJudicie AS STRING)                    AS subJudicie,
    a.ChaveGeral,
    a.situacaoInicialAR,
    CAST(a.originalAmount        AS FLOAT64)        AS originalAmount,
    CAST(a.ValorOriginalBloko    AS FLOAT64)        AS ValorOriginalBloko,
    CAST(a.ValorOriginalParceiro AS FLOAT64)        AS ValorOriginalParceiro,
    CAST(a.ValorBruto            AS FLOAT64)        AS ValorBruto,
    CAST(a.ValorBloko            AS FLOAT64)        AS ValorBloko,
    CAST(a.ValorParceiro         AS FLOAT64)        AS ValorParceiro
  FROM `dadosfinanceiro-501613.analytics.fato_areceber` a
  LEFT JOIN nome_companhias nc
    ON nc.enterpriseId = SAFE_CAST(a.costCenterId AS INT64)
  WHERE a.dueDate IS NOT NULL                       -- todos os tipos de documento
    AND nc.companyGroup IS NOT NULL
    AND nc.companyGroup <> 'Bloko Capital'
),

-- valores de cada ano (sem acumular)
por_ano AS (
  SELECT
    Ano, companyGroup, companyName, subJudicie,
    COUNT(DISTINCT ChaveGeral) AS ContratosEmAberto,   -- contratos distintos, todos os documentos
    SUM(IF(situacaoInicialAR = 'Inadimplente', originalAmount,        0)) AS inad_bruto,
    SUM(IF(situacaoInicialAR = 'Inadimplente', ValorOriginalBloko,    0)) AS inad_bloko,
    SUM(IF(situacaoInicialAR = 'Inadimplente', ValorOriginalParceiro, 0)) AS inad_parceiro,
    SUM(IF(situacaoInicialAR = 'Atrasado',     originalAmount,        0)) AS atr_bruto,
    SUM(IF(situacaoInicialAR = 'Atrasado',     ValorOriginalBloko,    0)) AS atr_bloko,
    SUM(IF(situacaoInicialAR = 'Atrasado',     ValorOriginalParceiro, 0)) AS atr_parceiro,
    SUM(IFNULL(ValorBruto,    0)) AS corr_bruto,
    SUM(IFNULL(ValorBloko,    0)) AS corr_bloko,
    SUM(IFNULL(ValorParceiro, 0)) AS corr_parceiro
  FROM ar
  GROUP BY 1, 2, 3, 4
),

-- todos os anos de cada grupo (do 1o ano dele ate o ultimo ano da base)
limites AS (
  SELECT MAX(Ano) AS ultimo FROM por_ano
),

grade AS (
  SELECT g.companyGroup, g.companyName, g.subJudicie, ano AS Ano
  FROM (
    SELECT companyGroup, companyName, subJudicie, MIN(Ano) AS primeiro
    FROM por_ano
    GROUP BY 1, 2, 3
  ) g
  CROSS JOIN limites l
  CROSS JOIN UNNEST(GENERATE_ARRAY(g.primeiro, l.ultimo)) AS ano
),

completa AS (
  SELECT
    g.Ano, g.companyGroup, g.companyName, g.subJudicie,
    p.ContratosEmAberto,
    IFNULL(p.inad_bruto, 0) AS inad_bruto,       IFNULL(p.inad_bloko, 0) AS inad_bloko,
    IFNULL(p.inad_parceiro, 0) AS inad_parceiro,
    IFNULL(p.atr_bruto, 0) AS atr_bruto,         IFNULL(p.atr_bloko, 0) AS atr_bloko,
    IFNULL(p.atr_parceiro, 0) AS atr_parceiro,
    IFNULL(p.corr_bruto, 0) AS corr_bruto,       IFNULL(p.corr_bloko, 0) AS corr_bloko,
    IFNULL(p.corr_parceiro, 0) AS corr_parceiro
  FROM grade g
  LEFT JOIN por_ano p
    ON  p.Ano = g.Ano
    AND p.companyGroup = g.companyGroup
    AND p.companyName  IS NOT DISTINCT FROM g.companyName
    AND p.subJudicie   IS NOT DISTINCT FROM g.subJudicie
),

acumulado AS (
  SELECT
    Ano,
    DATE(Ano, 1, 1) AS DataAno,          -- para usar como dimensao de data no Looker
    companyGroup,
    companyName,
    subJudicie,

    -- linha: Contratos Em Aberto (do ano, nao acumulado)
    ContratosEmAberto,

    -- colunas: acumulado desde o comeco ate 31/12 do ano
    ROUND(SUM(inad_bruto)    OVER w, 2) AS Inadimplente_Bruto,
    ROUND(SUM(inad_bloko)    OVER w, 2) AS Inadimplente_Bloko,
    ROUND(SUM(inad_parceiro) OVER w, 2) AS Inadimplente_Parceiro,

    ROUND(SUM(atr_bruto)     OVER w, 2) AS Atrasado_Bruto,
    ROUND(SUM(atr_bloko)     OVER w, 2) AS Atrasado_Bloko,
    ROUND(SUM(atr_parceiro)  OVER w, 2) AS Atrasado_Parceiro,

    -- dica de ferramenta: Valor Corrigido acumulado
    ROUND(SUM(corr_bruto)    OVER w, 2) AS ValorCorrigido_Bruto,
    ROUND(SUM(corr_bloko)    OVER w, 2) AS ValorCorrigido_Bloko,
    ROUND(SUM(corr_parceiro) OVER w, 2) AS ValorCorrigido_Parceiro

  FROM completa
  WINDOW w AS (
    PARTITION BY companyGroup, companyName, subJudicie
    ORDER BY Ano
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )
)

-- PERIODO FIXO: 2010 a 2024 (o acumulado continua somando desde o comeco)
SELECT *
FROM acumulado
WHERE Ano BETWEEN 2010 AND 2024;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- VALIDACAO (visao Bruto, SubJudice = N) - BI atualizado em 06/10/2026:
--   2024: Inadimplente 109.211.589 | Contratos 537
--   por grupo 2024: Gran Viver 98.624.163 | Inlot 4.109.228 |
--   Macapa 1.902.371 | Reserva Ville 1.485.587 | Res. Park 2.895.978 |
--   Vista Bela 194.263
-- ####################################################################
-- SELECT
--   Ano,
--   companyGroup,
--   ROUND(SUM(Inadimplente_Bruto)) AS inadimplente,
--   SUM(ContratosEmAberto)         AS contratos_em_aberto
-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_carteira_atrasada`
-- WHERE Ano = 2024
--   AND subJudicie = 'N'
-- GROUP BY ROLLUP(Ano, companyGroup)
-- ORDER BY Ano, companyGroup;