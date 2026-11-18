-- ####################################################################

-- TRUSTED.CRI + ANALYTICS.FATO_CRI  (fiel ao Power Query "CRI")

--   fonte: raw.cri (cri_extranet_bigquery.py - mesmo conteudo do

--          Cri_Final_novo.xlsx que o BI le)

--   tipos iguais ao PQ (Data date, valores number, Premio Int64)

--   companyGroup pelo Nome_DataFrame_Origem (mesma regra do PQ)

--   situacaoCRI = 'Paga' se Data <= hoje, senao 'A Pagar'

-- ####################################################################



CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.cri` AS

SELECT

  CAST(data AS DATE) AS data,

  CAST(prestacao AS FLOAT64) AS prestacao,

  CAST(juros AS FLOAT64) AS juros,

  CAST(amortizacao AS FLOAT64) AS amortizacao,

  CAST(amort_extraor AS FLOAT64) AS amort_extraor,

  SAFE_CAST(ROUND(SAFE_CAST(premio AS FLOAT64)) AS INT64) AS premio,   -- PQ: Prêmio Int64.Type

  CAST(saldo_devedor_apos_pmt AS FLOAT64) AS saldo_devedor_apos_pmt,

  CAST(nome_dataframe_origem AS STRING) AS nome_dataframe_origem,

  CAST(saldo_devedor_antes_pmt AS FLOAT64) AS saldo_devedor_antes_pmt,

  CAST(fundo_de_reserva AS FLOAT64) AS fundo_de_reserva

FROM `dadosfinanceiro-501613.raw.cri`;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_cri` AS

SELECT

  data,

  prestacao,

  juros,

  amortizacao,

  amort_extraor,

  premio,

  saldo_devedor_apos_pmt,

  nome_dataframe_origem,

  saldo_devedor_antes_pmt,

  fundo_de_reserva,



  CASE

    WHEN nome_dataframe_origem IN (

      'CRI_S685_690_Macapá_PU.xlsx',

      'CRI_S685_690_Macapa_PU.xlsx'

    ) THEN 'Macapá S.A.'

    WHEN nome_dataframe_origem = 'CRI_S19_20_Gran Viver_PU.xlsx' THEN 'Gran Viver'

    WHEN nome_dataframe_origem = 'CRI_E03_S01_04_S&J_PU.xlsx' THEN 'Inlot'

    WHEN nome_dataframe_origem = 'CRI_S608_615_Loteamento NG30_PU.xlsx' THEN 'Reserva Ville'

    WHEN nome_dataframe_origem = 'CRI_E05_S01_02_Bloko Urbanismo_PU.xlsx' THEN 'Bloko Urbanismo'

    ELSE NULL

  END AS companyGroup,



  CASE

    WHEN data <= CURRENT_DATE('America/Sao_Paulo') THEN 'Paga'

    ELSE 'A Pagar'

  END AS situacaoCRI



FROM `dadosfinanceiro-501613.trusted.cri`;