-- [otimizacao] CTE 'tel_reserva' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE tel_reserva AS
WITH
tel_raw AS (

  SELECT TO_JSON_STRING(t) AS j

  FROM `dadosfinanceiro-501613.raw.clientes_telefones` t

)
SELECT * FROM (


  SELECT

    SAFE_CAST(SAFE_CAST(COALESCE(

      JSON_VALUE(j, '$.cliente_id'), JSON_VALUE(j, '$.clienteId'),

      JSON_VALUE(j, '$.clientId'),   JSON_VALUE(j, '$.customerId'),

      JSON_VALUE(j, '$.id_cliente')) AS FLOAT64) AS INT64)           AS cliente_id,

    NULLIF(TRIM(JSON_VALUE(j, '$.subdominio')), '')                  AS subdominio,

    NULLIF(TRIM(COALESCE(JSON_VALUE(j, '$.number'),

                         JSON_VALUE(j, '$.telefone'),

                         JSON_VALUE(j, '$.phone'))), '')             AS Telefone,

    LOWER(TRIM(JSON_VALUE(j, '$.main')))                             AS main

  FROM tel_raw


);

-- [otimizacao] CTE 'tel_reserva_cliente' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE tel_reserva_cliente AS
  SELECT

    cliente_id,

    subdominio,

    -- principal (main = true) primeiro; se nao tiver principal, os outros

    COALESCE(

      NULLIF(ARRAY_TO_STRING(ARRAY_AGG(DISTINCT

        IF(main IN ('true', '1'), Telefone, NULL) IGNORE NULLS), ' - '), ''),

      NULLIF(ARRAY_TO_STRING(ARRAY_AGG(DISTINCT Telefone IGNORE NULLS), ' - '), '')

    ) AS Telefone

  FROM tel_reserva

  WHERE cliente_id IS NOT NULL

  GROUP BY 1, 2;

-- ####################################################################

-- CLIENTES  (fiel ao Power Query db_clientes)

-- Cria: trusted.db_clientes e analytics.dim_clientes

-- Le  : raw.clientes (+ raw.clientes_telefones como reserva)

--

-- Telefone:

--   1o) raw.clientes, coluna number (o AtualizarClientes.py abre a lista

--       phones: 1 linha por telefone, com main = principal)

--   2o) se o cliente ficou sem telefone, raw.clientes_telefones

--       (carregada pelo script de telefones, etapa 1c). Colunas dela:

--       indexador_unico, cliente_id, type, number, ddd, idd, note, main

--       (sem subdominio -> liga so pelo cliente_id)

--   Se o cliente nao tiver telefone principal, usa os outros

--   (comercial, referencia...) para nao ficar sem contato.

--   Telefone principal (main = true) primeiro; varios juntos com ' - '.

-- Leitura por JSON: coluna que nao existir vem NULL (nao da erro).

-- Cliente sem telefone continua na tabela (Telefone vazio).

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.db_clientes`

AS
WITH
bruto AS (

  SELECT TO_JSON_STRING(c) AS j

  FROM `dadosfinanceiro-501613.raw.clientes` c

),

base AS (

  SELECT

    SAFE_CAST(SAFE_CAST(JSON_VALUE(j, '$.id') AS FLOAT64) AS INT64) AS id,

    NULLIF(TRIM(JSON_VALUE(j, '$.subdominio')), '')                  AS subdominio,

    NULLIF(TRIM(JSON_VALUE(j, '$.name')), '')                        AS Nome,

    NULLIF(TRIM(JSON_VALUE(j, '$.cpf')), '')                         AS CPF,

    NULLIF(TRIM(JSON_VALUE(j, '$.cnpj')), '')                        AS CNPJ,

    NULLIF(TRIM(JSON_VALUE(j, '$.email')), '')                       AS Email,

    NULLIF(TRIM(CONCAT(

      IFNULL(NULLIF(TRIM(JSON_VALUE(j, '$.ddd')), ''), ''),

      IF(NULLIF(TRIM(JSON_VALUE(j, '$.ddd')), '') IS NULL, '', ' '),

      IFNULL(TRIM(JSON_VALUE(j, '$.number')), ''))), '')             AS Telefone,

    LOWER(TRIM(JSON_VALUE(j, '$.main')))                             AS main

  FROM bruto

),

clientes AS (

  SELECT

    CONCAT(subdominio, '-', CAST(id AS STRING)) AS ChaveClientes,

    ANY_VALUE(id)                               AS id,

    ANY_VALUE(subdominio)                       AS subdominio,

    STRING_AGG(DISTINCT CNPJ,  ' - ')           AS CNPJ,

    STRING_AGG(DISTINCT CPF,   ' - ')           AS CPF,

    STRING_AGG(DISTINCT Email, ' - ')           AS Email,

    STRING_AGG(DISTINCT Nome,  ' - ')           AS Nome,

    -- telefones: principal primeiro, sem os marcados main = false

    ARRAY_TO_STRING(ARRAY_AGG(DISTINCT

      IF(IFNULL(main, '') IN ('false', '0'), NULL, Telefone) IGNORE NULLS), ' - ') AS Telefone_principal,

    ARRAY_TO_STRING(ARRAY_AGG(DISTINCT Telefone IGNORE NULLS), ' - ') AS Telefone_todos

  FROM base

  WHERE id IS NOT NULL

    AND subdominio IS NOT NULL

  GROUP BY 1

),

tel_reserva_id AS (

  SELECT

    cliente_id,

    COALESCE(

      NULLIF(ARRAY_TO_STRING(ARRAY_AGG(DISTINCT

        IF(main IN ('true', '1'), Telefone, NULL) IGNORE NULLS), ' - '), ''),

      NULLIF(ARRAY_TO_STRING(ARRAY_AGG(DISTINCT Telefone IGNORE NULLS), ' - '), '')

    ) AS Telefone

  FROM tel_reserva

  WHERE cliente_id IS NOT NULL

  GROUP BY 1

)
SELECT

  c.CNPJ,

  c.CPF,

  c.ChaveClientes,

  c.Email,

  c.Nome,

  COALESCE(NULLIF(c.Telefone_principal, ''),

           NULLIF(c.Telefone_todos, ''),

           NULLIF(t1.Telefone, ''),

           NULLIF(t2.Telefone, ''),

           NULLIF(t3.Telefone, ''))        AS Telefone,

  c.id,

  c.subdominio

FROM clientes c

-- reserva com subdominio (quando a tabela de telefones tem a coluna)

LEFT JOIN tel_reserva_cliente t1

  ON t1.cliente_id = c.id AND t1.subdominio = c.subdominio

-- reserva so pelo id do cliente (quando nao tem subdominio)

LEFT JOIN tel_reserva_cliente t2

  ON t2.cliente_id = c.id AND t2.subdominio IS NULL

LEFT JOIN tel_reserva_id t3

  ON t3.cliente_id = c.id;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.dim_clientes`

AS

SELECT CNPJ, CPF, ChaveClientes, Email, Nome, Telefone, id, subdominio

FROM `dadosfinanceiro-501613.trusted.db_clientes`;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA: quantos clientes tem telefone

-- ####################################################################

-- SELECT

--   COUNT(*)                     AS clientes,

--   COUNTIF(Telefone IS NOT NULL) AS com_telefone,

--   COUNTIF(Email IS NOT NULL)    AS com_email

-- FROM `dadosfinanceiro-501613.analytics.dim_clientes`;