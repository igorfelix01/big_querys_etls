-- [otimizacao] CTE 'contrato' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE contrato AS
  SELECT

    CAST(ChaveGeral AS STRING)    AS ChaveGeral,

    ANY_VALUE(groupCompanyName)   AS groupCompanyName,

    ANY_VALUE(companyName)        AS companyName,

    ANY_VALUE(costCenterName)     AS costCenterName,

    ANY_VALUE(subJudicie)         AS subJudicie,

    ANY_VALUE(contractDate)       AS contractDate,

    ANY_VALUE(cancellationDate)   AS cancellationDate,

    ANY_VALUE(totalSellingValue)  AS totalSellingValue

  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

  WHERE documentIdentificationId = 'CT'

    AND contractDate IS NOT NULL

    AND IFNULL(TRIM(groupCompanyName), '') <> ''

    AND NOT REGEXP_CONTAINS(

          UPPER(CONCAT(IFNULL(groupCompanyName, ''), ' ', IFNULL(companyName, ''))),

          r'BLOKO')

  GROUP BY 1;

-- ####################################################################

-- SAFRA DE VENDAS: QUAIS VENDAS DAO MAIS PROBLEMA

--

-- Pergunta: dos contratos vendidos em cada ano (safra), quantos % ja

-- tinham virado INADIMPLENTES (90+ dias de atraso) ou DISTRATADOS

-- depois de 6, 12, 24, 36... meses da venda?

--

-- Comparar as safras no MESMO tempo de vida (ex.: 12 meses apos a

-- venda) mostra se as vendas estao ficando melhores ou piores, e em

-- qual empreendimento.

--

-- Cria:

--   looker_studio.safra_vendas_resumo  (1o, 2o e 3o ano - mais facil no Looker)

--   looker_studio.safra_vendas_curva

--     grupo x empresa x empreendimento x ano da venda x meses desde a venda

--     -> Contratos (observados naquele tempo de vida), Inadimplentes,

--        Distratados, InadimplentesOuDistratados (acumulados ate o mes)

--     Looker: SOMA(InadimplentesOuDistratados)/SOMA(Contratos)

--

-- Regras:

--   Safra = ano do contractDate (data da venda).

--   Inadimplente = 1o dia com 90+ dias de atraso (HistoricoInadimplencia),

--   so antes do distrato (depois do distrato as parcelas canceladas

--   apareceriam como "abertas").

--   Uma safra so entra no mes K de vida se ja passaram K meses desde a

--   venda (safras novas aparecem so nos primeiros meses).

--   Universo: CT, sem empresas Bloko. subJudicie vem como coluna para

--   filtrar no Looker (aqui NAO e excluido: processo judicial costuma

--   ser consequencia da inadimplencia).

--   Sem periodo fixo: filtrar AnoVenda / DataVenda no Looker.

--

-- Depende de: analytics.fato_titulos_totalizador, analytics.HistoricoInadimplencia

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.safra_vendas_curva`

CLUSTER BY groupCompanyName, AnoVenda

AS
WITH
hoje AS (

  SELECT MAX(Data) AS d

  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`

),

primeiro_90 AS (

  SELECT

    CAST(h.ChaveGeral AS STRING) AS ChaveGeral,

    MIN(h.Data)                  AS data_90

  FROM `dadosfinanceiro-501613.analytics.HistoricoInadimplencia` h

  JOIN contrato c

    ON c.ChaveGeral = CAST(h.ChaveGeral AS STRING)

  WHERE h.DiasAtraso >= 90

    AND h.Data < IFNULL(c.cancellationDate, DATE '9999-12-31')

  GROUP BY 1

),

base AS (

  SELECT

    c.*,

    DATE_DIFF(p.data_90, c.contractDate, MONTH)          AS meses_ate_90,

    DATE_DIFF(c.cancellationDate, c.contractDate, MONTH) AS meses_ate_distrato,

    DATE_DIFF(h.d, c.contractDate, MONTH)                AS meses_de_vida

  FROM contrato c

  CROSS JOIN hoje h

  LEFT JOIN primeiro_90 p USING (ChaveGeral)

  WHERE c.contractDate <= h.d

)
SELECT

  groupCompanyName,

  companyName,

  costCenterName,

  subJudicie,

  EXTRACT(YEAR FROM contractDate)                               AS AnoVenda,

  DATE(EXTRACT(YEAR FROM contractDate), 1, 1)                   AS DataVenda,

  k                                                             AS MesesDesdeVenda,

  COUNT(*)                                                      AS Contratos,

  COUNTIF(meses_ate_90 <= k)                                    AS Inadimplentes,

  COUNTIF(meses_ate_distrato <= k)                              AS Distratados,

  COUNTIF(meses_ate_90 <= k OR meses_ate_distrato <= k)         AS InadimplentesOuDistratados,

  ROUND(SUM(totalSellingValue), 2)                              AS VGV,

  ROUND(SUM(IF(meses_ate_90 <= k OR meses_ate_distrato <= k,

               totalSellingValue, 0)), 2)                       AS VGVComProblema

FROM base,

UNNEST(GENERATE_ARRAY(0, GREATEST(meses_de_vida, 0))) AS k

GROUP BY 1, 2, 3, 4, 5, 6, 7;





-- ####################################################################

-- RESUMO: 1o, 2o e 3o ano de contrato (para tabela / barras no Looker)

--   1 linha por grupo x empresa x empreendimento x ano da venda x ano

--   de contrato (12, 24 e 36 meses depois da venda).

--   So entram as safras que ja completaram aquele ano de contrato.

--   Looker: SOMA(InadimplentesOuDistratados)/SOMA(Contratos)

-- ####################################################################

CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.safra_vendas_resumo`

CLUSTER BY groupCompanyName, AnoVenda

AS

SELECT

  groupCompanyName,

  companyName,

  costCenterName,

  subJudicie,

  AnoVenda,

  DataVenda,

  CAST(MesesDesdeVenda / 12 AS INT64)                 AS AnoDeContratoNum,

  CONCAT(CAST(CAST(MesesDesdeVenda / 12 AS INT64) AS STRING), 'º ano') AS AnoDeContrato,

  Contratos,

  Inadimplentes,

  Distratados,

  InadimplentesOuDistratados,

  VGV,

  VGVComProblema

FROM `dadosfinanceiro-501613.looker_studio.safra_vendas_curva`

WHERE MesesDesdeVenda IN (12, 24, 36);
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- RESULTADO RAPIDO: % com problema aos 12 e 24 meses, por safra

-- ####################################################################

-- SELECT

--   AnoVenda,

--   SUM(IF(MesesDesdeVenda = 12, Contratos, 0))                                   AS contratos_12m,

--   ROUND(100 * SAFE_DIVIDE(SUM(IF(MesesDesdeVenda = 12, InadimplentesOuDistratados, 0)),

--                           SUM(IF(MesesDesdeVenda = 12, Contratos, 0))), 1)      AS pct_problema_12m,

--   ROUND(100 * SAFE_DIVIDE(SUM(IF(MesesDesdeVenda = 24, InadimplentesOuDistratados, 0)),

--                           SUM(IF(MesesDesdeVenda = 24, Contratos, 0))), 1)      AS pct_problema_24m

-- FROM `dadosfinanceiro-501613.looker_studio.safra_vendas_curva`

-- GROUP BY 1

-- ORDER BY 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]




-- por empreendimento: % com problema no 1o, 2o e 3o ano (todas as safras)

-- SELECT

--   groupCompanyName,

--   costCenterName,

--   ROUND(100 * SAFE_DIVIDE(SUM(IF(AnoDeContratoNum = 1, InadimplentesOuDistratados, 0)),

--                           SUM(IF(AnoDeContratoNum = 1, Contratos, 0))), 1) AS pct_1o_ano,

--   ROUND(100 * SAFE_DIVIDE(SUM(IF(AnoDeContratoNum = 2, InadimplentesOuDistratados, 0)),

--                           SUM(IF(AnoDeContratoNum = 2, Contratos, 0))), 1) AS pct_2o_ano,

--   ROUND(100 * SAFE_DIVIDE(SUM(IF(AnoDeContratoNum = 3, InadimplentesOuDistratados, 0)),

--                           SUM(IF(AnoDeContratoNum = 3, Contratos, 0))), 1) AS pct_3o_ano,

--   SUM(IF(AnoDeContratoNum = 1, Contratos, 0))                             AS contratos_com_1_ano

-- FROM `dadosfinanceiro-501613.looker_studio.safra_vendas_resumo`

-- GROUP BY 1, 2

-- HAVING contratos_com_1_ano >= 20

-- ORDER BY pct_1o_ano DESC;