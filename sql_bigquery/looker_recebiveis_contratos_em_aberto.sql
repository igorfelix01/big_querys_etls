-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_CONTRATOS_EM_ABERTO

--

-- Visual do BI: "Contratos em Aberto"

--   Eixo X  : Calendario (mes de vencimento; no A Receber paymentDate = dueDate)

--   Coluna  : # Contratos Permanecem em Aberto  = [ContratosAR]

--   Linha 1 : % Contratos Permanecem em Aberto  = [%ContratosEmAbertoCX]

--   Linha 2 : % Contratos Nao Pagos no Mes Venc = [%ContratosEmAbertoCP]

--

-- DAX -> REGRA (por mes de vencimento)

--   ContratosAR               = DISTINCTCOUNT(ChaveGeral), OrigemBase = 'A Receber'

--   TotalContratosCompetencia = DISTINCTCOUNT(ChaveGeral), todas as origens,

--                               SituacaoParcela fora de Quitacao / Venda a vista / Ato

--   ContratosPagosDepoisCP    = DISTINCTCOUNT(ChaveGeral), parcela do mes com

--                               SituacaoParcela Atrasado/Inadimplente e

--                               paymentDate >= ultimo dia do mes de vencimento

--                               (somado ao ContratosAR sem tirar repetidos, igual DAX)

--   %CX = ContratosAR / TotalContratosCompetencia

--   %CP = (ContratosAR + ContratosPagosDepoisCP) / TotalContratosCompetencia

--

-- Contagens distintas: cada contrato pertence a 1 empresa, entao as colunas

-- podem ser somadas entre empresas no Looker (nao somar entre meses).

-- Os % devem ser campos calculados no Looker: SUM(...)/SUM(...).

--

-- JA FILTRADO: CT, sem Bloko, sem 'Sem grupo' (conferido com o BI:

--   jun/26 1825 | 26,8% | 48,5%).

-- SEM limite de periodo: coluna Mes.

-- Depende de: looker_studio.recebiveis_situacao_parcela

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_contratos_em_aberto`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_contratos_em_aberto`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY companyGroup

AS



WITH



sd AS (

  SELECT

    DATE_TRUNC(dueDate, MONTH) AS Mes,

    ChaveGeral,

    OrigemBase,

    SituacaoParcela,

    paymentDate,

    dueDate,

    companyGroup,

    companyName,

    subJudicie,

    anoPeriodoVenda

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

  WHERE documentIdentificationId = 'CT'

    AND companyGroup IS NOT NULL

    AND companyGroup NOT IN ('Bloko Capital', 'Sem grupo')

    AND dueDate IS NOT NULL

    AND ChaveGeral IS NOT NULL

),



-- 1 linha por Mes x contrato com as marcacoes

contrato_mes AS (

  SELECT

    Mes,

    ChaveGeral,

    ANY_VALUE(companyGroup)    AS companyGroup,

    ANY_VALUE(companyName)     AS companyName,

    ANY_VALUE(subJudicie)      AS subJudicie,

    ANY_VALUE(anoPeriodoVenda) AS anoPeriodoVenda,



    LOGICAL_OR(OrigemBase = 'A Receber') AS tem_ar,



    LOGICAL_OR(IFNULL(SituacaoParcela, '') NOT IN ('Quitação', 'Venda à vista', 'Ato'))

      AS entra_competencia,



    -- DAX ContratosPagosDepoisCP: paymentDate >= ultimo dia do mes de

    -- vencimento e SituacaoParcela Atrasado ou Inadimplente

    LOGICAL_OR(SituacaoParcela IN ('Atrasado', 'Inadimplente')

               AND paymentDate >= LAST_DAY(dueDate))

      AS pago_depois

  FROM sd

  GROUP BY Mes, ChaveGeral

)



SELECT

  Mes,

  companyGroup,

  companyName,

  subJudicie,

  anoPeriodoVenda,

  COUNTIF(tem_ar)                          AS ContratosAR,

  COUNTIF(entra_competencia)               AS TotalContratosCompetencia,

  COUNTIF(pago_depois)                     AS ContratosPagosDepoisCP

FROM contrato_mes

GROUP BY 1, 2, 3, 4, 5;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO

-- BI: mai/25 917 | 13,3% | 35,5%     ago/25 980 | 14,2% | 36,9%

--     dez/25 1136 | 16,5% | 37,2%    jun/26 1827 | 26,8% | 48,5%

-- ####################################################################



-- SELECT

--   Mes,

--   filtro,

--   SUM(ContratosAR) AS contratos_ar,

--   ROUND(100 * SAFE_DIVIDE(SUM(ContratosAR), SUM(TotalContratosCompetencia)), 1) AS pct_cx,

--   ROUND(100 * SAFE_DIVIDE(SUM(ContratosAR) + SUM(ContratosPagosDepoisCP),

--                           SUM(TotalContratosCompetencia)), 1)                     AS pct_cp

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_contratos_em_aberto`

-- CROSS JOIN UNNEST(['com Sem grupo', 'sem Sem grupo']) AS filtro

-- WHERE Mes IN ('2025-05-01', '2025-08-01', '2025-12-01', '2026-06-01')

--   AND (filtro = 'com Sem grupo' OR companyGroup <> 'Sem grupo')

-- GROUP BY Mes, filtro

-- ORDER BY Mes, filtro;