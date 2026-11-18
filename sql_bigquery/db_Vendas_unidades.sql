-- ============================================================

-- 20_db_vendas_unidades_transformacoes

-- Reproducao do Editor Avancado original do Power Query

-- ============================================================



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.db_vendas_unidades`

AS



WITH fonte AS (



  SELECT

    CAST(main AS STRING) AS main,

    CAST(name AS STRING) AS name,

    CAST(ChaveEspecifica AS STRING) AS ChaveGeral



  FROM

    `dadosfinanceiro-501613.raw.vendas_unidades`

),



adicionado_receivable_bill_id AS (



  SELECT

    *,

    CAST(

      REGEXP_EXTRACT(

        ChaveGeral,

        r'^[^-]+-(.*)$'

      )

      AS INT64

    ) AS receivableBillId



  FROM fonte

),



adicionado_chave_lote AS (



  SELECT

    *,

    CONCAT(

      ChaveGeral,

      '-',

      name

    ) AS ChaveLote



  FROM adicionado_receivable_bill_id

),



removidos_duplicados AS (



  SELECT

    *



  FROM adicionado_chave_lote



  QUALIFY

    ROW_NUMBER() OVER (

      PARTITION BY ChaveLote

      ORDER BY ChaveLote

    ) = 1

),



adicionado_company_id AS (



  SELECT

    *,

    REGEXP_EXTRACT(

      ChaveGeral,

      r'^([^-]+)-'

    ) AS companyId



  FROM removidos_duplicados

),



adicionado_nome_lote AS (



  SELECT

    *,

    CONCAT(

      companyId,

      '-',

      name

    ) AS NomeLote



  FROM adicionado_company_id

)



SELECT

  main,

  name,

  ChaveGeral,

  receivableBillId,

  ChaveLote,

  companyId,

  NomeLote



FROM

  adicionado_nome_lote;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.dim_vendas_unidades`

AS



SELECT

  main,

  name,

  ChaveGeral,

  receivableBillId,

  ChaveLote,

  companyId,

  NomeLote



FROM

  `dadosfinanceiro-501613.trusted.db_vendas_unidades`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ============================================================

-- VALIDACAO

-- ============================================================



-- SELECT

--   (

--     SELECT COUNT(*)

--     FROM `dadosfinanceiro-501613.raw.vendas_unidades`

--   ) AS linhas_raw,



--   (

--     SELECT COUNT(*)

--     FROM `dadosfinanceiro-501613.trusted.db_vendas_unidades`

--   ) AS linhas_trusted,



--   (

--     SELECT COUNT(*)

--     FROM `dadosfinanceiro-501613.analytics.dim_vendas_unidades`

--   ) AS linhas_analytics,



--   (

--     SELECT COUNT(DISTINCT ChaveLote)

--     FROM `dadosfinanceiro-501613.trusted.db_vendas_unidades`

--   ) AS chaves_lote_distintas,



--   (

--     SELECT COUNT(*)

--     FROM `dadosfinanceiro-501613.trusted.db_vendas_unidades`

--     WHERE ChaveGeral IS NULL

--        OR receivableBillId IS NULL

--        OR ChaveLote IS NULL

--        OR companyId IS NULL

--        OR NomeLote IS NULL

--   ) AS linhas_com_nulos_chave;