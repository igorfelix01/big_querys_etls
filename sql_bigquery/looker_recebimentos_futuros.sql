-- ####################################################################
-- LOOKER_STUDIO.RECEBIMENTOS_FUTUROS
-- Curva de recebimentos futuros por MES DE VENCIMENTO:
--   ValorContratado = o que o contrato preve (parcelas em aberto no
--                     A Receber que vencem no mes)
--   ValorAjustado   = o que deve entrar, descontada a inadimplencia:
--                     ValorContratado x % que a carteira costuma receber
--                     ate 12 meses depois do vencimento
--   (acumulados: no Looker, Calculo de execucao -> Soma acumulada)
--
-- A % vem da curva de recebimento da Projecao de Caixa
-- (looker_studio.projecao_caixa_curva, TaxaAcumulada no mes 12 depois do
-- vencimento, ultimas 12 competencias, por grupo; grupo com pouca
-- amostra usa a taxa da carteira inteira - mesma regra da projecao).
-- Mesmo universo da projecao: CT, sem Bloko, empresa pelo centro de custo.
-- Meses a partir do mes atual; sem limite final (filtro no Looker).
--
-- Depende de: analytics.saldo_devedor, analytics.dim_nome_companhias,
--             looker_studio.projecao_caixa_curva
-- ####################################################################

DROP TABLE IF EXISTS `dadosfinanceiro-501613.looker_studio.recebimentos_futuros`;

CREATE OR REPLACE TABLE
  `dadosfinanceiro-501613.looker_studio.recebimentos_futuros`
CLUSTER BY companyGroup
AS
WITH
hoje AS (
  SELECT DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual
),
emp AS (
  SELECT
    SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,
    companyGroup,
    companyName
  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`
  WHERE enterpriseId IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SAFE_CAST(enterpriseId AS INT64)
    ORDER BY companyGroup, companyName) = 1
),
-- % recebida ate 12 meses depois do vencimento, por grupo
taxa_grupo AS (
  SELECT companyGroup, TaxaAcumulada AS taxa, ValorAmostra
  FROM `dadosfinanceiro-501613.looker_studio.projecao_caixa_curva`
  WHERE MesesDepoisDoVencimento = 12
),
-- reserva para grupo sem historico: media da carteira (ponderada)
taxa_geral AS (
  SELECT SAFE_DIVIDE(SUM(taxa * ValorAmostra), SUM(ValorAmostra)) AS taxa
  FROM taxa_grupo
),
aberto AS (
  SELECT
    e.companyGroup,
    e.companyName,
    s.subJudicie,
    DATE_TRUNC(s.dueDate, MONTH) AS MesVencimento,
    s.ValorBruto
  FROM `dadosfinanceiro-501613.analytics.saldo_devedor` s
  JOIN emp e
    ON e.enterpriseId = SAFE_CAST(SAFE_CAST(CAST(s.costCenterId AS STRING) AS FLOAT64) AS INT64)
  CROSS JOIN hoje h
  WHERE s.documentIdentificationId = 'CT'
    AND s.OrigemBase = 'A Receber'
    AND DATE_TRUNC(s.dueDate, MONTH) >= h.mes_atual
    AND IFNULL(TRIM(e.companyGroup), '') <> ''
    AND e.companyGroup <> 'Bloko Capital'
)
SELECT
  a.companyGroup,
  a.companyName,
  a.subJudicie,
  a.MesVencimento,
  ROUND(SUM(a.ValorBruto), 2)                                         AS ValorContratado,
  ROUND(SUM(a.ValorBruto) * ANY_VALUE(COALESCE(t.taxa, g.taxa)), 2)   AS ValorAjustado,
  ROUND(ANY_VALUE(COALESCE(t.taxa, g.taxa)), 6)                       AS PctEsperado
FROM aberto a
LEFT JOIN taxa_grupo t
  ON t.companyGroup = a.companyGroup
CROSS JOIN taxa_geral g
GROUP BY 1, 2, 3, 4;


-- ####################################################################
-- CONFERENCIA (rodar na mao): proximos 12 meses
-- ####################################################################
-- SELECT
--   MesVencimento,
--   ROUND(SUM(ValorContratado)) AS contratado,
--   ROUND(SUM(ValorAjustado))   AS ajustado,
--   ROUND(100 * SAFE_DIVIDE(SUM(ValorAjustado), SUM(ValorContratado)), 1) AS pct_esperado
-- FROM `dadosfinanceiro-501613.looker_studio.recebimentos_futuros`
-- WHERE MesVencimento < DATE_ADD(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 12 MONTH)
-- GROUP BY 1
-- ORDER BY 1;
