DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_barras`;



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_barras`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY Serie, companyGroup

AS

WITH

filtrado AS (

  SELECT m.*

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_mensal` m

  WHERE m.documentIdentificationId = 'CT'

    AND IFNULL(m.companyGroup, '') <> 'Bloko Capital'

)

SELECT

  f.Mes,

  f.companyGroup,

  f.companyName,

  f.subJudicie,

  f.anoPeriodoVenda,

  s.Serie,

  s.OrdemSerie,



  ROUND(SUM(CASE s.Serie

    WHEN 'Valor Competência' THEN f.ValorCompetencia_Bruto

    WHEN 'ValorPrevisto'     THEN f.ValorPrevisto_Bruto

    WHEN 'Recebido'          THEN f.Recebido_Bruto

  END), 2) AS Valor_Bruto,



  ROUND(SUM(CASE s.Serie

    WHEN 'Valor Competência' THEN f.ValorCompetencia_Bloko

    WHEN 'ValorPrevisto'     THEN f.ValorPrevisto_Bloko

    WHEN 'Recebido'          THEN f.Recebido_Bloko

  END), 2) AS Valor_Bloko,



  ROUND(SUM(CASE s.Serie

    WHEN 'Valor Competência' THEN f.ValorCompetencia_Parceiro

    WHEN 'ValorPrevisto'     THEN f.ValorPrevisto_Parceiro

    WHEN 'Recebido'          THEN f.Recebido_Parceiro

  END), 2) AS Valor_Parceiro



FROM filtrado f

CROSS JOIN UNNEST([

  STRUCT('Valor Competência' AS Serie, 1 AS OrdemSerie),

  STRUCT('ValorPrevisto'     AS Serie, 2 AS OrdemSerie),

  STRUCT('Recebido'          AS Serie, 3 AS OrdemSerie)

]) AS s

GROUP BY

  f.Mes, f.companyGroup, f.companyName, f.subJudicie,

  f.anoPeriodoVenda, s.Serie, s.OrdemSerie;