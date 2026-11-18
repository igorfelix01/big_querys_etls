-- ####################################################################
-- LOOKER_STUDIO.RENEGOCIACAO_BASE
-- Pagina Renegociacao - base de todos os graficos da pagina
-- 1o grafico: "Contratos Renegociados - Situacao"
-- + tabela "Detalhamento Renegociacoes", barra "Composicao" e cards
--   SD ReparcMes / Acum. SD Recuperado / SD Recuperado / Acum. Recebido
--   (SDSemJuros = SaldoDevedorSemJuros do titulos_totalizador;
--    SDRecuperado = SDSemJuros so de Adimplente e Quitado;
--    ValorRecebidoAposReneg = db_recebidas[ValorBruto] do contrato com
--    paymentDate >= data do reparcelamento, igual a coluna do BI)
--
-- Visual do BI:
--   Eixo X  : Calendario[Date] (Ano > Mes)  -> data do reparcelamento
--   Colunas : Contagem de Reparcelamento_Analise[ChaveGeral]
--   Legenda : db_titulos_totalizador[SituacaoContrato]
--
-- 1 linha por CONTRATO renegociado (ChaveGeral), com os campos dos
-- filtros da pagina:
--   Periodo          -> DataReparcelamento (UltimaDataReparcelamento)
--   Pesquisa de ID   -> ChaveGeral
--   Status Projeto   -> StatusPerf   (dv_Performados, pelo enterpriseId)
--   Empresa/Projeto  -> companyGroup / companyName (NomeCompanhias,
--                       pelo enterpriseId = centro de custo)
--   CT               -> documentIdentificationId (do titulos_totalizador)
--
-- JA FILTRADO no SQL (vale para todos os graficos da pagina):
--   companyGroup nao e Bloko Capital e nao e em branco
-- O filtro CT (documentIdentificationId = 'CT') fica no Looker.
--
-- SEM periodo no SQL: o periodo e controlado no Looker.
--
-- Depende de: analytics.fato_reparcelamento_analise,
--             analytics.fato_titulos_totalizador,
--             analytics.dim_nome_companhias, analytics.dim_perfomados,
--             analytics.saldo_devedor (RenegociacaoAberta),
--             analytics.fato_renegociacoes (reparcelamento valido no Sienge)
-- ####################################################################

DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.renegociacao_base`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.renegociacao_base`
CLUSTER BY companyGroup, SituacaoContrato
AS

WITH

-- reparcelamentos que EXISTEM HOJE no Sienge (operacao 'Reparcelamento'
-- nas recebidas, carga diaria). Reparcelamento excluido/cancelado no
-- Sienge some daqui no dia seguinte.
reneg_sienge AS (
  SELECT
    CAST(ChaveGeral AS STRING) AS ChaveGeral,
    MAX(paymentDate)           AS UltimaDataSienge
  FROM `dadosfinanceiro-501613.analytics.fato_renegociacoes`
  WHERE ChaveGeral IS NOT NULL
  GROUP BY 1
),

-- contratos do extrato (dados do cliente) que tem reparcelamento valido
-- no Sienge. O extrato (EXTRATO_GERAL_Reparcelamento_Analise.csv) e uma
-- foto tirada no dia em que foi gerado: se o reparcelamento foi excluido
-- depois, ele continuava la. Agora so entra quem o Sienge confirma, e a
-- data do reparcelamento e a ultima valida no Sienge.
reparcelamento AS (
  SELECT
    x.ChaveGeral,
    s.UltimaDataSienge AS UltimaDataReparcelamento,
    x.enterpriseId,
    x.NomeCliente,
    x.Unidade,
    x.CPF,
    x.CNPJ,
    x.Telefone,
    x.Email
  FROM (
    SELECT
      ChaveGeral,
      SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
      NomeCliente,
      Unidade,
      CPF,
      CNPJ,
      Telefone,
      Email
    FROM `dadosfinanceiro-501613.analytics.fato_reparcelamento_analise`
    WHERE ChaveGeral IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral
                               ORDER BY UltimaDataReparcelamento DESC) = 1
  ) x
  JOIN reneg_sienge s
    ON s.ChaveGeral = CAST(x.ChaveGeral AS STRING)
),

nome_companhias AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup,
    companyName,
    projectName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName
  ) = 1
),

performados AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    StatusPerf
  FROM `dadosfinanceiro-501613.analytics.dim_perfomados`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY StatusPerf
  ) = 1
),

titulos AS (
  SELECT
    ChaveGeral,
    ANY_VALUE(SituacaoContrato)         AS SituacaoContrato,
    ANY_VALUE(documentIdentificationId) AS documentIdentificationId,
    ANY_VALUE(MaxAtrasoDias)            AS MaxAtrasoDias,
    ANY_VALUE(PrimeiraDataVencimento)   AS PrimeiraDataVencimento,
    ANY_VALUE(SaldoDevedorSemJuros)     AS SaldoDevedorSemJuros,
    ANY_VALUE(SaldoDevedorComJuros)     AS SaldoDevedorComJuros,
    ANY_VALUE(ValorLiquidoAgregado)     AS ValorLiquidoAgregado,
    ANY_VALUE(subJudicie)               AS subJudicie
  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`
  GROUP BY ChaveGeral
),

-- recebido DEPOIS da renegociacao = coluna ValorRecebidoAposReneg do BI:
--   SUM(db_recebidas[ValorBruto]) do contrato com
--   paymentDate >= UltimaDataReparcelamento  (sem filtro de Conta)
recebido_apos AS (
  SELECT
    rc.ChaveGeral,
    SUM(CAST(rc.ValorBruto AS FLOAT64)) AS ValorRecebidoAposReneg
  FROM `dadosfinanceiro-501613.analytics.fato_recebidas` rc
  JOIN reparcelamento r
    ON r.ChaveGeral = rc.ChaveGeral
  WHERE SAFE_CAST(rc.paymentDate AS DATE) >= r.UltimaDataReparcelamento
  GROUP BY rc.ChaveGeral
),

-- renegociacao ABERTA = o contrato ainda tem parcela a pagar no A Receber
-- (no Sienge o reparcelamento substitui as parcelas em aberto pelas novas,
--  entao as parcelas em aberto hoje sao as da renegociacao) e nao foi
--  distratado. Sem parcela em aberto = renegociacao encerrada (quitada).
parcelas_abertas AS (
  SELECT
    CAST(ChaveGeral AS STRING)                                        AS ChaveGeral,
    COUNT(DISTINCT IF(OrigemBase = 'A Receber',
          CONCAT(CAST(ChaveEspecifica AS STRING), '|', CAST(dueDate AS STRING)), NULL)) AS ParcelasEmAberto,
    COUNT(DISTINCT IF(OrigemBase = 'A Receber'
                        AND dueDate < CURRENT_DATE('America/Sao_Paulo'),
          CONCAT(CAST(ChaveEspecifica AS STRING), '|', CAST(dueDate AS STRING)), NULL)) AS ParcelasVencidasEmAberto,
    MAX(cancellationDate)                                             AS DataDistrato
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`
  WHERE ChaveGeral IS NOT NULL
  GROUP BY 1
)

SELECT
  r.ChaveGeral,
  r.UltimaDataReparcelamento                       AS DataReparcelamento,
  DATE_TRUNC(r.UltimaDataReparcelamento, MONTH)    AS MesReparcelamento,
  EXTRACT(YEAR FROM r.UltimaDataReparcelamento)    AS Ano,

  nc.companyGroup,
  nc.companyName,
  nc.projectName,
  p.StatusPerf,

  t.SituacaoContrato,
  t.documentIdentificationId,

  r.enterpriseId,
  r.NomeCliente,
  r.Unidade,

  -- ===== tabela Detalhamento Renegociacoes =====
  t.MaxAtrasoDias                                  AS Atraso,
  t.PrimeiraDataVencimento                         AS Vencimento,
  ROUND(t.SaldoDevedorComJuros, 2)                 AS SaldoDevedor,
  ROUND(t.ValorLiquidoAgregado, 2)                 AS ValorRecebido,
  t.subJudicie,
  r.CPF,
  r.CNPJ,
  r.Telefone,
  r.Email,

  -- ===== cards =====
  ROUND(t.SaldoDevedorSemJuros, 2)                 AS SDSemJuros,
  ROUND(IF(t.SituacaoContrato IN ('Adimplente', 'Quitado'),
           t.SaldoDevedorSemJuros, 0), 2)          AS SDRecuperado,
  ROUND(IFNULL(ra.ValorRecebidoAposReneg, 0), 2)   AS ValorRecebidoAposReneg,

  -- ===== renegociacao aberta ou encerrada =====
  IF(pa.DataDistrato IS NULL AND IFNULL(pa.ParcelasEmAberto, 0) > 0,
     'Sim', 'Não')                                 AS RenegociacaoAberta,
  CASE
    WHEN pa.DataDistrato IS NOT NULL              THEN 'Encerrada - distratada'
    WHEN IFNULL(pa.ParcelasEmAberto, 0) = 0       THEN 'Encerrada - quitada'
    WHEN pa.ParcelasVencidasEmAberto > 0          THEN 'Aberta - com parcela vencida'
    ELSE                                               'Aberta - em dia'
  END                                              AS StatusRenegociacao,
  IFNULL(pa.ParcelasEmAberto, 0)                   AS ParcelasEmAberto,
  IFNULL(pa.ParcelasVencidasEmAberto, 0)           AS ParcelasVencidasEmAberto,

  1 AS Contratos           -- no Looker: SOMA (= contagem de ChaveGeral)

FROM reparcelamento r
JOIN nome_companhias nc
  ON nc.enterpriseId = r.enterpriseId
LEFT JOIN performados p
  ON p.enterpriseId = r.enterpriseId
LEFT JOIN titulos t
  ON t.ChaveGeral = r.ChaveGeral
LEFT JOIN recebido_apos ra
  ON ra.ChaveGeral = r.ChaveGeral
LEFT JOIN parcelas_abertas pa
  ON pa.ChaveGeral = CAST(r.ChaveGeral AS STRING)
WHERE nc.companyGroup IS NOT NULL
  AND TRIM(nc.companyGroup) <> ''
  AND nc.companyGroup <> 'Bloko Capital';
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]



-- ####################################################################
-- VALIDACAO dos CARDS contra o BI (periodo 01/05/2025 a 24/09/2026)
-- BI: SD ReparcMes 9.850.365 | Acum. SD Recuperado 61.941.721
--     SD Recuperado 35.056.562 | Acum. Recebido Reneg. 60.967.917
-- (linha 1 = so CT; linha 2 = todos os documentos)
-- ####################################################################
-- SELECT
--   IF(documentIdentificationId = 'CT', 'so CT', 'todos')            AS filtro,
--   ROUND(SUM(IF(MesReparcelamento = DATE '2026-09-01', SDSemJuros, 0)))  AS sd_reparc_mes,
--   ROUND(SUM(SDRecuperado))                                          AS acum_sd_recuperado,
--   ROUND(SUM(IF(DataReparcelamento BETWEEN '2025-05-01' AND '2026-09-24',
--                SDRecuperado, 0)))                                   AS sd_recuperado_periodo,
--   ROUND(SUM(ValorRecebidoAposReneg))                                AS acum_recebido_reneg,
--   COUNT(*)                                                          AS contratos
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base`
-- WHERE documentIdentificationId = 'CT'
-- GROUP BY 1
-- UNION ALL
-- SELECT
--   'todos',
--   ROUND(SUM(IF(MesReparcelamento = DATE '2026-09-01', SDSemJuros, 0))),
--   ROUND(SUM(SDRecuperado)),
--   ROUND(SUM(IF(DataReparcelamento BETWEEN '2025-05-01' AND '2026-09-24',
--                SDRecuperado, 0))),
--   ROUND(SUM(ValorRecebidoAposReneg)),
--   COUNT(*)
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base`;

-- ####################################################################
-- CONFERENCIA: renegociacoes abertas x encerradas
-- ####################################################################
-- SELECT StatusRenegociacao, COUNT(*) AS contratos, ROUND(SUM(SaldoDevedor), 2) AS saldo_devedor
-- FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base`
-- WHERE documentIdentificationId = 'CT'
-- GROUP BY 1
-- ORDER BY 1;
