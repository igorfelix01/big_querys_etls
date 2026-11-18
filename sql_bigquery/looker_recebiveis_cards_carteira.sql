-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_CARDS_CARTEIRA

-- Cards da pagina Carteira do BI - refeito a partir das DAX:

--

--   "Valor Atrasado / Inadimplente"  (TotalAdimplente / TotalAtrasado /

--                                     TotalInadimplente / ValorPassadoTotal)

--     VisaoCarteiraOriginal (originalAmount / ValorOriginalBloko /

--     ValorOriginalParceiro), parcelas com originalAmount <> 0,

--     por situacaoInicialAR (situacao da PARCELA).

--     TOTAL = Atrasado + Inadimplente  (o Adimplente NAO entra no total)

--     BI: vencidas ANTES do fim do periodo.

--

--   "Valor Presente"  (ARFuturoAdP / ARFuturoAtP / ARFuturoIdP / Total)

--     VisaoCarteiraPresente (ValorPresente / ValorPresenteBloko /

--     ValorPresenteParceiro), por SituacaoContrato (situacao do CONTRATO).

--     TOTAL = Adimplente + Atrasado + Inadimplente

--     BI: vencem DEPOIS do fim do periodo.

--

--   "Valor Futuro"  (ARFuturoAdimplente / Atrasado / Inadimplente / Total)

--     VisaoCarteira (ValorBruto / ValorBloko / ValorParceiro),

--     por SituacaoContrato. TOTAL = soma das 3.

--     BI: vencem DEPOIS do fim do periodo.

--

-- SEM PERIODO NO SQL: o antes/depois do periodo e feito no Looker pelo

-- campo DataVencimento (data do vencimento, dia a dia).

--

-- Regras iguais as da Carteira Atrasada / Futura (conferidas com o BI):

--   - filtro "CT" da pagina e de 'db_recebidas' -> NAO filtra o A Receber

--   - empresa: costCenterId -> NomeCompanhias.enterpriseId;

--     sem Bloko Capital; centro de custo sem cadastro fica fora

--   - subJudicie como coluna (no Looker: filtro subJudicie = N)

--

-- Depende de: analytics.fato_areceber, analytics.fato_titulos_totalizador,

--             analytics.dim_nome_companhias

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_cards_carteira`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_cards_carteira`

CLUSTER BY companyGroup, companyName

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

),



ar AS (

  SELECT

    a.dueDate                                AS DataVencimento,

    nc.companyGroup,

    nc.companyName,

    CAST(a.subJudicie AS STRING)             AS subJudicie,

    a.situacaoInicialAR,

    s.SituacaoContrato,

    (IFNULL(CAST(a.originalAmount AS FLOAT64), 0) <> 0) AS tem_original,

    CAST(a.originalAmount        AS FLOAT64) AS orig_bruto,

    CAST(a.ValorOriginalBloko    AS FLOAT64) AS orig_bloko,

    CAST(a.ValorOriginalParceiro AS FLOAT64) AS orig_parceiro,

    CAST(a.ValorPresente         AS FLOAT64) AS pres_bruto,

    CAST(a.ValorPresenteBloko    AS FLOAT64) AS pres_bloko,

    CAST(a.ValorPresenteParceiro AS FLOAT64) AS pres_parceiro,

    CAST(a.ValorBruto            AS FLOAT64) AS fut_bruto,

    CAST(a.ValorBloko            AS FLOAT64) AS fut_bloko,

    CAST(a.ValorParceiro         AS FLOAT64) AS fut_parceiro

  FROM `dadosfinanceiro-501613.analytics.fato_areceber` a

  JOIN nome_companhias nc

    ON nc.enterpriseId = SAFE_CAST(a.costCenterId AS INT64)

  LEFT JOIN situacao s

    ON s.ChaveGeral = a.ChaveGeral

  WHERE a.dueDate IS NOT NULL

    AND nc.companyGroup <> 'Bloko Capital'

)



SELECT

  DataVencimento,

  EXTRACT(YEAR FROM DataVencimento) AS Ano,

  companyGroup,

  companyName,

  subJudicie,



  -- ================= Valor Atrasado / Inadimplente =================

  -- Bruto

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Adimplente',   orig_bruto, 0)), 2) AS Passado_Adimplente_Bruto,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Atrasado',     orig_bruto, 0)), 2) AS Passado_Atrasado_Bruto,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Inadimplente', orig_bruto, 0)), 2) AS Passado_Inadimplente_Bruto,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR IN ('Atrasado', 'Inadimplente'), orig_bruto, 0)), 2) AS Passado_Total_Bruto,

  -- Bloko

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Adimplente',   orig_bloko, 0)), 2) AS Passado_Adimplente_Bloko,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Atrasado',     orig_bloko, 0)), 2) AS Passado_Atrasado_Bloko,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Inadimplente', orig_bloko, 0)), 2) AS Passado_Inadimplente_Bloko,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR IN ('Atrasado', 'Inadimplente'), orig_bloko, 0)), 2) AS Passado_Total_Bloko,

  -- Parceiro

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Adimplente',   orig_parceiro, 0)), 2) AS Passado_Adimplente_Parceiro,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Atrasado',     orig_parceiro, 0)), 2) AS Passado_Atrasado_Parceiro,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR = 'Inadimplente', orig_parceiro, 0)), 2) AS Passado_Inadimplente_Parceiro,

  ROUND(SUM(IF(tem_original AND situacaoInicialAR IN ('Atrasado', 'Inadimplente'), orig_parceiro, 0)), 2) AS Passado_Total_Parceiro,



  -- ========================= Valor Presente =========================

  ROUND(SUM(IF(SituacaoContrato = 'Adimplente',   pres_bruto, 0)), 2) AS Presente_Adimplente_Bruto,

  ROUND(SUM(IF(SituacaoContrato = 'Atrasado',     pres_bruto, 0)), 2) AS Presente_Atrasado_Bruto,

  ROUND(SUM(IF(SituacaoContrato = 'Inadimplente', pres_bruto, 0)), 2) AS Presente_Inadimplente_Bruto,

  ROUND(SUM(IF(SituacaoContrato IN ('Adimplente', 'Atrasado', 'Inadimplente'), pres_bruto, 0)), 2) AS Presente_Total_Bruto,



  ROUND(SUM(IF(SituacaoContrato = 'Adimplente',   pres_bloko, 0)), 2) AS Presente_Adimplente_Bloko,

  ROUND(SUM(IF(SituacaoContrato = 'Atrasado',     pres_bloko, 0)), 2) AS Presente_Atrasado_Bloko,

  ROUND(SUM(IF(SituacaoContrato = 'Inadimplente', pres_bloko, 0)), 2) AS Presente_Inadimplente_Bloko,

  ROUND(SUM(IF(SituacaoContrato IN ('Adimplente', 'Atrasado', 'Inadimplente'), pres_bloko, 0)), 2) AS Presente_Total_Bloko,



  ROUND(SUM(IF(SituacaoContrato = 'Adimplente',   pres_parceiro, 0)), 2) AS Presente_Adimplente_Parceiro,

  ROUND(SUM(IF(SituacaoContrato = 'Atrasado',     pres_parceiro, 0)), 2) AS Presente_Atrasado_Parceiro,

  ROUND(SUM(IF(SituacaoContrato = 'Inadimplente', pres_parceiro, 0)), 2) AS Presente_Inadimplente_Parceiro,

  ROUND(SUM(IF(SituacaoContrato IN ('Adimplente', 'Atrasado', 'Inadimplente'), pres_parceiro, 0)), 2) AS Presente_Total_Parceiro,



  -- ========================== Valor Futuro ==========================

  ROUND(SUM(IF(SituacaoContrato = 'Adimplente',   fut_bruto, 0)), 2) AS Futuro_Adimplente_Bruto,

  ROUND(SUM(IF(SituacaoContrato = 'Atrasado',     fut_bruto, 0)), 2) AS Futuro_Atrasado_Bruto,

  ROUND(SUM(IF(SituacaoContrato = 'Inadimplente', fut_bruto, 0)), 2) AS Futuro_Inadimplente_Bruto,

  ROUND(SUM(IF(SituacaoContrato IN ('Adimplente', 'Atrasado', 'Inadimplente'), fut_bruto, 0)), 2) AS Futuro_Total_Bruto,



  ROUND(SUM(IF(SituacaoContrato = 'Adimplente',   fut_bloko, 0)), 2) AS Futuro_Adimplente_Bloko,

  ROUND(SUM(IF(SituacaoContrato = 'Atrasado',     fut_bloko, 0)), 2) AS Futuro_Atrasado_Bloko,

  ROUND(SUM(IF(SituacaoContrato = 'Inadimplente', fut_bloko, 0)), 2) AS Futuro_Inadimplente_Bloko,

  ROUND(SUM(IF(SituacaoContrato IN ('Adimplente', 'Atrasado', 'Inadimplente'), fut_bloko, 0)), 2) AS Futuro_Total_Bloko,



  ROUND(SUM(IF(SituacaoContrato = 'Adimplente',   fut_parceiro, 0)), 2) AS Futuro_Adimplente_Parceiro,

  ROUND(SUM(IF(SituacaoContrato = 'Atrasado',     fut_parceiro, 0)), 2) AS Futuro_Atrasado_Parceiro,

  ROUND(SUM(IF(SituacaoContrato = 'Inadimplente', fut_parceiro, 0)), 2) AS Futuro_Inadimplente_Parceiro,

  ROUND(SUM(IF(SituacaoContrato IN ('Adimplente', 'Atrasado', 'Inadimplente'), fut_parceiro, 0)), 2) AS Futuro_Total_Parceiro



FROM ar

GROUP BY 1, 2, 3, 4, 5;