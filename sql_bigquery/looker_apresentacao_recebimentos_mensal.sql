-- ####################################################################
-- LOOKER_STUDIO.APRESENTACAO_RECEBIMENTOS_MENSAL
-- Grafico "Recebiveis" da pagina Apresentacao COM a linha
-- "# Contratos Recebidos" (igual ao BI).
--
-- Por que uma tabela nova: no Looker, grafico com "dimensao detalhada"
-- (SituacaoParcelaVisual) nao aceita uma linha extra. Aqui cada situacao
-- vira uma COLUNA de valor -> grafico de combinacao com 7 barras
-- empilhadas + 1 linha (contratos) no eixo direito.
--
-- MESMA regra e MESMOS valores da apresentacao_recebimentos:
--   Conta = Efeito Caixa, empresa pelo centro de custo, sem Bloko,
--   companyGroup nao vazio. Valor = ValorBruto (visao Bruto).
-- ContratosRecebidos: contratos (ChaveGeral) com recebimento no mes.
--   Marca 1 so no PRIMEIRO pagamento do contrato no mes -> a SOMA no
--   Looker da a contagem distinta do mes (com qualquer filtro de
--   empresa / documento / subJudicie).
-- No Looker: filtro documentIdentificationId = CT (igual a pagina).
-- SEM periodo no SQL.
--
-- Depende de: looker_studio.recebiveis_situacao_parcela,
--             analytics.dim_nome_companhias
-- ####################################################################

DROP TABLE IF EXISTS
  `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos_mensal`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos_mensal`
CLUSTER BY companyGroup, documentIdentificationId
AS
WITH
nome_companhias AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup,
    companyName,
    enterpriseName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName
  ) = 1
),
base AS (
  SELECT
    SAFE_CAST(sd.paymentDate AS DATE)                    AS DataPagamento,
    CAST(sd.ChaveGeral AS STRING)                        AS ChaveGeral,
    nc.companyGroup,
    nc.companyName,
    nc.enterpriseName,
    CAST(sd.documentIdentificationId AS STRING)          AS documentIdentificationId,
    CAST(sd.subJudicie AS STRING)                        AS subJudicie,
    LOWER(NORMALIZE(CAST(sd.SituacaoParcelaVisual AS STRING), NFD)) AS sit,
    CAST(sd.ValorBruto AS FLOAT64)                       AS valor
  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` sd
  JOIN nome_companhias nc
    ON nc.enterpriseId = SAFE_CAST(sd.costCenterId AS INT64)
  WHERE sd.Conta = 'Efeito Caixa'
    AND sd.paymentDate IS NOT NULL
    AND nc.companyGroup IS NOT NULL
    AND TRIM(nc.companyGroup) <> ''
    AND nc.companyGroup <> 'Bloko Capital'
),
marcado AS (
  SELECT
    *,
    -- 1 no primeiro pagamento de cada contrato em cada mes
    IF(ChaveGeral IS NOT NULL
       AND ROW_NUMBER() OVER (
             PARTITION BY ChaveGeral, DATE_TRUNC(DataPagamento, MONTH)
             ORDER BY DataPagamento) = 1, 1, 0) AS primeiro_no_mes
  FROM base
)
SELECT
  DataPagamento,
  DATE_TRUNC(DataPagamento, MONTH)                                AS MesAnoPagamento,
  EXTRACT(YEAR FROM DataPagamento)                                AS AnoPagamento,
  companyGroup,
  companyName,
  enterpriseName,
  documentIdentificationId,
  subJudicie,
  ROUND(SUM(IF(STARTS_WITH(sit, 'adimpl'),    valor, 0)), 2)      AS Adimplente,
  ROUND(SUM(IF(STARTS_WITH(sit, 'atras'),     valor, 0)), 2)      AS Atrasado,
  ROUND(SUM(IF(STARTS_WITH(sit, 'quita'),     valor, 0)), 2)      AS Quitacao,
  ROUND(SUM(IF(STARTS_WITH(sit, 'inadimpl'),  valor, 0)), 2)      AS Inadimplente,
  ROUND(SUM(IF(STARTS_WITH(sit, 'antecip'),   valor, 0)), 2)      AS Antecipado,
  ROUND(SUM(IF(STARTS_WITH(sit, 'venda'),     valor, 0)), 2)      AS VendaAVista,
  ROUND(SUM(IF(STARTS_WITH(sit, 'ato'),       valor, 0)), 2)      AS Ato,
  ROUND(SUM(IF(sit IS NULL
               OR NOT REGEXP_CONTAINS(sit, r'^(adimpl|atras|quita|inadimpl|antecip|venda|ato)'),
               valor, 0)), 2)                                      AS OutrasSituacoes,
  ROUND(SUM(valor), 2)                                            AS Valor_Bruto,
  SUM(primeiro_no_mes)                                            AS ContratosRecebidos
FROM marcado
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;


-- ####################################################################
-- CONFERENCIA (rodar na mao): total por mes deve bater com a
-- apresentacao_recebimentos (CT) e OutrasSituacoes deve ser 0
-- ####################################################################
-- SELECT
--   MesAnoPagamento,
--   ROUND(SUM(Valor_Bruto))       AS recebido,
--   ROUND(SUM(OutrasSituacoes))   AS outras,
--   SUM(ContratosRecebidos)       AS contratos
-- FROM `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos_mensal`
-- WHERE documentIdentificationId = 'CT'
--   AND MesAnoPagamento >= DATE '2025-09-01'
-- GROUP BY 1
-- ORDER BY 1;
