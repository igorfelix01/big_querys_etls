-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_DETALHE_ATRASADOS

--

-- Visual do BI: tabela "Detalhamento atrasados e inadimplentes"

--   ID                  = SaldoDevedor[ChaveGeral]

--   Cliente             = nome do cliente

--   Atraso              = db_titulos_totalizador[MaxAtrasoDias]

--   Vencimento          = db_titulos_totalizador[PrimeiraDataVencimento]

--   Saldo c/ juros      = db_titulos_totalizador[SaldoDevedorComJuros]

--   Valor liquido       = db_titulos_totalizador[ValorLiquidoAgregado]

--   subJudicie          = db_titulos_totalizador[subJudicie]

--   Email / Telefone / CNPJ / CPF = clientes

--

-- MESMOS FILTROS DO GRAFICO "Contratos nao Pagos" (ja no SQL):

--   OrigemBase = 'A Receber'

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital' e sem 'Sem grupo'

--   SituacaoContrato IN ('Atrasado', 'Inadimplente')

--   SEM limite de periodo: coluna Mes (vencimento da parcela A Receber)

--     -> o filtro de periodo do Looker mostra os contratos com parcela

--        vencida no periodo, como o grafico ao lado.

--

-- Uma linha por Mes x contrato. Os valores sao do contrato e se repetem

-- em cada mes -> no Looker usar agregacao MAX (nao SUM).

--

-- Depende de: looker_studio.recebiveis_situacao_parcela,

--             analytics.fato_titulos_totalizador (etapa 2.3)

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_detalhe_atrasados`;-- [otimizacao] CTE 'ar' usada 6x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE ar AS
  SELECT

    DATE_TRUNC(s.paymentDate, MONTH) AS Mes,

    s.ChaveGeral,

    s.companyGroup,

    s.companyName

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela` s

  WHERE s.OrigemBase = 'A Receber'

    AND s.paymentDate IS NOT NULL

    AND s.ChaveGeral IS NOT NULL

    AND s.documentIdentificationId = 'CT'

    AND s.companyGroup IS NOT NULL

    AND s.companyGroup NOT IN ('Bloko Capital', 'Sem grupo')

  GROUP BY 1, 2, 3, 4;







CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_detalhe_atrasados`



-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY

  SituacaoContrato,

  companyGroup,

  ID



AS
WITH
totalizador AS (

  SELECT

    ChaveGeral,

    clientName,

    SituacaoContrato,

    MaxAtrasoDias,

    PrimeiraDataVencimento,

    SaldoDevedorComJuros,

    ValorLiquidoAgregado,

    subJudicie,

    Email,

    Telefone,

    CNPJ,

    CPF

  FROM `dadosfinanceiro-501613.analytics.fato_titulos_totalizador`

  QUALIFY ROW_NUMBER() OVER (PARTITION BY ChaveGeral ORDER BY ChaveGeral) = 1

)
SELECT

  ar.Mes,



  ar.ChaveGeral                         AS ID,

  t.clientName                          AS Cliente,

  t.SituacaoContrato,



  t.MaxAtrasoDias                       AS Atraso,

  t.PrimeiraDataVencimento              AS Vencimento,

  ROUND(t.SaldoDevedorComJuros, 2)      AS SaldoDevedorComJuros,

  ROUND(t.ValorLiquidoAgregado, 2)      AS ValorLiquidoAgregado,

  t.subJudicie,



  t.Email,

  t.Telefone,

  t.CNPJ,

  t.CPF,



  ar.companyGroup,

  ar.companyName



FROM ar

JOIN totalizador t

  ON t.ChaveGeral = ar.ChaveGeral



WHERE t.SituacaoContrato IN ('Atrasado', 'Inadimplente');
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO: contratos do print do BI

-- esperado: 501-66414 OSMERIO LUIZ GUIMARAES atraso 1363

--           323-69889 MICHAEL OLIVEIRA ANDRADE atraso 0

-- ####################################################################



-- SELECT

--   ID,

--   Cliente,

--   SituacaoContrato,

--   MAX(Atraso)               AS atraso,

--   MAX(Vencimento)           AS vencimento,

--   MAX(SaldoDevedorComJuros) AS saldo_com_juros,

--   MAX(ValorLiquidoAgregado) AS valor_liquido,

--   MAX(subJudicie)           AS subjudicie,

--   COUNT(DISTINCT Mes)       AS meses_com_parcela_vencida

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_detalhe_atrasados`

-- WHERE ID IN ('323-69889', '501-66036', '501-65119', '501-66414',

--              '501-63806', '501-63807', '501-63943')

-- GROUP BY 1, 2, 3

-- ORDER BY ID;