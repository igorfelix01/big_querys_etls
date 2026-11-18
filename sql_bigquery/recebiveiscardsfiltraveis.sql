-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_CARDS_MENSAL_FILTRAVEL

--

-- Substitui recebiveis_cards_situacao_v1 / gauge_v2 / gauge_v4 no Looker

-- (medidor "Mes atual vs. Minimo, Media e Maximo" e cards Media

-- Adimplentes / Atrasados / Inadimplentes / MediaContratos), agora

-- FILTRAVEL por Empresa, Projeto, Empreendimento e subJudicie.

--

-- Por que a tabela antiga nao filtrava: ela ja vinha com Minimo / Media /

-- Maximo calculados para a carteira inteira (sem empresa nem projeto).

-- Aqui a tabela guarda o VALOR DE CADA MES, aberto por empresa/projeto,

-- e o Looker faz a conta depois de aplicar os filtros:

--   Recebiveis Mes Passado = SOMA(Valor_MesPassado)

--   Media                  = SOMA(Valor) / CONTAGEM_DISTINTA(MesPagamento)

--   Minimo / Maximo        = tabela de 1 linha por MesPagamento ordenada

--                            (menor / maior mes)  -> ver LEIA-ME abaixo

--

-- Regras iguais a recebiveis_cards_situacao_v1 (DAX RecebiveisMesPassado):

--   Mes = paymentYear/paymentMonth

--   Acumulado ate o dia: NumeroDiaDaSemana <= DiaParametro (31 = mes todo)

--   No Looker: controle "Dias" = lista suspensa no campo DiaParametro,

--   SELECAO UNICA, padrao 31 (cada linha ja e o acumulado ate aquele dia;

--   sem selecionar 1 dia so, os valores somariam 31 vezes).

--   documentIdentificationId = 'CT', Conta = 'Efeito Caixa',

--   companyGroup sem 'Bloko Capital' e sem vazio

--   Situacoes: Adimplente, Atrasado, Inadimplente, Antecipado, Quitacao,

--              Venda a vista, Ato

-- SEM periodo fixo no SQL: o periodo da media e do min/max e o filtro de

-- data do Looker (campo MesPagamento). EhMesFechado tira o mes corrente.

--

-- Projeto/Empreendimento: costCenterId -> dim_empreendimentos_vendas

--   (projectName / enterpriseName, os mesmos do seletor "Projeto").

--

-- Depende de: looker_studio.recebiveis_situacao_parcela,

--             analytics.dim_empreendimentos_vendas

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_cards_mensal_filtravel`;-- [otimizacao] CTE 'base' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base AS
WITH
empreendimentos AS (

  SELECT

    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,

    ANY_VALUE(companyName)           AS companyName,

    ANY_VALUE(projectName)           AS projectName,

    ANY_VALUE(enterpriseName)        AS enterpriseName

  FROM `dadosfinanceiro-501613.analytics.dim_empreendimentos_vendas`

  WHERE SAFE_CAST(enterpriseId AS INT64) IS NOT NULL

  GROUP BY 1

)
SELECT * FROM (


  SELECT

    DATE(rsp.paymentYear, rsp.paymentMonth, 1)       AS MesPagamento,

    SAFE_CAST(rsp.NumeroDiaDaSemana AS INT64)        AS DiaPagamento,

    rsp.companyGroup,

    e.companyName,

    e.projectName,

    e.enterpriseName,

    rsp.subJudicie,

    rsp.SituacaoParcelaVisual,

    CAST(rsp.ChaveGeral AS STRING)                   AS ChaveGeral,

    IFNULL(rsp.ValorBruto_EfeitoCaixa, 0)            AS ValorBruto,

    IFNULL(rsp.ValorBloko_EfeitoCaixa, 0)            AS ValorBloko,

    IFNULL(rsp.ValorParceiro_EfeitoCaixa, 0)         AS ValorParceiro

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` rsp

  LEFT JOIN empreendimentos e

    ON e.enterpriseId = SAFE_CAST(SAFE_CAST(CAST(rsp.costCenterId AS STRING) AS FLOAT64) AS INT64)

  WHERE rsp.paymentYear IS NOT NULL

    AND rsp.paymentMonth IS NOT NULL

    AND rsp.documentIdentificationId = 'CT'

    AND rsp.Conta = 'Efeito Caixa'

    AND rsp.companyGroup IS NOT NULL

    AND TRIM(rsp.companyGroup) <> ''

    AND rsp.companyGroup <> 'Bloko Capital'

    AND rsp.SituacaoParcelaVisual IN (

      'Adimplente', 'Atrasado', 'Inadimplente', 'Antecipado',

      'Quitação', 'Venda à vista', 'Ato'

    )


);

-- [otimizacao] CTE 'contratos' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE contratos AS
WITH
dias AS (

  SELECT dia AS DiaParametro

  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS dia

),

contrato_dia AS (

  SELECT

    MesPagamento, companyGroup, companyName, projectName,

    enterpriseName, subJudicie, SituacaoParcelaVisual, ChaveGeral,

    MIN(DiaPagamento) AS PrimeiroDia

  FROM base

  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8

)
SELECT * FROM (


  SELECT

    d.DiaParametro,

    c.MesPagamento, c.companyGroup, c.companyName, c.projectName,

    c.enterpriseName, c.subJudicie, c.SituacaoParcelaVisual,

    COUNT(*) AS Contratos

  FROM dias d

  JOIN contrato_dia c

    ON c.PrimeiroDia <= d.DiaParametro

  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8


);





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_cards_mensal_filtravel`

CLUSTER BY DiaParametro, companyGroup, projectName

AS
WITH
hoje AS (

  SELECT

    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual,

    DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH),

             INTERVAL 1 MONTH)                           AS mes_passado

),

dias AS (

  SELECT dia AS DiaParametro

  FROM UNNEST(GENERATE_ARRAY(1, 31)) AS dia

),

valor_dia AS (

  SELECT

    MesPagamento, DiaPagamento, companyGroup, companyName, projectName,

    enterpriseName, subJudicie, SituacaoParcelaVisual,

    SUM(ValorBruto)    AS ValorBruto,

    SUM(ValorBloko)    AS ValorBloko,

    SUM(ValorParceiro) AS ValorParceiro

  FROM base

  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8

),

valores AS (

  SELECT

    d.DiaParametro,

    v.MesPagamento, v.companyGroup, v.companyName, v.projectName,

    v.enterpriseName, v.subJudicie, v.SituacaoParcelaVisual,

    SUM(v.ValorBruto)    AS Valor,

    SUM(v.ValorBloko)    AS Valor_Bloko,

    SUM(v.ValorParceiro) AS Valor_Parceiro

  FROM dias d

  JOIN valor_dia v

    ON v.DiaPagamento <= d.DiaParametro

  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8

)
SELECT

  v.DiaParametro,

  v.MesPagamento,

  EXTRACT(YEAR FROM v.MesPagamento)                         AS Ano,

  v.MesPagamento = h.mes_passado                            AS EhMesPassado,

  v.MesPagamento = h.mes_atual                              AS EhMesAtual,

  v.MesPagamento < h.mes_atual                              AS EhMesFechado,



  v.companyGroup,

  v.companyName,

  v.projectName,

  v.enterpriseName,

  v.subJudicie,

  v.SituacaoParcelaVisual,



  ROUND(v.Valor, 2)                                         AS Valor,

  ROUND(v.Valor_Bloko, 2)                                   AS Valor_Bloko,

  ROUND(v.Valor_Parceiro, 2)                                AS Valor_Parceiro,



  -- prontos para os cards (somar no Looker)

  ROUND(IF(v.MesPagamento = h.mes_passado, v.Valor, 0), 2)  AS Valor_MesPassado,

  ROUND(IF(v.MesPagamento = h.mes_atual,   v.Valor, 0), 2)  AS Valor_MesAtual,

  ROUND(IF(v.SituacaoParcelaVisual = 'Adimplente',   v.Valor, 0), 2) AS Valor_Adimplente,

  ROUND(IF(v.SituacaoParcelaVisual = 'Atrasado',     v.Valor, 0), 2) AS Valor_Atrasado,

  ROUND(IF(v.SituacaoParcelaVisual = 'Inadimplente', v.Valor, 0), 2) AS Valor_Inadimplente,



  IFNULL(c.Contratos, 0)                                    AS Contratos



FROM valores v

CROSS JOIN hoje h

LEFT JOIN contratos c

  ON  c.DiaParametro          = v.DiaParametro

  AND c.MesPagamento          = v.MesPagamento

  AND c.companyGroup          = v.companyGroup

  AND c.SituacaoParcelaVisual = v.SituacaoParcelaVisual

  AND IFNULL(c.companyName, '') = IFNULL(v.companyName, '')

  AND IFNULL(c.projectName, '') = IFNULL(v.projectName, '')

  AND IFNULL(c.enterpriseName, '') = IFNULL(v.enterpriseName, '')

  AND IFNULL(c.subJudicie, '') = IFNULL(v.subJudicie, '');
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA com o medidor atual (carteira inteira, dia 31, mai/2025 ate

-- o ultimo mes fechado). Tem que bater com recebiveis_cards_situacao_v1:

--   minimo 3.589.005 | media 4.900.667 | maximo 6.254.878 | mes passado

-- Para "ate o dia X", troque o 31 abaixo por X.

-- ####################################################################

-- WITH mes AS (

--   SELECT MesPagamento, SUM(Valor) AS total, SUM(Valor_MesPassado) AS mes_passado

--   FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_mensal_filtravel`

--   WHERE DiaParametro = 31

--     AND EhMesFechado

--     AND MesPagamento >= DATE '2025-05-01'

--   GROUP BY 1

-- )

-- SELECT

--   ROUND(MIN(total))       AS minimo,

--   ROUND(AVG(total))       AS media,

--   ROUND(MAX(total))       AS maximo,

--   ROUND(SUM(mes_passado)) AS recebiveis_mes_passado,

--   COUNT(*)                AS meses

-- FROM mes;