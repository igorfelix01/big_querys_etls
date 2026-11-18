-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_COMPOSICAO_COMPETENCIA

--

-- Visual do BI: "Composicao Competencia (R$)"

--   Nao Recebido = [ValorCompetenciaSPASemUso]

--   Adimplente   = Soma de SaldoDevedor[ValorBruto] (Adimplente)

--

-- DAX [ValorCompetenciaSPASemUso]:

--   PARTE 1 (VisaoRecebiveis Atrasado + Inadimplente) SEMPRE da ZERO no BI:

--     - dueDate < dataComeco && dueDate > dataFim  -> impossivel

--     - SituacaoParcela = "Atrasado" E = "Inadimplente" ao mesmo tempo

--   Por fidelidade ao BI, essa parte nao entra (resultado = 0).

--   PARTE 2 = SUM(originalAmount) com SituacaoParcela = "A Receber"

--             e dueDate no periodo (ALLEXCEPT sem ContasBancarias:

--             nao tem filtro de Conta)

--

-- Adimplente = SUM(ValorBruto) com SituacaoParcela = 'Adimplente',

--              Conta = 'Efeito Caixa', paymentDate no periodo

--

-- JA FILTRADO NO SQL (igual BI):

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital'

--   SEM limite de periodo: coluna Mes para o filtro do Looker

--     (Nao Recebido -> mes do dueDate ; Adimplente -> mes do paymentDate)

--

-- Uma linha por serie. companyGroup / companyName / subJudicie /

-- anoPeriodoVenda ficam como colunas para os filtros do painel.

-- Percentual: calcular no Looker (percentual do total), para continuar

-- certo quando o painel filtrar empresa.

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_composicao_competencia`;-- [otimizacao] CTE 'sd' usada 23x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE sd AS
  SELECT *

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

  WHERE documentIdentificationId = 'CT'

    AND IFNULL(companyGroup, '') <> 'Bloko Capital';







CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_composicao_competencia`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  Serie,

  companyGroup



AS
WITH
nao_recebido AS (

  SELECT

    DATE_TRUNC(sd.dueDate, MONTH) AS Mes,

    'Não Recebido' AS Serie,

    1              AS OrdemSerie,

    sd.companyGroup, sd.companyName, sd.subJudicie, sd.anoPeriodoVenda,

    sd.originalAmount AS Valor_Bruto,

    sd.originalAmount AS Valor_Bloko,      -- DAX usa originalAmount em qualquer visao

    sd.originalAmount AS Valor_Parceiro

  FROM sd

  WHERE sd.SituacaoParcela = 'A Receber'

    AND sd.dueDate IS NOT NULL

),

adimplente AS (

  SELECT

    DATE_TRUNC(sd.paymentDate, MONTH) AS Mes,

    'Adimplente' AS Serie,

    2            AS OrdemSerie,

    sd.companyGroup, sd.companyName, sd.subJudicie, sd.anoPeriodoVenda,

    sd.ValorBruto    AS Valor_Bruto,

    sd.ValorBloko    AS Valor_Bloko,

    sd.ValorParceiro AS Valor_Parceiro

  FROM sd

  WHERE sd.SituacaoParcela = 'Adimplente'

    AND sd.Conta = 'Efeito Caixa'

    AND sd.paymentDate IS NOT NULL

)
SELECT

  Mes,

  Serie,

  OrdemSerie,

  companyGroup,

  companyName,

  subJudicie,

  anoPeriodoVenda,

  ROUND(SUM(Valor_Bruto), 2)    AS Valor_Bruto,

  ROUND(SUM(Valor_Bloko), 2)    AS Valor_Bloko,

  ROUND(SUM(Valor_Parceiro), 2) AS Valor_Parceiro

FROM (

  SELECT * FROM nao_recebido

  UNION ALL

  SELECT * FROM adimplente

)

GROUP BY 1, 2, 3, 4, 5, 6, 7;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO (CT e sem Bloko ja filtrados; escolher o mes)

-- Esperado ago/2026: Nao Recebido 2.331.063 (45,59%) |

--                    Adimplente   2.782.196 (54,41%)

-- ####################################################################



-- SELECT

--   Mes,

--   Serie,

--   ROUND(SUM(Valor_Bruto), 2) AS valor,

--   ROUND(100 * SUM(Valor_Bruto) / SUM(SUM(Valor_Bruto)) OVER (), 2) AS percentual

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_composicao_competencia`

-- WHERE Mes = '2026-08-01'

-- GROUP BY Mes, Serie, OrdemSerie

-- ORDER BY OrdemSerie;