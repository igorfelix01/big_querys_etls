-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_MATRIZ_PROJETOS

--

-- Visual do BI (matriz):

--   Linhas  : Projeto (NomeCompanhias[enterpriseName]), subJudicie

--   Colunas : Ano / Mes (Calendario)

--   Valores : # Cont. Rec. | # Cont. AR | # Cont. Comp. | Valor Recebido

--

-- DAX -> REGRA

--   [ContratosRecebidos]   DISTINCTCOUNT(ChaveGeral), OrigemBase = "" (recebidas),

--                          mes do paymentDate (Calendario mantido)

--   [ContratosAR]          DISTINCTCOUNT(ChaveGeral), OrigemBase = "A Receber",

--                          mes do paymentDate (= vencimento no A Receber).

--                          ALLEXCEPT sem ContasBancarias -> sem filtro de Conta

--   [ContratosCompetencia] DISTINCTCOUNT(ChaveGeral), dueDate no periodo,

--                          todas as origens (Calendario NAO mantido: so dueDate)

--   [ValorRecebido (Din.)] SUM(ValorBloko|ValorBruto|ValorParceiro),

--                          OrigemBase = "" (recebidas), mes do paymentDate

--

-- FILTROS DE PAGINA DO BI (aplicados aqui):

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital'

--   Conta = (Em branco) ou 'Efeito Caixa'  -> vale para Rec, Comp e Valor

--     (conferido: ago/25 Valor Recebido 5.645.189 = Efeito Caixa 5.555.451

--      + recebidas sem conta 89.739)

--   SEM limite de periodo: filtro do Looker pela coluna Mes

--

-- CONTAGEM DISTINTA: nao soma entre linhas, por isso a tabela guarda a

-- ChaveGeral. No Looker use COUNT_DISTINCT nas colunas ChaveGeral_*.

-- Uma linha por Mes x Projeto x subJudicie x ChaveGeral x tipo.

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_matriz_projetos`;-- [otimizacao] CTE 'sd' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE sd AS
WITH
projetos AS (

  SELECT

    enterpriseId,

    enterpriseName

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  WHERE enterpriseId IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (PARTITION BY enterpriseId ORDER BY enterpriseName) = 1

)
SELECT * FROM (


  SELECT

    s.*,

    IFNULL(p.enterpriseName, '(Em branco)') AS Projeto

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` s

  LEFT JOIN projetos p

    ON p.enterpriseId = s.costCenterId

  WHERE s.documentIdentificationId = 'CT'

    AND IFNULL(s.companyGroup, '') <> 'Bloko Capital'


);







CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_matriz_projetos`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  Projeto,

  subJudicie,

  companyGroup



AS
WITH
recebidas AS (

  SELECT

    DATE_TRUNC(paymentDate, MONTH) AS Mes,

    Projeto, subJudicie, companyGroup, companyName, anoPeriodoVenda,

    ChaveGeral AS ChaveGeral_Rec,

    CAST(NULL AS STRING) AS ChaveGeral_AR,

    CAST(NULL AS STRING) AS ChaveGeral_Comp,

    ValorBruto    AS ValorRecebido_Bruto,

    ValorBloko    AS ValorRecebido_Bloko,

    ValorParceiro AS ValorRecebido_Parceiro

  FROM sd

  WHERE OrigemBase = 'Recebidas'

    AND (Conta IS NULL OR Conta = 'Efeito Caixa')

    AND paymentDate IS NOT NULL

),

a_receber AS (

  SELECT

    DATE_TRUNC(paymentDate, MONTH) AS Mes,

    Projeto, subJudicie, companyGroup, companyName, anoPeriodoVenda,

    CAST(NULL AS STRING) AS ChaveGeral_Rec,

    ChaveGeral           AS ChaveGeral_AR,

    CAST(NULL AS STRING) AS ChaveGeral_Comp,

    0, 0, 0

  FROM sd

  WHERE OrigemBase = 'A Receber'

    AND paymentDate IS NOT NULL

),

competencia AS (

  SELECT

    DATE_TRUNC(dueDate, MONTH) AS Mes,

    Projeto, subJudicie, companyGroup, companyName, anoPeriodoVenda,

    CAST(NULL AS STRING) AS ChaveGeral_Rec,

    CAST(NULL AS STRING) AS ChaveGeral_AR,

    ChaveGeral           AS ChaveGeral_Comp,

    0, 0, 0

  FROM sd

  WHERE (Conta IS NULL OR Conta = 'Efeito Caixa')

    AND dueDate IS NOT NULL

)
SELECT

  Mes,

  Projeto,

  subJudicie,

  companyGroup,

  companyName,

  anoPeriodoVenda,

  ChaveGeral_Rec,

  ChaveGeral_AR,

  ChaveGeral_Comp,

  ROUND(SUM(ValorRecebido_Bruto), 2)    AS ValorRecebido_Bruto,

  ROUND(SUM(ValorRecebido_Bloko), 2)    AS ValorRecebido_Bloko,

  ROUND(SUM(ValorRecebido_Parceiro), 2) AS ValorRecebido_Parceiro

FROM (

  SELECT * FROM recebidas

  UNION ALL SELECT * FROM a_receber

  UNION ALL SELECT * FROM competencia

)

GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO - totais por mes (linha "Total" da matriz do BI)

-- BI: jul/25  Rec 4.703 | AR 946 | Comp 6.408 | Valor 5.514.748,79

--     ago/25  Rec 4.407 | AR 980 | Comp 6.385 | Valor 5.645.189,03

--     jun/25  Valor 5.185.961,47

-- ####################################################################



-- SELECT

--   Mes,

--   COUNT(DISTINCT ChaveGeral_Rec)      AS cont_rec,

--   COUNT(DISTINCT ChaveGeral_AR)       AS cont_ar,

--   COUNT(DISTINCT ChaveGeral_Comp)     AS cont_comp,

--   ROUND(SUM(ValorRecebido_Bruto), 2)  AS valor_recebido_bruto

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_matriz_projetos`

-- WHERE Mes BETWEEN '2025-06-01' AND '2025-08-01'

-- GROUP BY Mes

-- ORDER BY Mes;