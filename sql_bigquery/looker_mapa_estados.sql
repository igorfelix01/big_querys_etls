-- ####################################################################
-- LOOKER_STUDIO.MAPA_ESTADOS
-- Mapa do Brasil: estados coloridos pelo numero de contratos e bolinhas
-- por companyGroup (tamanho = contratos).
--
-- Local de cada empresa (informado pelo financeiro):
--   Gran Viver -> Belo Horizonte / MG      Macapa  -> Macapa / AP
--   Inlot      -> GO                       Imperial -> GO
--   NG30       -> GO
--   (empresa fora da lista -> UF vazia; acrescentar no CTE "locais")
-- As 3 de GO nao tem cidade: a bolinha fica num ponto aproximado dentro de
-- Goias (LatLong), um pouco afastadas para nao ficarem uma em cima da outra.
--
-- 1 linha por empreendimento (enterpriseId), com:
--   UF, NomeEstado, UF_ISO ('BR-MG')    -> mapa preenchido por estado
--   Cidade, LatLong ('-19.9167,-43.9345')     -> mapa de bolhas
--   companyGroup, companyName, projectName, enterpriseName (filtros/cor)
--   Contratos, Contratos_Adimplentes / _Atrasados / _Inadimplentes,
--   Saldo_A_Receber, Vencido_Em_Aberto            (no Looker: SOMA)
--
-- Contrato ativo = tem parcela no A Receber (documento CT), sem Bloko.
-- Empreendimento do contrato = centro de custo (costCenterId), igual ao BI.
-- Situacao do contrato = analytics.fato_titulos_totalizador.
--
-- Depende de: analytics.saldo_devedor, analytics.fato_titulos_totalizador,
--             analytics.dim_empreendimentos_vendas
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.mapa_estados`
AS

WITH

-- local de cada empresa (procura o nome dentro do companyGroup)
locais AS (
  SELECT * FROM UNNEST([
    STRUCT('GRAN VIVER' AS chave, 'MG' AS UF, 'Belo Horizonte' AS Cidade, -19.9167 AS Lat, -43.9345 AS Lon),
    ('MACAP',   'AP', 'Macapá',          0.0349, -51.0694),
    ('INLOT',   'GO', CAST(NULL AS STRING), -16.6869, -49.2648),
    ('IMPERIAL','GO', CAST(NULL AS STRING), -15.6000, -50.4000),
    ('NG30',    'GO', CAST(NULL AS STRING), -17.6000, -48.6000),
    ('NG 30',   'GO', CAST(NULL AS STRING), -17.6000, -48.6000)
  ])
),

estados AS (
  SELECT * FROM UNNEST([
    STRUCT('AC' AS UF, 'Acre' AS NomeEstado), ('AL','Alagoas'), ('AP','Amapá'),
    ('AM','Amazonas'), ('BA','Bahia'), ('CE','Ceará'), ('DF','Distrito Federal'),
    ('ES','Espírito Santo'), ('GO','Goiás'), ('MA','Maranhão'), ('MT','Mato Grosso'),
    ('MS','Mato Grosso do Sul'), ('MG','Minas Gerais'), ('PA','Pará'), ('PB','Paraíba'),
    ('PR','Paraná'), ('PE','Pernambuco'), ('PI','Piauí'), ('RJ','Rio de Janeiro'),
    ('RN','Rio Grande do Norte'), ('RS','Rio Grande do Sul'), ('RO','Rondônia'),
    ('RR','Roraima'), ('SC','Santa Catarina'), ('SP','São Paulo'), ('SE','Sergipe'),
    ('TO','Tocantins')
  ])
),

emp AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    ANY_VALUE(companyGroup)          AS companyGroup,
    ANY_VALUE(companyName)           AS companyName,
    ANY_VALUE(projectName)           AS projectName,
    ANY_VALUE(enterpriseName)        AS enterpriseName
  FROM `dadosfinanceiro-501613.analytics.dim_empreendimentos_vendas`
  WHERE SAFE_CAST(enterpriseId AS INT64) IS NOT NULL
  GROUP BY 1
),

-- parcelas em aberto (A Receber), por contrato
aberto AS (
  SELECT
    CAST(ChaveGeral AS STRING)       AS ChaveGeral,
    ANY_VALUE(SAFE_CAST(costCenterId AS INT64)) AS enterpriseId,
    SUM(ValorBruto)                  AS Saldo_A_Receber,
    SUM(IF(dueDate < CURRENT_DATE('America/Sao_Paulo'), ValorBruto, 0)) AS Vencido_Em_Aberto
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`
  WHERE OrigemBase = 'A Receber'
    AND documentIdentificationId = 'CT'
    AND ChaveGeral IS NOT NULL
  GROUP BY 1
),

situacao AS (
  SELECT
    CAST(ChaveGeral AS STRING) AS ChaveGeral,
    ANY_VALUE(SituacaoContrato) AS SituacaoContrato
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  GROUP BY 1
),

contrato AS (
  SELECT
    a.enterpriseId,
    a.ChaveGeral,
    s.SituacaoContrato,
    a.Saldo_A_Receber,
    a.Vencido_Em_Aberto
  FROM aberto a
  LEFT JOIN situacao s USING (ChaveGeral)
)

SELECT
  c.enterpriseId,
  e.companyGroup,
  e.companyName,
  e.projectName,
  e.enterpriseName,

  u.UF,
  es.NomeEstado,
  CONCAT('BR-', u.UF)                                   AS UF_ISO,
  u.Cidade,
  IF(u.Lat IS NULL, NULL,
     CONCAT(CAST(u.Lat AS STRING), ',', CAST(u.Lon AS STRING))) AS LatLong,

  COUNT(*)                                              AS Contratos,
  COUNTIF(c.SituacaoContrato = 'Adimplente')            AS Contratos_Adimplentes,
  COUNTIF(c.SituacaoContrato = 'Atrasado')              AS Contratos_Atrasados,
  COUNTIF(c.SituacaoContrato = 'Inadimplente')          AS Contratos_Inadimplentes,
  ROUND(SUM(c.Saldo_A_Receber), 2)                      AS Saldo_A_Receber,
  ROUND(SUM(c.Vencido_Em_Aberto), 2)                    AS Vencido_Em_Aberto

FROM contrato c
JOIN emp e
  ON e.enterpriseId = c.enterpriseId
LEFT JOIN locais u
  ON STRPOS(UPPER(e.companyGroup), u.chave) > 0
LEFT JOIN estados es
  ON es.UF = u.UF
WHERE e.companyGroup IS NOT NULL
  AND TRIM(e.companyGroup) <> ''
  AND e.companyGroup <> 'Bloko Capital'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- CONFERENCIA: contratos por estado e por empresa
-- (UF vazia = empresa fora da lista do CTE "locais")
-- ####################################################################
-- SELECT
--   IFNULL(UF, '(sem UF)') AS UF,
--   companyGroup,
--   SUM(Contratos)         AS contratos,
--   ROUND(SUM(Saldo_A_Receber)) AS saldo_a_receber
-- FROM `dadosfinanceiro-501613.looker_studio.mapa_estados`
-- GROUP BY 1, 2
-- ORDER BY 1, 3 DESC;