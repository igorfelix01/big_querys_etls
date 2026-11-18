-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_COMPETENCIA_INADIMPLENCIA

--

-- Visual do BI: "Valor Competencia vs. Recebimento (R$) e Inadimplencia"

--   Eixo X  : Calendario aplicado no dueDate (mes de VENCIMENTO)

--   Colunas : Antecipado / Adimplente / Atrasado / Inadimplente / Em Aberto

--   Linha   : Inadimplencia

--

-- DAX -> REGRA (todas pelo mes do dueDate)

--   AntecipadoTotalMes   = VisaoRecebiveis, SituacaoParcela = 'Antecipado'

--   AdimplenteTotalMes   = VisaoRecebiveis, SituacaoParcela = 'Adimplente'

--   AtrasadoTotalMes     = VisaoRecebiveis, SituacaoParcela = 'Atrasado'

--   InadimplenteTotalMes = VisaoRecebiveis, SituacaoParcela = 'Inadimplente'

--     (VisaoRecebiveis = SUM(ValorBruto|Bloko|Parceiro) com Conta='Efeito Caixa')

--   EmAberto             = SUM(originalAmount), OrigemBase = 'A Receber'

--                          (sem filtro de Conta, igual a DAX)

--   ValorCompetencia     = soma das 5 colunas

--   Inadimplencia        = (Em Aberto + Atrasado + Inadimplente) / ValorCompetencia

--

-- JA FILTRADO NO SQL (mesmos filtros das outras paginas de recebiveis):

--   documentIdentificationId = 'CT'

--   companyGroup <> 'Bloko Capital'

--   companyGroup em branco ('Sem grupo') FORA (conferido: jun/26 Em Aberto

--     BI 1.848.384 = Looker 2.042.852 - Sem grupo 194.538)

--   SEM limite de periodo: coluna Mes (vencimento) para o filtro do Looker

--

-- No Looker a Inadimplencia deve ser um CAMPO CALCULADO (ver final), para

-- continuar certa quando filtrar empresa/periodo.

--

-- Depende de: looker_studio.recebiveis_situacao_parcela

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_inadimplencia`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_inadimplencia`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY companyGroup

AS



WITH



sd AS (

  SELECT *

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

  WHERE documentIdentificationId = 'CT'

    AND companyGroup IS NOT NULL

    AND companyGroup NOT IN ('Bloko Capital', 'Sem grupo')

    AND dueDate IS NOT NULL

)



SELECT

  DATE_TRUNC(dueDate, MONTH) AS Mes,

  companyGroup,

  companyName,

  subJudicie,

  anoPeriodoVenda,



  -- ---------- Bruto ----------

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Antecipado',   ValorBruto, 0)), 2) AS Antecipado_Bruto,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Adimplente',   ValorBruto, 0)), 2) AS Adimplente_Bruto,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Atrasado',     ValorBruto, 0)), 2) AS Atrasado_Bruto,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Inadimplente', ValorBruto, 0)), 2) AS Inadimplente_Bruto,



  -- ---------- Bloko ----------

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Antecipado',   ValorBloko, 0)), 2) AS Antecipado_Bloko,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Adimplente',   ValorBloko, 0)), 2) AS Adimplente_Bloko,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Atrasado',     ValorBloko, 0)), 2) AS Atrasado_Bloko,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Inadimplente', ValorBloko, 0)), 2) AS Inadimplente_Bloko,



  -- ---------- Parceiro ----------

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Antecipado',   ValorParceiro, 0)), 2) AS Antecipado_Parceiro,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Adimplente',   ValorParceiro, 0)), 2) AS Adimplente_Parceiro,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Atrasado',     ValorParceiro, 0)), 2) AS Atrasado_Parceiro,

  ROUND(SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela = 'Inadimplente', ValorParceiro, 0)), 2) AS Inadimplente_Parceiro,



  -- ---------- Em Aberto (originalAmount, igual em todas as visoes) ----------

  ROUND(SUM(IF(OrigemBase = 'A Receber', originalAmount, 0)), 2) AS EmAberto,



  -- ---------- para a linha de Inadimplencia (Looker: SUM/SUM) ----------

  -- numerador = Em Aberto + Atrasado + Inadimplente

  ROUND(SUM(IF(OrigemBase = 'A Receber', originalAmount, 0))

      + SUM(IF(Conta = 'Efeito Caixa' AND SituacaoParcela IN ('Atrasado', 'Inadimplente'), ValorBruto, 0)), 2)

    AS NaoRecebido_Bruto,

  -- denominador = Valor Competencia (soma das 5 colunas)

  ROUND(SUM(IF(OrigemBase = 'A Receber', originalAmount, 0))

      + SUM(IF(Conta = 'Efeito Caixa'

               AND SituacaoParcela IN ('Antecipado', 'Adimplente', 'Atrasado', 'Inadimplente'),

               ValorBruto, 0)), 2)

    AS ValorCompetencia_Bruto



FROM sd

GROUP BY 1, 2, 3, 4, 5;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO (visao Bruto)

-- BI: mai/25 total 5.487 mil | adimplente 2.870 mil | inadimplencia 46,8%

--     jun/25 5.392 | 2.877 | 46,6%     dez/25 5.670 | 2.988 | 46,3%

--     abr/26 5.738 | 2.019 | 62,9%     jun/26 5.482 | 2.113 | 61,5%

-- ####################################################################



-- SELECT

--   Mes,

--   ROUND(SUM(Antecipado_Bruto + Adimplente_Bruto + Atrasado_Bruto

--             + Inadimplente_Bruto + EmAberto)) AS valor_competencia,

--   ROUND(SUM(Adimplente_Bruto))                AS adimplente,

--   ROUND(SUM(Atrasado_Bruto))                  AS atrasado,

--   ROUND(SUM(Inadimplente_Bruto))              AS inadimplente,

--   ROUND(SUM(EmAberto))                        AS em_aberto,

--   ROUND(100 * SAFE_DIVIDE(

--     SUM(EmAberto + Atrasado_Bruto + Inadimplente_Bruto),

--     SUM(Antecipado_Bruto + Adimplente_Bruto + Atrasado_Bruto

--         + Inadimplente_Bruto + EmAberto)), 1) AS inadimplencia_pct

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_inadimplencia`

-- WHERE Mes BETWEEN '2025-05-01' AND '2026-06-01'

-- GROUP BY Mes

-- ORDER BY Mes;