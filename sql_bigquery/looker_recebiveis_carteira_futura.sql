-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_CARTEIRA_FUTURA

--

-- Visual do BI: "Carteira Futura (R$)"

--   Eixo X  : ano do vencimento (DatasFuturas, relacionada ao dueDate)

--   Colunas empilhadas por situacao do CONTRATO:

--     Adimplente   = [ARFuturoAdimplente]

--     Atrasado     = [ARFuturoAtrasado]

--     Inadimplente = [ARFuturoInadimplente]

--   Filtro do visual: Ano < 2041

--

-- DAX -> REGRA

--   VisaoCarteira (ValorBruto / ValorBloko / ValorParceiro) das parcelas do

--   A Receber com dueDate > MAX(Calendario[Date]) (= fim do periodo do

--   seletor de datas), separadas por db_a_receber[SituacaoContrato]

--   (= situacao do contrato no db_titulos_totalizador, via ChaveGeral).

--   ALLEXCEPT(documentIdentificationId, subJudicie, ChaveGeral,

--             NomeCompanhias, DatasFuturas):

--     - o filtro "CT" da pagina e de 'db_recebidas' -> NAO filtra o A Receber

--       (entram todos os tipos de documento, igual a Carteira Atrasada)

--     - respeita subJudicie (seletor N), empresa (NomeCompanhias pelo

--       costCenterId) e o ano do vencimento.

--

-- DATA DE CORTE ("futuro" = vencimento depois dela):

--   no BI e o fim do periodo do seletor (hoje: 01/06/2026).

--   Aqui: HOJE (CURRENT_DATE), para a carteira futura andar sozinha.

--   Para ficar identico ao BI com o periodo fixo, troque a linha

--   DECLARE abaixo por:  DECLARE data_corte DATE DEFAULT DATE '2026-06-01';

--

-- Empresa: db_a_receber[costCenterId] -> NomeCompanhias[enterpriseId];

--   sem Bloko Capital; centro de custo sem cadastro fica fora.

-- SEM limite de ano no SQL: o filtro Ano < 2041 fica no Looker.

--

-- Depende de: analytics.fato_areceber, analytics.fato_titulos_totalizador,

--             analytics.dim_nome_companhias

-- ####################################################################



DECLARE data_corte DATE DEFAULT CURRENT_DATE('America/Sao_Paulo');



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_carteira_futura`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_carteira_futura`

CLUSTER BY companyGroup, SituacaoContrato

AS



WITH



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



situacao AS (

  SELECT ChaveGeral, ANY_VALUE(SituacaoContrato) AS SituacaoContrato

  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

  GROUP BY ChaveGeral

)



SELECT

  EXTRACT(YEAR FROM a.dueDate)                AS Ano,

  -- sem campo de DATA de proposito: assim o controle de Periodo da pagina

  -- do Looker nao filtra este grafico (a carteira futura nao depende dele)

  FORMAT_DATE('%d/%m/%Y', data_corte)         AS DataCorte,

  nc.companyGroup,

  nc.companyName,

  CAST(a.subJudicie AS STRING)                AS subJudicie,

  s.SituacaoContrato,



  COUNT(DISTINCT a.ChaveGeral)                AS Contratos,

  COUNT(*)                                    AS Parcelas,



  ROUND(SUM(CAST(a.ValorBruto    AS FLOAT64)), 2) AS Valor_Bruto,

  ROUND(SUM(CAST(a.ValorBloko    AS FLOAT64)), 2) AS Valor_Bloko,

  ROUND(SUM(CAST(a.ValorParceiro AS FLOAT64)), 2) AS Valor_Parceiro



FROM `dadosfinanceiro-501613.analytics.fato_areceber` a

JOIN nome_companhias nc

  ON nc.enterpriseId = SAFE_CAST(a.costCenterId AS INT64)

LEFT JOIN situacao s

  ON s.ChaveGeral = a.ChaveGeral

WHERE a.dueDate > data_corte                 -- todos os tipos de documento

  -- o BI so tem as 3 medidas (Adimplente / Atrasado / Inadimplente)

  AND s.SituacaoContrato IN ('Adimplente', 'Atrasado', 'Inadimplente')

  AND nc.companyGroup IS NOT NULL

  AND nc.companyGroup <> 'Bloko Capital'

GROUP BY 1, 2, 3, 4, 5, 6;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO contra o BI (corte FIXO 01/06/2026 como no seletor do BI,

-- SubJudice = N, visao Bruto) - calcula direto das tabelas de origem

-- BI: 2026 16,80 Mi | 2027 68,50 | 2028 62,06 | 2029 56,44 | 2030 52,13

--     2031 47,15 | 2032 44,72 | 2033 40,25 | 2034 36,22 | 2035 ~

--     2036 26,30 | 2037 20,17 | 2038 15,08 | 2039 11,45 | 2040 8,52

-- ####################################################################

-- WITH nc AS (

--   SELECT SAFE_CAST(enterpriseId AS INT64) AS enterpriseId, companyGroup

--   FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

--   WHERE enterpriseId IS NOT NULL

--   QUALIFY ROW_NUMBER() OVER (PARTITION BY SAFE_CAST(enterpriseId AS INT64)

--                              ORDER BY companyGroup) = 1

-- ),

-- s AS (

--   SELECT ChaveGeral, ANY_VALUE(SituacaoContrato) AS SituacaoContrato

--   FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

--   GROUP BY ChaveGeral

-- )

-- SELECT

--   EXTRACT(YEAR FROM a.dueDate) AS Ano,

--   ROUND(SUM(IF(s.SituacaoContrato = 'Adimplente',   CAST(a.ValorBruto AS FLOAT64), 0))) AS adimplente,

--   ROUND(SUM(IF(s.SituacaoContrato = 'Atrasado',     CAST(a.ValorBruto AS FLOAT64), 0))) AS atrasado,

--   ROUND(SUM(IF(s.SituacaoContrato = 'Inadimplente', CAST(a.ValorBruto AS FLOAT64), 0))) AS inadimplente,

--   ROUND(SUM(CAST(a.ValorBruto AS FLOAT64)))                                              AS total

-- FROM `dadosfinanceiro-501613.analytics.fato_areceber` a

-- JOIN nc ON nc.enterpriseId = SAFE_CAST(a.costCenterId AS INT64)

-- LEFT JOIN s ON s.ChaveGeral = a.ChaveGeral

-- WHERE a.dueDate > DATE '2026-06-01'

--   AND a.subJudicie = 'N'

--   AND nc.companyGroup <> 'Bloko Capital'

--   AND EXTRACT(YEAR FROM a.dueDate) < 2041

-- GROUP BY Ano

-- ORDER BY Ano;