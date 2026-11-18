-- ####################################################################
-- CONCENTRACAO DO RISCO: QUANTO DO DINHEIRO ESTA EM POUCOS CLIENTES
--
-- Pergunta: quanto do saldo a receber (e do vencido) esta nos 10, 50,
-- 100 maiores clientes de cada empresa? Esses grandes clientes estao
-- em dia ou atrasados?
--
-- Por que importa: se poucos clientes concentram muito saldo, um unico
-- atraso grande pesa no caixa (ex.: Inlot com 13 mi em risco e pouco
-- vencido). Esses clientes merecem acompanhamento individual.
--
-- Cliente = CPF (ou CNPJ; sem documento -> ChaveClientes). Um cliente
-- com varios contratos e somado.
-- Ranking feito DENTRO de cada grupo (RankNoGrupo) e na carteira
-- inteira (RankGeral), pelo saldo em aberto.
--
-- Cria:
--   looker_studio.concentracao_risco
--     1 linha por cliente x grupo: contratos, saldo em aberto, vencido,
--     maior atraso hoje, situacao, ranking, % acumulado (curva de Pareto)
--     e FaixaRanking (Top 10 / 11-50 / 51-100 / Demais)
--
-- Universo: CT, sem empresas Bloko, sem distratados, saldo > 0.
-- subJudicie vem como coluna (filtro no Looker).
-- "Hoje" = ultimo dia do analytics.HistoricoInadimplencia.
--
-- Depende de: analytics.fato_titulos_totalizador, analytics.saldo_devedor,
--             analytics.HistoricoInadimplencia
-- ####################################################################

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.concentracao_risco`
CLUSTER BY groupCompanyName
AS

WITH

hoje AS (
  SELECT MAX(Data) AS d
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`
),

contrato AS (
  SELECT
    CAST(ChaveGeral AS STRING)       AS ChaveGeral,
    ANY_VALUE(groupCompanyName)      AS groupCompanyName,
    ANY_VALUE(companyName)           AS companyName,
    ANY_VALUE(costCenterName)        AS costCenterName,
    ANY_VALUE(clientName)            AS clientName,
    ANY_VALUE(Telefone)              AS Telefone,
    ANY_VALUE(subJudicie)            AS subJudicie,
    ANY_VALUE(SituacaoContrato)      AS SituacaoContrato,
    ANY_VALUE(SaldoDevedorComJuros)  AS SaldoEmAberto,
    COALESCE(NULLIF(TRIM(ANY_VALUE(CPF)), ''),
             NULLIF(TRIM(ANY_VALUE(CNPJ)), ''),
             ANY_VALUE(ChaveClientes))  AS DocCliente
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  WHERE documentIdentificationId = 'CT'
    AND cancellationDate IS NULL
    AND IFNULL(TRIM(groupCompanyName), '') <> ''
    AND NOT REGEXP_CONTAINS(
          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),
          r'BLOKO')
  GROUP BY 1
  HAVING IFNULL(ANY_VALUE(SaldoDevedorComJuros), 0) > 0
),

vencido AS (
  SELECT
    CAST(s.ChaveGeral AS STRING) AS ChaveGeral,
    SUM(s.ValorBruto)            AS ValorVencido
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor` s, hoje
  WHERE s.OrigemBase = 'A Receber'
    AND s.dueDate < hoje.d
  GROUP BY 1
),

atraso AS (
  SELECT CAST(h.ChaveGeral AS STRING) AS ChaveGeral, h.DiasAtraso
  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h, hoje
  WHERE h.Data = hoje.d
),

cliente AS (
  SELECT
    c.groupCompanyName,
    c.DocCliente,
    ANY_VALUE(c.clientName)                          AS clientName,
    ANY_VALUE(c.Telefone)                            AS Telefone,
    STRING_AGG(DISTINCT c.companyName, ' | ')        AS Empresas,
    STRING_AGG(DISTINCT c.costCenterName, ' | ')     AS Empreendimentos,
    MAX(c.subJudicie)                                AS subJudicie,
    COUNT(*)                                         AS Contratos,
    SUM(c.SaldoEmAberto)                             AS SaldoEmAberto,
    SUM(IFNULL(v.ValorVencido, 0))                   AS ValorVencido,
    MAX(IFNULL(a.DiasAtraso, 0))                     AS MaiorAtrasoHoje
  FROM contrato c
  LEFT JOIN vencido v USING (ChaveGeral)
  LEFT JOIN atraso  a USING (ChaveGeral)
  GROUP BY 1, 2
),

ranking AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY groupCompanyName ORDER BY SaldoEmAberto DESC, DocCliente) AS RankNoGrupo,
    ROW_NUMBER() OVER (ORDER BY SaldoEmAberto DESC, groupCompanyName, DocCliente)             AS RankGeral,
    SUM(SaldoEmAberto) OVER (PARTITION BY groupCompanyName)                                AS SaldoGrupo,
    SUM(SaldoEmAberto) OVER (PARTITION BY groupCompanyName ORDER BY SaldoEmAberto DESC, DocCliente
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)            AS SaldoAcumGrupo,
    SUM(SaldoEmAberto) OVER ()                                                             AS SaldoTotal,
    SUM(SaldoEmAberto) OVER (ORDER BY SaldoEmAberto DESC, groupCompanyName, DocCliente
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)            AS SaldoAcumGeral,
    COUNT(*) OVER (PARTITION BY groupCompanyName)                                          AS ClientesGrupo
  FROM cliente
)

SELECT
  groupCompanyName,
  DocCliente                                                   AS DocumentoCliente,
  clientName,
  Telefone,
  Empresas,
  Empreendimentos,
  subJudicie,
  Contratos,
  ROUND(SaldoEmAberto, 2)                                      AS SaldoEmAberto,
  ROUND(ValorVencido, 2)                                       AS ValorVencido,
  MaiorAtrasoHoje,
  CASE
    WHEN MaiorAtrasoHoje = 0  THEN '1. Em dia'
    WHEN MaiorAtrasoHoje < 90 THEN '2. Atrasado'
    ELSE                           '3. Inadimplente'
  END                                                          AS SituacaoHoje,
  RankNoGrupo,
  CASE
    WHEN RankNoGrupo <= 10  THEN '1. Top 10'
    WHEN RankNoGrupo <= 50  THEN '2. Top 11-50'
    WHEN RankNoGrupo <= 100 THEN '3. Top 51-100'
    ELSE                         '4. Demais'
  END                                                          AS FaixaRanking,
  ROUND(SAFE_DIVIDE(SaldoEmAberto, SaldoGrupo), 6)             AS PctDoSaldoGrupo,
  ROUND(SAFE_DIVIDE(SaldoAcumGrupo, SaldoGrupo), 6)            AS PctAcumuladoGrupo,
  ROUND(SAFE_DIVIDE(RankNoGrupo, ClientesGrupo), 6)            AS PctClientesGrupo,
  RankGeral,
  ROUND(SAFE_DIVIDE(SaldoAcumGeral, SaldoTotal), 6)            AS PctAcumuladoGeral,
  (SELECT d FROM hoje)                                         AS DataReferencia
FROM ranking;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- RESULTADO RAPIDO
-- ####################################################################

-- (1) quanto do saldo esta em cada faixa de clientes, por grupo
-- SELECT
--   groupCompanyName,
--   FaixaRanking,
--   COUNT(*)                                                         AS clientes,
--   ROUND(SUM(SaldoEmAberto))                                        AS saldo_em_aberto,
--   ROUND(100 * SUM(PctDoSaldoGrupo), 1)                             AS pct_do_saldo_do_grupo,
--   ROUND(SUM(ValorVencido))                                         AS vencido,
--   COUNTIF(SituacaoHoje <> '1. Em dia')                             AS clientes_atrasados
-- FROM `dadosfinanceiro-501613.looker_studio.concentracao_risco`
-- GROUP BY 1, 2
-- ORDER BY 1, 2;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]


-- (2) os 20 maiores clientes da carteira e a situacao deles hoje
-- SELECT
--   RankGeral, groupCompanyName, clientName, Contratos,
--   SaldoEmAberto, ValorVencido, MaiorAtrasoHoje, SituacaoHoje
-- FROM `dadosfinanceiro-501613.looker_studio.concentracao_risco`
-- ORDER BY RankGeral
-- LIMIT 20;