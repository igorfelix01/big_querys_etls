DROP TABLE IF EXISTS `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`;

-- ####################################################################

-- ANALYTICS.HISTORICOINADIMPLENCIA  (reconstrucao DIARIA)

--

-- Mesmo formato da tabela que ja existe no banco:

--   ChaveGeral, Data, DiasAtraso, QtdParcelas, ParcelasAtrasadas,

--   ParcelasInadimplentes   |  CLUSTER BY ChaveGeral, Data (sem particao)

--

-- Uma linha por dia x contrato ATIVO naquele dia.

--   DiasAtraso            = Data - vencimento da parcela vencida e nao

--                           paga mais antiga (0 se nenhuma)

--   QtdParcelas           = parcelas vencidas e nao pagas naquele dia

--   ParcelasAtrasadas     = dessas, com 1 a 89 dias de atraso

--   ParcelasInadimplentes = dessas, com 90 dias ou mais

--

-- Parcela (ChaveEspecifica) a partir do analytics.saldo_devedor:

--   vencimento = menor dueDate; quitada_em = ultimo paymentDate das

--   recebidas (se ainda aparece no A Receber -> nao quitada).

-- Contrato ativo: entre o 1o vencimento e a quitacao da ultima parcela.

-- Vai do 1o vencimento da base ate HOJE (sem limite fixo).

--

-- Vencimentos antes de 2000 (data errada no Sienge, ex.: 1901) sao ignorados.

-- ####################################################################



CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.HistoricoInadimplencia`

-- (sem particao: validade de particao de 60 dias apagava meses antigos)
CLUSTER BY ChaveGeral

AS



WITH



hoje AS (

  SELECT CURRENT_DATE('America/Sao_Paulo') AS d

),



parcelas AS (

  SELECT

    ChaveGeral,

    ChaveEspecifica,

    MIN(dueDate) AS vencimento,

    IF(COUNTIF(OrigemBase = 'A Receber') > 0, NULL, MAX(paymentDate)) AS quitada_em

  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`

  WHERE ChaveGeral IS NOT NULL

    AND ChaveEspecifica IS NOT NULL

    AND dueDate IS NOT NULL

    -- vencimentos com data errada no Sienge (ex.: 1901) geravam um

    -- historico desde 1901 para o contrato: ficam fora

    AND dueDate >= DATE '2000-01-01'

  GROUP BY ChaveGeral, ChaveEspecifica

),



contratos AS (

  SELECT

    ChaveGeral,

    MIN(vencimento) AS inicio,

    IF(COUNTIF(quitada_em IS NULL) > 0, NULL, MAX(quitada_em)) AS fim

  FROM parcelas

  GROUP BY ChaveGeral

),



-- contrato x cada dia em que esteve ativo

ativos AS (

  SELECT c.ChaveGeral, Data

  FROM contratos c, hoje h,

  UNNEST(GENERATE_DATE_ARRAY(

    c.inicio,

    LEAST(IFNULL(DATE_SUB(c.fim, INTERVAL 1 DAY), h.d), h.d)

  )) AS Data

  WHERE c.inicio <= h.d

),



-- parcela x cada dia em que esteve vencida e nao paga

vencidas_dia AS (

  SELECT

    p.ChaveGeral,

    Data,

    DATE_DIFF(Data, p.vencimento, DAY) AS atraso

  FROM parcelas p, hoje h,

  UNNEST(GENERATE_DATE_ARRAY(

    DATE_ADD(p.vencimento, INTERVAL 1 DAY),

    LEAST(IFNULL(p.quitada_em, h.d), h.d)

  )) AS Data

  WHERE p.vencimento < h.d

    AND (p.quitada_em IS NULL OR p.quitada_em > p.vencimento)

    -- no dia do pagamento a parcela ja conta como paga

    AND (p.quitada_em IS NULL OR Data < p.quitada_em OR p.quitada_em > h.d)

),



resumo_dia AS (

  SELECT

    ChaveGeral,

    Data,

    MAX(atraso)                AS DiasAtraso,

    COUNT(*)                   AS QtdParcelas,

    COUNTIF(atraso < 90)       AS ParcelasAtrasadas,

    COUNTIF(atraso >= 90)      AS ParcelasInadimplentes

  FROM vencidas_dia

  GROUP BY ChaveGeral, Data

)



SELECT

  a.ChaveGeral,

  a.Data,

  IFNULL(r.DiasAtraso, 0)            AS DiasAtraso,

  IFNULL(r.QtdParcelas, 0)           AS QtdParcelas,

  IFNULL(r.ParcelasAtrasadas, 0)     AS ParcelasAtrasadas,

  IFNULL(r.ParcelasInadimplentes, 0) AS ParcelasInadimplentes

FROM ativos a

LEFT JOIN resumo_dia r

  ON r.ChaveGeral = a.ChaveGeral

 AND r.Data = a.Data;