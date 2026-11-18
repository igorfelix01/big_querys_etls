-- ####################################################################

-- LOOKER_STUDIO.DATA_ATUALIZACAO

-- Card "Dados atualizados em" no Looker (igual a "ultima atualizacao" do BI).

--

-- 1 linha so: a hora em que os dados do Sienge chegaram no BigQuery

-- (ultima gravacao da raw.areceber, feita pela etapa 1 do ATUALIZAR_TUDO),

-- no horario de Brasilia.

--   DataAtualizacao       DATETIME  ex.: 2026-10-13 05:12:40

--   DiaAtualizacao        DATE      ex.: 2026-10-13

--   DataAtualizacaoTexto  STRING    ex.: 13/10/2026 05:12

--

-- Le so os metadados das tabelas (__TABLES__): nao custa nada.

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.data_atualizacao`

AS



WITH ultima AS (

  SELECT

    DATETIME(TIMESTAMP_MILLIS(MAX(last_modified_time)), 'America/Sao_Paulo') AS dt

  FROM `dadosfinanceiro-501613.raw.__TABLES__`

  WHERE table_id IN ('areceber', 'recebidas_atualizavel')

)



SELECT

  dt                                       AS DataAtualizacao,

  DATE(dt)                                 AS DiaAtualizacao,

  FORMAT_DATETIME('%d/%m/%Y %H:%M', dt)    AS DataAtualizacaoTexto

FROM ultima;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- CONFERENCIA

-- SELECT * FROM `dadosfinanceiro-501613.looker_studio.data_atualizacao`;