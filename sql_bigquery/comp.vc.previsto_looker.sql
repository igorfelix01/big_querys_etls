-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_COMPETENCIA_PREVISTO_RECEBIDO_MENSAL

--

-- Visual do BI: "Competencia vs. Previsto vs. Recebido (R$)"

-- Filtros da pagina no BI: documentIdentificationId = CT,

--   companyGroup <> Bloko Capital, Conta = (Em branco) ou Efeito Caixa

-- Filtro do visual: Conta = Efeito Caixa

--

-- MEDIDAS (DAX) -> COLUNAS

--

-- [VisaoRecebiveis] = SUM(ValorBruto|ValorBloko|ValorParceiro)

--                     com SaldoDevedor[Conta] = "Efeito Caixa"

--

-- [Recebido] = SUM(SaldoDevedor[ValorBruto]) no contexto do visual

--   -> Conta = Efeito Caixa, mes do paymentDate (Calendario)

--

-- [ValorCompetenciaTotal] (ALLEXCEPT tira o filtro de Conta)

--   = [VisaoRecebiveis] com dueDate no periodo      (recebidas Efeito Caixa)

--   + SUM(originalAmount) do 'A Receber' com dueDate no periodo

--

-- [ValorPrevisto] = [ValorPrevistoAR]

--                 + [Media3MensalAtrasado]

--                 + [Media3MensalInadimplente]

--                 + [Media3MensalAntecipado]

--                 + [VisaoRecebiveis] com SituacaoParcela = "Adimplente"

--                   (mes do paymentDate)

--

--   [ValorPrevistoAR] = SUM(db_a_receber[ValorBruto]) com

--                       SituacaoContrato = "Adimplente", mes do dueDate

--   [Media3Mensal*]   = SUM(ValorBruto) com paymentDate nos 3 ultimos

--                       meses fechados e SituacaoParcela = X, / 3

--                       (NAO depende do periodo selecionado)

--

-- GRAO: Mes x documentIdentificationId x subJudicie x anoPeriodoVenda x

--       operationTypeId x companyGroup x companyId x companyName

--   (colunas mantidas nos ALLEXCEPT, para os filtros do painel valerem)

--

-- ATENCAO:

--   - As medias de 3 meses se repetem em todos os meses. Com UM mes

--     selecionado o Previsto fica igual ao BI; com varios meses o Looker

--     soma a media uma vez por mes (no BI entra uma vez so).

--   - ValorPrevistoAR e medias usam sempre ValorBruto (igual DAX); so a

--     parcela Adimplente muda com a visao Bloko/Parceiro.

--   - Linhas do A Receber (db_a_receber) nao tem anoPeriodoVenda nem

--     operationTypeId (ficam NULL), igual ao BI, onde esses filtros nao

--     atingem a db_a_receber.

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_mensal`;-- [otimizacao] CTE 'sd' usada 5x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE sd AS
  SELECT

    OrigemBase,

    Conta,

    SituacaoParcela,

    paymentDate,

    dueDate,

    originalAmount,

    ValorBruto,

    ValorBloko,

    ValorParceiro,

    documentIdentificationId,

    subJudicie,

    anoPeriodoVenda,

    operationTypeId,

    companyGroup,

    companyId,

    companyName

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`;

-- [otimizacao] CTE 'base_mensal' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base_mensal AS
WITH
nome_companhias AS (

  SELECT

    companyId,

    companyGroup

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  QUALIFY ROW_NUMBER() OVER (PARTITION BY companyId ORDER BY companyId) = 1

),

situacao_contrato AS (

  SELECT

    ChaveGeral,

    SituacaoContrato

  FROM `dadosfinanceiro-501613.analytics.fato_a_receber_totalizador`

  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral ORDER BY ChaveGeral) = 1

),

p_competencia_recebido AS (

  SELECT

    DATE_TRUNC(dueDate, MONTH) AS Mes,

    documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

    companyGroup, companyId, companyName,



    ValorBruto    AS CompetenciaRecebido_Bruto,

    ValorBloko    AS CompetenciaRecebido_Bloko,

    ValorParceiro AS CompetenciaRecebido_Parceiro,

    0 AS CompetenciaEmAberto,

    0 AS Recebido_Bruto, 0 AS Recebido_Bloko, 0 AS Recebido_Parceiro,

    0 AS Adimplente_Bruto, 0 AS Adimplente_Bloko, 0 AS Adimplente_Parceiro,

    0 AS PrevistoAR

  FROM sd

  WHERE Conta = 'Efeito Caixa'

    AND dueDate IS NOT NULL

),

p_competencia_aberto AS (

  SELECT

    DATE_TRUNC(dueDate, MONTH) AS Mes,

    documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

    companyGroup, companyId, companyName,



    0, 0, 0,

    originalAmount,

    0, 0, 0,

    0, 0, 0,

    0

  FROM sd

  WHERE OrigemBase = 'A Receber'

    AND dueDate IS NOT NULL

),

p_recebido AS (

  SELECT

    DATE_TRUNC(paymentDate, MONTH) AS Mes,

    documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

    companyGroup, companyId, companyName,



    0, 0, 0,

    0,

    ValorBruto, ValorBloko, ValorParceiro,

    0, 0, 0,

    0

  FROM sd

  WHERE Conta = 'Efeito Caixa'

    AND paymentDate IS NOT NULL

),

p_adimplente AS (

  SELECT

    DATE_TRUNC(paymentDate, MONTH) AS Mes,

    documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

    companyGroup, companyId, companyName,



    0, 0, 0,

    0,

    0, 0, 0,

    ValorBruto, ValorBloko, ValorParceiro,

    0

  FROM sd

  WHERE Conta = 'Efeito Caixa'

    AND SituacaoParcela = 'Adimplente'

    AND paymentDate IS NOT NULL

),

p_previsto_ar AS (

  SELECT

    DATE_TRUNC(ar.dueDate, MONTH) AS Mes,

    CAST(ar.documentIdentificationId AS STRING) AS documentIdentificationId,

    CAST(ar.subJudicie AS STRING)               AS subJudicie,

    CAST(NULL AS STRING)                        AS anoPeriodoVenda,

    CAST(NULL AS INT64)                         AS operationTypeId,

    IFNULL(nc.companyGroup, 'Sem grupo')        AS companyGroup,

    ar.companyId,

    CAST(ar.companyName AS STRING)              AS companyName,



    0, 0, 0,

    0,

    0, 0, 0,

    0, 0, 0,

    ar.ValorBruto

  FROM `dadosfinanceiro-501613.analytics.fato_areceber` ar

  LEFT JOIN situacao_contrato sc ON sc.ChaveGeral = ar.ChaveGeral

  LEFT JOIN nome_companhias  nc ON nc.companyId  = ar.companyId

  WHERE sc.SituacaoContrato = 'Adimplente'

    AND ar.dueDate IS NOT NULL

),

base AS (

  SELECT * FROM p_competencia_recebido

  UNION ALL SELECT * FROM p_competencia_aberto

  UNION ALL SELECT * FROM p_recebido

  UNION ALL SELECT * FROM p_adimplente

  UNION ALL SELECT * FROM p_previsto_ar

)
SELECT * FROM (


  SELECT

    Mes,

    documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

    companyGroup, companyId, companyName,



    SUM(CompetenciaRecebido_Bruto)    AS CompetenciaRecebido_Bruto,

    SUM(CompetenciaRecebido_Bloko)    AS CompetenciaRecebido_Bloko,

    SUM(CompetenciaRecebido_Parceiro) AS CompetenciaRecebido_Parceiro,

    SUM(CompetenciaEmAberto)          AS CompetenciaEmAberto,

    SUM(Recebido_Bruto)               AS Recebido_Bruto,

    SUM(Recebido_Bloko)               AS Recebido_Bloko,

    SUM(Recebido_Parceiro)            AS Recebido_Parceiro,

    SUM(Adimplente_Bruto)             AS Adimplente_Bruto,

    SUM(Adimplente_Bloko)             AS Adimplente_Bloko,

    SUM(Adimplente_Parceiro)          AS Adimplente_Parceiro,

    SUM(PrevistoAR)                   AS PrevistoAR

  FROM base

  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8


);

-- [otimizacao] CTE 'medias' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE medias AS
WITH
periodo AS (

  SELECT

    -- EOMONTH(TODAY(), -4) < paymentDate <= EOMONTH(TODAY(), -1)

    DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 3 MONTH) AS media_inicio,

    DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 1 DAY)   AS media_fim

)
SELECT * FROM (


  SELECT

    documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

    companyGroup, companyId, companyName,



    SUM(IF(SituacaoParcela = 'Atrasado',     ValorBruto, 0)) / 3 AS Media3MensalAtrasado,

    SUM(IF(SituacaoParcela = 'Inadimplente', ValorBruto, 0)) / 3 AS Media3MensalInadimplente,

    SUM(IF(SituacaoParcela = 'Antecipado',   ValorBruto, 0)) / 3 AS Media3MensalAntecipado

  FROM sd

  CROSS JOIN periodo p

  WHERE Conta = 'Efeito Caixa'

    AND paymentDate >  DATE_SUB(p.media_inicio, INTERVAL 1 DAY)

    AND paymentDate <= p.media_fim

  GROUP BY 1, 2, 3, 4, 5, 6, 7


);







CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_mensal`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  documentIdentificationId,

  companyGroup,

  subJudicie



AS
WITH
meses AS (

  SELECT DISTINCT Mes FROM base_mensal WHERE Mes IS NOT NULL

),

grade AS (

  SELECT

    m.Mes,

    k.documentIdentificationId, k.subJudicie, k.anoPeriodoVenda, k.operationTypeId,

    k.companyGroup, k.companyId, k.companyName

  FROM meses m

  CROSS JOIN (

    SELECT documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

           companyGroup, companyId, companyName

    FROM base_mensal

    UNION DISTINCT

    SELECT documentIdentificationId, subJudicie, anoPeriodoVenda, operationTypeId,

           companyGroup, companyId, companyName

    FROM medias

  ) k

)
SELECT

  g.Mes,

  g.documentIdentificationId,

  g.subJudicie,

  g.anoPeriodoVenda,

  g.operationTypeId,

  g.companyGroup,

  g.companyId,

  g.companyName,



  -- Recebido

  ROUND(IFNULL(b.Recebido_Bruto, 0), 2)    AS Recebido_Bruto,

  ROUND(IFNULL(b.Recebido_Bloko, 0), 2)    AS Recebido_Bloko,

  ROUND(IFNULL(b.Recebido_Parceiro, 0), 2) AS Recebido_Parceiro,



  -- Competencia

  ROUND(IFNULL(b.CompetenciaRecebido_Bruto, 0)    + IFNULL(b.CompetenciaEmAberto, 0), 2) AS ValorCompetencia_Bruto,

  ROUND(IFNULL(b.CompetenciaRecebido_Bloko, 0)    + IFNULL(b.CompetenciaEmAberto, 0), 2) AS ValorCompetencia_Bloko,

  ROUND(IFNULL(b.CompetenciaRecebido_Parceiro, 0) + IFNULL(b.CompetenciaEmAberto, 0), 2) AS ValorCompetencia_Parceiro,



  -- Previsto

  ROUND(

    IFNULL(b.PrevistoAR, 0)

    + IFNULL(md.Media3MensalAtrasado, 0)

    + IFNULL(md.Media3MensalInadimplente, 0)

    + IFNULL(md.Media3MensalAntecipado, 0)

    + IFNULL(b.Adimplente_Bruto, 0), 2)    AS ValorPrevisto_Bruto,

  ROUND(

    IFNULL(b.PrevistoAR, 0)

    + IFNULL(md.Media3MensalAtrasado, 0)

    + IFNULL(md.Media3MensalInadimplente, 0)

    + IFNULL(md.Media3MensalAntecipado, 0)

    + IFNULL(b.Adimplente_Bloko, 0), 2)    AS ValorPrevisto_Bloko,

  ROUND(

    IFNULL(b.PrevistoAR, 0)

    + IFNULL(md.Media3MensalAtrasado, 0)

    + IFNULL(md.Media3MensalInadimplente, 0)

    + IFNULL(md.Media3MensalAntecipado, 0)

    + IFNULL(b.Adimplente_Parceiro, 0), 2) AS ValorPrevisto_Parceiro,



  -- componentes (conferencia)

  ROUND(IFNULL(b.CompetenciaRecebido_Bruto, 0), 2)  AS CompetenciaRecebido_Bruto,

  ROUND(IFNULL(b.CompetenciaEmAberto, 0), 2)        AS CompetenciaEmAberto,

  ROUND(IFNULL(b.PrevistoAR, 0), 2)                 AS ValorPrevistoAR,

  ROUND(IFNULL(b.Adimplente_Bruto, 0), 2)           AS PrevistoAdimplente_Bruto,

  ROUND(IFNULL(md.Media3MensalAtrasado, 0), 2)      AS Media3MensalAtrasado,

  ROUND(IFNULL(md.Media3MensalInadimplente, 0), 2)  AS Media3MensalInadimplente,

  ROUND(IFNULL(md.Media3MensalAntecipado, 0), 2)    AS Media3MensalAntecipado



FROM grade g



LEFT JOIN base_mensal b

  ON  b.Mes = g.Mes

  AND b.documentIdentificationId IS NOT DISTINCT FROM g.documentIdentificationId

  AND b.subJudicie               IS NOT DISTINCT FROM g.subJudicie

  AND b.anoPeriodoVenda          IS NOT DISTINCT FROM g.anoPeriodoVenda

  AND b.operationTypeId          IS NOT DISTINCT FROM g.operationTypeId

  AND b.companyGroup             IS NOT DISTINCT FROM g.companyGroup

  AND b.companyId                IS NOT DISTINCT FROM g.companyId

  AND b.companyName              IS NOT DISTINCT FROM g.companyName



LEFT JOIN medias md

  ON  md.documentIdentificationId IS NOT DISTINCT FROM g.documentIdentificationId

  AND md.subJudicie               IS NOT DISTINCT FROM g.subJudicie

  AND md.anoPeriodoVenda          IS NOT DISTINCT FROM g.anoPeriodoVenda

  AND md.operationTypeId          IS NOT DISTINCT FROM g.operationTypeId

  AND md.companyGroup             IS NOT DISTINCT FROM g.companyGroup

  AND md.companyId                IS NOT DISTINCT FROM g.companyId

  AND md.companyName              IS NOT DISTINCT FROM g.companyName



-- descarta linhas totalmente zeradas

WHERE COALESCE(b.Recebido_Bruto, 0) <> 0

   OR COALESCE(b.CompetenciaRecebido_Bruto, 0) <> 0

   OR COALESCE(b.CompetenciaEmAberto, 0) <> 0

   OR COALESCE(b.Adimplente_Bruto, 0) <> 0

   OR COALESCE(b.PrevistoAR, 0) <> 0

   OR COALESCE(md.Media3MensalAtrasado, 0) <> 0

   OR COALESCE(md.Media3MensalInadimplente, 0) <> 0

   OR COALESCE(md.Media3MensalAntecipado, 0) <> 0;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO - agosto/2026, filtros do BI (CT, sem Bloko Capital)

-- Esperado (BI): Competencia 6.878.632 | Previsto 4.791.927 |

--                Recebido 5.148.311

-- ####################################################################



-- SELECT

--   Mes,

--   ROUND(SUM(ValorCompetencia_Bruto), 2)     AS competencia,

--   ROUND(SUM(ValorPrevisto_Bruto), 2)        AS previsto,

--   ROUND(SUM(Recebido_Bruto), 2)             AS recebido,



--   ROUND(SUM(CompetenciaRecebido_Bruto), 2)  AS comp_recebido,

--   ROUND(SUM(CompetenciaEmAberto), 2)        AS comp_em_aberto,

--   ROUND(SUM(ValorPrevistoAR), 2)            AS prev_ar,

--   ROUND(SUM(PrevistoAdimplente_Bruto), 2)   AS prev_adimplente,

--   ROUND(SUM(Media3MensalAtrasado), 2)       AS media_atrasado,

--   ROUND(SUM(Media3MensalInadimplente), 2)   AS media_inadimplente,

--   ROUND(SUM(Media3MensalAntecipado), 2)     AS media_antecipado

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_mensal`

-- WHERE Mes = '2026-08-01'

--   AND documentIdentificationId = 'CT'

--   AND companyGroup <> 'Bloko Capital'

-- GROUP BY Mes;