-- ####################################################################

-- LOOKER_STUDIO.CRI_PMT_AMORTIZACAO

-- Grafico do BI: "PMT e Curva de Amortizacao"

--   Eixo X  : mes (CRI[Data])

--   Colunas empilhadas (DAX):

--     Juros Pago               = SUM(Juros)           situacaoCRI = "Paga"

--     Amortizacao Pago         = SUM(Amortizacao)     situacaoCRI = "Paga"

--     Amortizacao Extr. Pago   = SUM(Amort. Extraor.) situacaoCRI = "Paga"

--     Juros A Pagar            = SUM(Juros)           situacaoCRI = "A Pagar"

--     Amortizacao A Pagar      = SUM(Amortizacao)     situacaoCRI = "A Pagar"

--     Amortizacao Extr. A Pagar= SUM(Amort. Extraor.) situacaoCRI = "A Pagar"

--   Linha   : Saldo Devedor (Saldo Devedor Apos a PMT)

--

-- 1 linha por MES x CRI (Nome_DataFrame_Origem) x companyGroup.

-- Saldo_Devedor = saldo apos a ULTIMA PMT do mes de cada CRI

--   (alguns CRIs tem 2 PMTs no mes; somar as duas dobraria o saldo).

--   No Looker: SOMA (soma os CRIs do mes).

-- situacaoCRI vem do Cri.sql (Paga = data <= hoje).

-- SEM periodo no SQL (Looker: campo Mes).

--

-- Depende de: analytics.fato_cri

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.cri_pmt_amortizacao`;-- [otimizacao] CTE 'base' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base AS
  SELECT

    DATE_TRUNC(data, MONTH)         AS Mes,

    data,

    nome_dataframe_origem           AS CRI,

    companyGroup,

    situacaoCRI,

    IFNULL(juros, 0)                AS juros,

    IFNULL(amortizacao, 0)          AS amortizacao,

    IFNULL(amort_extraor, 0)        AS amort_extraor,

    saldo_devedor_apos_pmt

  FROM `dadosfinanceiro-501613.analytics.fato_cri`

  WHERE data IS NOT NULL;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.cri_pmt_amortizacao`

CLUSTER BY companyGroup

AS
WITH
saldo_mes AS (

  SELECT Mes, CRI, saldo_devedor_apos_pmt AS Saldo_Devedor

  FROM base

  WHERE saldo_devedor_apos_pmt IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (PARTITION BY Mes, CRI ORDER BY data DESC) = 1

)
SELECT

  b.Mes,

  EXTRACT(YEAR FROM b.Mes)                                              AS Ano,

  b.CRI,

  b.companyGroup,



  ROUND(SUM(IF(b.situacaoCRI = 'Paga',    b.juros,         0)), 2)     AS Juros_Pago,

  ROUND(SUM(IF(b.situacaoCRI = 'Paga',    b.amortizacao,   0)), 2)     AS Amortizacao_Pago,

  ROUND(SUM(IF(b.situacaoCRI = 'Paga',    b.amort_extraor, 0)), 2)     AS Amortizacao_Extr_Pago,

  ROUND(SUM(IF(b.situacaoCRI = 'A Pagar', b.juros,         0)), 2)     AS Juros_A_Pagar,

  ROUND(SUM(IF(b.situacaoCRI = 'A Pagar', b.amortizacao,   0)), 2)     AS Amortizacao_A_Pagar,

  ROUND(SUM(IF(b.situacaoCRI = 'A Pagar', b.amort_extraor, 0)), 2)     AS Amortizacao_Extr_A_Pagar,



  -- total da coluna (rotulo em cima da barra)

  ROUND(SUM(b.juros + b.amortizacao + b.amort_extraor), 2)             AS PMT_Total,



  ROUND(ANY_VALUE(s.Saldo_Devedor), 2)                                  AS Saldo_Devedor



FROM base b

LEFT JOIN saldo_mes s

  ON s.Mes = b.Mes AND s.CRI = b.CRI

GROUP BY 1, 2, 3, 4;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO (comparar com o grafico do BI, todos os CRIs)

-- ####################################################################

-- SELECT

--   Mes,

--   ROUND(SUM(Juros_Pago + Amortizacao_Pago + Amortizacao_Extr_Pago))          AS pago,

--   ROUND(SUM(Juros_A_Pagar + Amortizacao_A_Pagar + Amortizacao_Extr_A_Pagar)) AS a_pagar,

--   ROUND(SUM(PMT_Total))                                                       AS pmt_total,

--   ROUND(SUM(Saldo_Devedor))                                                   AS saldo_devedor

-- FROM `dadosfinanceiro-501613.looker_studio.cri_pmt_amortizacao`

-- GROUP BY Mes

-- ORDER BY Mes;