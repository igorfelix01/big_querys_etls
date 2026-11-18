-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_TABELA_CONTRATOS

--

-- Visual do BI (tabela):

--   ID               = SaldoDevedor[ChaveGeral]

--   Nome             = SaldoDevedor[clientName]

--   Status           = SaldoDevedor[OrigemBase]  ('A Receber' ou vazio = recebida)

--   Valor            = SUM(SaldoDevedor[ValorBruto])

--   Situacao Contrato= db_titulos_totalizador[SituacaoContrato]

--   Valor Recebido   = [ValorRecebido (Dinamico)]  -> SUM(Valor*) das recebidas

--   Valor Em Aberto  = db_titulos_totalizador[SaldoDevedorComJuros]

--

-- FILTROS DE PAGINA DO BI (aplicados aqui, mesma pagina da matriz):

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital'

--   Conta = (Em branco) ou 'Efeito Caixa'

--   SEM limite de periodo: coluna Mes (mes do paymentDate; no A Receber

--   e o vencimento) para o filtro do Looker

--

-- DIFERENCA CONHECIDA:

--   No BI, a medida [ValorRecebido] troca o filtro de Status, entao na

--   linha 'A Receber' ela repete o recebido do mesmo contrato. O Looker

--   nao faz esse calculo entre linhas: aqui o Valor Recebido aparece na

--   linha da recebida (Status vazio) e fica vazio na linha 'A Receber'.

--   Os totais do Valor Recebido nao mudam.

--

-- Valor Em Aberto e Situacao Contrato sao do contrato (totalizador) e se

-- repetem em cada linha -> no Looker usar agregacao MAX, nao SUM.

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_tabela_contratos`;-- [otimizacao] CTE 'sd' usada 25x: calculada 1 vez como tabela temporaria
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

    AND (s.Conta IS NULL OR s.Conta = 'Efeito Caixa')

    AND s.paymentDate IS NOT NULL


);







CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_tabela_contratos`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  ChaveGeral,

  companyGroup



AS
WITH
totalizador AS (

  SELECT

    ChaveGeral,

    SituacaoContrato,

    SaldoDevedorComJuros

  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral ORDER BY ChaveGeral) = 1

)
SELECT

  DATE_TRUNC(sd.paymentDate, MONTH) AS Mes,



  sd.ChaveGeral                                    AS ID,

  sd.clientName                                    AS Nome,

  IF(sd.OrigemBase = 'A Receber', 'A Receber', '') AS Status,

  t.SituacaoContrato                               AS SituacaoContrato,



  sd.companyGroup,

  sd.companyName,

  sd.Projeto,

  sd.subJudicie,

  sd.ChaveGeral,



  -- Valor = SUM(ValorBruto) da linha (recebida ou A Receber)

  ROUND(SUM(sd.ValorBruto), 2)    AS Valor_Bruto,

  ROUND(SUM(sd.ValorBloko), 2)    AS Valor_Bloko,

  ROUND(SUM(sd.ValorParceiro), 2) AS Valor_Parceiro,



  -- Valor Recebido = so recebidas

  ROUND(SUM(IF(sd.OrigemBase = 'Recebidas', sd.ValorBruto,    NULL)), 2) AS ValorRecebido_Bruto,

  ROUND(SUM(IF(sd.OrigemBase = 'Recebidas', sd.ValorBloko,    NULL)), 2) AS ValorRecebido_Bloko,

  ROUND(SUM(IF(sd.OrigemBase = 'Recebidas', sd.ValorParceiro, NULL)), 2) AS ValorRecebido_Parceiro,



  -- Valor Em Aberto do contrato (usar MAX no Looker)

  ROUND(MAX(t.SaldoDevedorComJuros), 2) AS ValorEmAberto



FROM sd

LEFT JOIN totalizador t

  ON t.ChaveGeral = sd.ChaveGeral



GROUP BY

  Mes, ID, Nome, Status, SituacaoContrato,

  sd.companyGroup, sd.companyName, sd.Projeto, sd.subJudicie, sd.ChaveGeral;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO: contratos do print do BI (periodo mai/25 a dez/26)

-- ex.: 606-61464 -> recebida 77,49 | A Receber 587,12 | aberto 733,90

--      606-61248 -> recebida 8.833,30 | A Receber 2.192,80 | aberto 9.565,83

-- ####################################################################



-- SELECT

--   ID,

--   Nome,

--   Status,

--   SituacaoContrato,

--   ROUND(SUM(Valor_Bruto), 2)         AS valor,

--   ROUND(SUM(ValorRecebido_Bruto), 2) AS valor_recebido,

--   MAX(ValorEmAberto)                 AS valor_em_aberto

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_tabela_contratos`

-- WHERE ID IN ('606-62260', '606-61683', '606-61464', '606-61434',

--              '606-61357', '606-61248', '606-61200')

--   AND Mes BETWEEN '2025-05-01' AND '2026-12-01'

-- GROUP BY 1, 2, 3, 4

-- ORDER BY ID DESC, Status;