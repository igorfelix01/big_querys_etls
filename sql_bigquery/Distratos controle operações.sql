-- ####################################################################

-- TRUSTED.DISTRATOS_CONTROLE_OPERACOES

-- + ANALYTICS.FATO_DISTRATOS_CONTROLE_OPERACOES

--

-- FONTE: dadosfinanceiro-501613.raw.distratos_controle_operacoes

--        (distratos_controle_operacoes.py: copia da aba "Base da dados",

--         cabecalho da linha 9, colunas 1 a 33, tudo texto)

--

-- FIEL AO POWER QUERY: Base_Distratos_Operacoes

--   1. Tipo Alterado1: datas, numeros e inteiros (o que nao converte = NULL)

--      Column1, Column2, Double check_2 e Column33 ficam sem tipo (texto)

--   2. Renamed Columns: "Empresa" -> "Empresa.1"   (aqui: Empresa_1, ja

--      vem assim do Python: o BigQuery nao diferencia EMPRESA de Empresa)

--   3. Colunas Removidas: Column32 e Column34..Column123

--      (Column33 FICA, igual ao PQ)

--   4. companyId    = Text.BeforeDelimiter([Empresa.1], "-")

--      enterpriseId = Text.BeforeDelimiter([EMPREENDIMENTO], "-")

--      (texto antes do 1o "-", SEM tirar espaco, igual ao PQ;

--       sem "-" -> texto inteiro)

--   5. Linhas em Branco Removidas: tira a linha quando TODOS os campos

--      estao vazios ("" ou null)

-- ####################################################################





-- ====================================================================

-- FUNCOES AUXILIARES

-- ====================================================================



-- texto -> numero (aceita 1234.5 e tambem 1.234,50)

CREATE TEMP FUNCTION br_num(v STRING) AS (

  CASE

    WHEN v IS NULL OR TRIM(v) = '' THEN NULL

    WHEN REGEXP_CONTAINS(TRIM(v), r',')

      THEN SAFE_CAST(REPLACE(REPLACE(REPLACE(TRIM(v), 'R$', ''), '.', ''), ',', '.') AS FLOAT64)

    ELSE SAFE_CAST(REPLACE(TRIM(v), 'R$', '') AS FLOAT64)

  END

);



-- texto -> inteiro (Int64.Type: arredonda)

CREATE TEMP FUNCTION br_int(v STRING) AS (

  SAFE_CAST(ROUND(br_num(v)) AS INT64)

);



-- texto -> data (AAAA-MM-DD do Python, ou dd/mm/aaaa digitado)

CREATE TEMP FUNCTION br_data(v STRING) AS (

  CASE

    WHEN v IS NULL OR TRIM(v) = '' THEN NULL

    ELSE COALESCE(

      SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(TRIM(v), 1, 10)),

      SAFE.PARSE_DATE('%d/%m/%Y', SUBSTR(TRIM(v), 1, 10))

    )

  END

);



-- Text.BeforeDelimiter(texto, "-")

CREATE TEMP FUNCTION antes_do_traco(v STRING) AS (

  IF(v IS NULL, NULL, SPLIT(v, '-')[OFFSET(0)])

);





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.distratos_controle_operacoes`

AS



WITH



-- ====================================================================

-- 5 (antes). LINHAS EM BRANCO REMOVIDAS

-- (todas as colunas do raw vazias; companyId/enterpriseId vem delas)

-- ====================================================================

raw_sem_branco AS (

  SELECT *

  FROM `dadosfinanceiro-501613.raw.distratos_controle_operacoes` r

  WHERE COALESCE(

    NULLIF(r.Column1, ''), NULLIF(r.Column2, ''), NULLIF(r.MES_CANCELAMENTO, ''),

    NULLIF(r.Data, ''), NULLIF(r.Titulo, ''), NULLIF(r.Documento, ''),

    NULLIF(r.EMPREENDIMENTO, ''), NULLIF(r.Unidades, ''), NULLIF(r.VGV, ''),

    NULLIF(r.Valor_historico_contrato, ''), NULLIF(r.V_pago_pelo_cliente, ''),

    NULLIF(r.TITULO_GERADO, ''), NULLIF(r.VALOR_DISTRATO, ''),

    NULLIF(r.titulo_a_devolver, ''), NULLIF(r.Nao_programado, ''),

    NULLIF(r.Modo_devolucao, ''), NULLIF(r.Numero_de_parcelas, ''),

    NULLIF(r.Double_check, ''), NULLIF(r.Valor_da_parcela, ''),

    NULLIF(r.Data_inicio, ''), NULLIF(r.COND, ''), NULLIF(r.IPTU, ''),

    NULLIF(r.Cliente, ''), NULLIF(r.OBSERVACAO, ''),

    NULLIF(r.TIPO_DE_CANCELAMENTO, ''), NULLIF(r.EMPRESA, ''),

    NULLIF(r.Empresa_1, ''), NULLIF(r.Valor_da_parcela_1, ''),

    NULLIF(r.Ativa_desembolso, ''), NULLIF(r.Termina_desembolso, ''),

    NULLIF(r.Double_check_2, ''), NULLIF(r.Column33, '')

  ) IS NOT NULL

)



-- ====================================================================

-- 1 a 4. TIPOS + RENOMEAR + REMOVER Column32 + companyId / enterpriseId

-- ====================================================================

SELECT

  Column1,

  Column2,

  br_data(MES_CANCELAMENTO)          AS MES_CANCELAMENTO,

  br_data(Data)                      AS Data,

  br_int(Titulo)                     AS Titulo,

  Documento,

  EMPREENDIMENTO,

  Unidades,

  br_num(VGV)                        AS VGV,

  br_num(Valor_historico_contrato)   AS Valor_historico_contrato,

  br_num(V_pago_pelo_cliente)        AS V_pago_pelo_cliente,

  br_int(TITULO_GERADO)              AS TITULO_GERADO,

  br_num(VALOR_DISTRATO)             AS VALOR_DISTRATO,

  br_num(titulo_a_devolver)          AS titulo_a_devolver,

  br_num(Nao_programado)             AS Nao_programado,

  Modo_devolucao,

  br_int(Numero_de_parcelas)         AS Numero_de_parcelas,

  Double_check,

  br_num(Valor_da_parcela)           AS Valor_da_parcela,

  br_data(Data_inicio)               AS Data_inicio,

  br_num(COND)                       AS COND,

  br_num(IPTU)                       AS IPTU,

  Cliente,

  OBSERVACAO,

  TIPO_DE_CANCELAMENTO,

  EMPRESA,

  Empresa_1,                                              -- PQ: "Empresa" -> "Empresa.1"

  br_num(Valor_da_parcela_1)         AS Valor_da_parcela_1,

  br_data(Ativa_desembolso)          AS Ativa_desembolso,

  br_data(Termina_desembolso)        AS Termina_desembolso,

  Double_check_2,

  Column33,                                               -- PQ mantem (sem tipo)

  antes_do_traco(Empresa_1)          AS companyId,

  antes_do_traco(EMPREENDIMENTO)     AS enterpriseId

FROM raw_sem_branco;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.fato_distratos_controle_operacoes`

AS

SELECT *

FROM `dadosfinanceiro-501613.trusted.distratos_controle_operacoes`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA (comparar com o BI: linhas, soma do VALOR DISTRATO)

-- ####################################################################

-- SELECT

--   (SELECT COUNT(*) FROM `dadosfinanceiro-501613.raw.distratos_controle_operacoes`)            AS linhas_raw,

--   (SELECT COUNT(*) FROM `dadosfinanceiro-501613.analytics.fato_distratos_controle_operacoes`) AS linhas_fato,

--   (SELECT ROUND(SUM(VALOR_DISTRATO), 2)

--      FROM `dadosfinanceiro-501613.analytics.fato_distratos_controle_operacoes`)               AS soma_valor_distrato,

--   (SELECT COUNTIF(MES_CANCELAMENTO IS NULL AND Data IS NOT NULL)

--      FROM `dadosfinanceiro-501613.analytics.fato_distratos_controle_operacoes`)               AS sem_mes_cancelamento;