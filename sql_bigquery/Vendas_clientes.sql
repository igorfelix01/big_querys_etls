
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]
-- ####################################################################

-- 19_db_vendas_clientes_transformacoes

--

-- IMPORTANTE:

-- NAO usa raw.vendas_clientes.

-- Trabalha somente com a TRUSTED ja existente e confirmada.

-- ####################################################################





-- ====================================================================

-- 1. VALIDACAO DA TRUSTED ATUAL

-- ====================================================================



-- SELECT

--   COUNT(*) AS total_trusted,



--   COUNT(

--     DISTINCT ChaveGeral

--   ) AS chaves_distintas,



--   COUNTIF(

--     ChaveGeral IS NULL

--   ) AS chave_nula,



--   COUNTIF(

--     names IS NULL

--     OR TRIM(names) = ''

--   ) AS nomes_nulos_ou_vazios,



--   COUNTIF(

--     companyId IS NULL

--   ) AS companyId_nulo,



--   COUNTIF(

--     receivableBillId IS NULL

--   ) AS receivableBillId_nulo



-- FROM

--   `dadosfinanceiro-501613.trusted.db_vendas_clientes`

-- ;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ====================================================================

-- 2. VALIDACAO DE DUPLICIDADE

-- Resultado esperado: nenhuma linha

-- ====================================================================



-- SELECT

--   ChaveGeral,

--   COUNT(*) AS qtd



-- FROM

--   `dadosfinanceiro-501613.trusted.db_vendas_clientes`



-- GROUP BY

--   ChaveGeral



-- HAVING

--   COUNT(*) > 1



-- ORDER BY

--   qtd DESC,

--   ChaveGeral

-- ;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ====================================================================

-- 3. VALIDAR CHAVEGERAL X IDS

-- ====================================================================



-- SELECT

--   COUNT(*) AS total,



--   COUNTIF(

--     SAFE_CAST(

--       SPLIT(

--         ChaveGeral,

--         '-'

--       )[SAFE_OFFSET(0)]

--       AS INT64

--     ) != companyId

--   ) AS companyId_divergente,



--   COUNTIF(

--     SAFE_CAST(

--       SPLIT(

--         ChaveGeral,

--         '-'

--       )[SAFE_OFFSET(1)]

--       AS INT64

--     ) != receivableBillId

--   ) AS receivableBillId_divergente



-- FROM

--   `dadosfinanceiro-501613.trusted.db_vendas_clientes`

-- ;





-- ====================================================================

-- 4. RECRIAR ANALYTICS

-- ====================================================================



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.dim_vendas_clientes`

AS



SELECT

  ChaveGeral,

  names,

  companyId,

  receivableBillId



FROM

  `dadosfinanceiro-501613.trusted.db_vendas_clientes`

;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ====================================================================

-- 5. VALIDACAO FINAL DA ANALYTICS

-- ====================================================================



-- SELECT

--   COUNT(*) AS total_analytics,



--   COUNT(

--     DISTINCT ChaveGeral

--   ) AS chaves_distintas,



--   COUNTIF(

--     ChaveGeral IS NULL

--   ) AS chave_nula,



--   COUNTIF(

--     names IS NULL

--     OR TRIM(names) = ''

--   ) AS nomes_nulos_ou_vazios,



--   COUNTIF(

--     companyId IS NULL

--   ) AS companyId_nulo,



--   COUNTIF(

--     receivableBillId IS NULL

--   ) AS receivableBillId_nulo



-- FROM

--   `dadosfinanceiro-501613.analytics.dim_vendas_clientes`

-- ;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ====================================================================

-- 6. COMPARACAO TRUSTED X ANALYTICS

-- ====================================================================



-- WITH trusted AS (



--   SELECT

--     ChaveGeral,

--     names,

--     companyId,

--     receivableBillId



--   FROM

--     `dadosfinanceiro-501613.trusted.db_vendas_clientes`



-- ),



-- analytics AS (



--   SELECT

--     ChaveGeral,

--     names,

--     companyId,

--     receivableBillId



--   FROM

--     `dadosfinanceiro-501613.analytics.dim_vendas_clientes`



-- )



-- SELECT



--   (

--     SELECT COUNT(*)

--     FROM trusted

--   ) AS total_trusted,



--   (

--     SELECT COUNT(*)

--     FROM analytics

--   ) AS total_analytics,



--   (

--     SELECT COUNT(*)

--     FROM (

--       SELECT * FROM trusted



--       EXCEPT DISTINCT



--       SELECT * FROM analytics

--     )

--   ) AS linhas_so_trusted,



--   (

--     SELECT COUNT(*)

--     FROM (

--       SELECT * FROM analytics



--       EXCEPT DISTINCT



--       SELECT * FROM trusted

--     )

--   ) AS linhas_so_analytics

-- ;