-- ####################################################################

-- LOOKER_STUDIO.HISTORICO_CLIENTE

-- Tabela da pagina "Historico Cliente": 1 linha por contrato.

--

-- Colunas (de onde vem cada uma):

--   ChaveGeral              analytics.saldo_devedor        (lista de contratos)

--   SituacaoContrato        analytics.fato_contratos_ativos (Contratos Ativos);

--                           se o contrato nao esta la ou veio '-', usa a

--                           SituacaoContrato do db_titulos_totalizador

--                           (coluna OrigemSituacao mostra de onde veio)

--   Cliente                 nome do cliente: fato_titulos_totalizador.clientName

--                           (se vazio, o nome da venda em fato_contratos_ativos)

--   MaxAtrasoDias           analytics.fato_titulos_totalizador

--   PrimeiraDataVencimento  analytics.fato_titulos_totalizador = vencimento da

--                           parcela EM ABERTO mais antiga (vazio se o contrato

--                           nao tem parcela em aberto: quitado ou distratado)

--   UltimaDataVencimento    vencimento da ULTIMA parcela do contrato

--                           (saldo_devedor, todas as parcelas, pagas ou nao)

--   SaldoDevedorComJuros    analytics.fato_titulos_totalizador

--   ValorLiquidoAgregado    analytics.fato_titulos_totalizador

--   QtdRenegociacoes        analytics.fato_renegociacoes: quantas vezes o

--                           contrato foi renegociado (0 = nunca)

--   QtdRenegociacoesCliente soma de todos os contratos do mesmo cliente

--   DataUltimaRenegociacao  data do ultimo reparcelamento

-- + campos para os filtros do Looker: companyGroup, companyName,

--   enterpriseName (dim_nome_companhias pelo centro de custo),

--   documentIdentificationId, subJudicie.

--

-- Sem filtro de periodo, de empresa ou de documento no SQL: os filtros

-- ficam no Looker (ex.: documentIdentificationId = CT).

--

-- Depende de: analytics.saldo_devedor, analytics.fato_contratos_ativos,

--             analytics.fato_titulos_totalizador, analytics.dim_nome_companhias

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.historico_cliente`

CLUSTER BY companyGroup, ChaveGeral

AS



WITH



contratos AS (

  SELECT

    CAST(ChaveGeral AS STRING)                                            AS ChaveGeral,

    ANY_VALUE(SAFE_CAST(SAFE_CAST(CAST(costCenterId AS STRING) AS FLOAT64) AS INT64)) AS costCenterId,

    ANY_VALUE(documentIdentificationId)                                   AS documentIdentificationId,

    MAX(subJudicie)                                                       AS subJudicie,

    MIN(IF(OrigemBase = 'A Receber', dueDate, NULL))                      AS PrimeiroVencimentoAberto,

    MAX(dueDate)                                                          AS UltimoVencimentoContrato

  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`

  WHERE ChaveGeral IS NOT NULL

  GROUP BY 1

),



ativos AS (

  SELECT

    CAST(ChaveGeral AS STRING)          AS ChaveGeral,

    ANY_VALUE(SituacaoContrato)         AS SituacaoContrato,

    ANY_VALUE(COALESCE(names, name))    AS NomeVenda

  FROM `dadosfinanceiro-501613.analytics.fato_contratos_ativos`

  GROUP BY 1

),



titulos AS (

  SELECT

    CAST(ChaveGeral AS STRING)          AS ChaveGeral,

    ANY_VALUE(clientName)               AS clientName,

    ANY_VALUE(ChaveClientes)            AS ChaveClientes,

    ANY_VALUE(SituacaoContrato)         AS SituacaoTitulos,

    ANY_VALUE(MaxAtrasoDias)            AS MaxAtrasoDias,

    ANY_VALUE(PrimeiraDataVencimento)   AS PrimeiraDataVencimento,

    ANY_VALUE(SaldoDevedorComJuros)     AS SaldoDevedorComJuros,

    ANY_VALUE(ValorLiquidoAgregado)     AS ValorLiquidoAgregado

  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

  GROUP BY 1

),



-- renegociacoes (reparcelamentos) de cada contrato: 1 por data de reparcelamento

-- (mesma contagem do qtd_renegociacoes_totais do BI)

reneg AS (

  SELECT

    CAST(ChaveGeral AS STRING)          AS ChaveGeral,

    MAX(qtd_renegociacoes_totais)       AS QtdRenegociacoes,

    MAX(paymentDate)                    AS DataUltimaRenegociacao

  FROM `dadosfinanceiro-501613.analytics.fato_renegociacoes`

  GROUP BY 1

),



empresas AS (

  SELECT

    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,

    companyGroup,

    companyName,

    enterpriseName

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  WHERE enterpriseId IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (

    PARTITION BY SAFE_CAST(enterpriseId AS INT64)

    ORDER BY companyGroup, companyName, enterpriseName) = 1

)



SELECT

  c.ChaveGeral,

  -- Contratos Ativos; se o contrato nao esta la (ou veio '-'), usa a

  -- situacao do db_titulos_totalizador (Adimplente/Atrasado/Inadimplente/

  -- Quitado/Distratado)

  COALESCE(NULLIF(TRIM(a.SituacaoContrato), '-'), t.SituacaoTitulos) AS SituacaoContrato,

  CASE

    WHEN NULLIF(TRIM(a.SituacaoContrato), '-') IS NOT NULL THEN 'Contratos Ativos'

    WHEN t.SituacaoTitulos IS NOT NULL                     THEN 'db_titulos_totalizador'

  END                                                                AS OrigemSituacao,

  COALESCE(t.clientName, a.NomeVenda)   AS Cliente,

  t.MaxAtrasoDias,

  -- parcela EM ABERTO mais antiga (igual ao db_titulos_totalizador do BI);

  -- vazio quando o contrato nao tem parcela em aberto (quitado/distratado)

  COALESCE(t.PrimeiraDataVencimento, c.PrimeiroVencimentoAberto) AS PrimeiraDataVencimento,

  -- vencimento da ULTIMA parcela do contrato (todas as parcelas, pagas ou nao)

  c.UltimoVencimentoContrato                                    AS UltimaDataVencimento,

  t.SaldoDevedorComJuros,

  t.ValorLiquidoAgregado,



  -- quantas vezes o CONTRATO foi renegociado (0 = nunca)

  IFNULL(r.QtdRenegociacoes, 0)                                 AS QtdRenegociacoes,

  -- soma das renegociacoes de TODOS os contratos do mesmo cliente

  SUM(IFNULL(r.QtdRenegociacoes, 0)) OVER (

    PARTITION BY IFNULL(t.ChaveClientes, c.ChaveGeral))         AS QtdRenegociacoesCliente,

  r.DataUltimaRenegociacao,



  -- filtros

  e.companyGroup,

  e.companyName,

  e.enterpriseName,

  c.documentIdentificationId,

  c.subJudicie

FROM contratos c

LEFT JOIN ativos   a USING (ChaveGeral)

LEFT JOIN titulos  t USING (ChaveGeral)

LEFT JOIN reneg    r USING (ChaveGeral)

LEFT JOIN empresas e ON e.enterpriseId = c.costCenterId;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA

--   1 linha por contrato (linhas = contratos) e totais por situacao

-- ####################################################################

-- SELECT

--   SituacaoContrato,

--   COUNT(*)                            AS linhas,

--   COUNT(DISTINCT ChaveGeral)          AS contratos,

--   ROUND(SUM(SaldoDevedorComJuros), 2) AS saldo_devedor_com_juros,

--   ROUND(SUM(ValorLiquidoAgregado), 2) AS valor_liquido_agregado

-- FROM `dadosfinanceiro-501613.looker_studio.historico_cliente`

-- GROUP BY 1

-- ORDER BY 2 DESC;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]




-- por que PrimeiraDataVencimento vem vazia: contratos sem parcela em aberto

-- SELECT

--   PrimeiraDataVencimento IS NULL              AS primeira_data_vazia,

--   SaldoDevedorComJuros IS NULL OR SaldoDevedorComJuros = 0 AS sem_saldo,

--   COUNT(*)                                    AS contratos

-- FROM `dadosfinanceiro-501613.looker_studio.historico_cliente`

-- GROUP BY 1, 2

-- ORDER BY 1, 2;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]




-- de onde veio a situacao de cada contrato

-- SELECT OrigemSituacao, SituacaoContrato, COUNT(*) AS contratos

-- FROM `dadosfinanceiro-501613.looker_studio.historico_cliente`

-- GROUP BY 1, 2

-- ORDER BY 1, 3 DESC;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]




-- renegociacoes: quantos contratos por numero de renegociacoes

-- SELECT QtdRenegociacoes, COUNT(*) AS contratos

-- FROM `dadosfinanceiro-501613.looker_studio.historico_cliente`

-- GROUP BY 1

-- ORDER BY 1;