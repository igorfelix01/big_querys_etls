-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_DIARIO_PREVISTO

-- Grafico "Recebiveis Diarios": RECEBIDO x PREVISTO x COMPETENCIA,

-- acumulados dia a dia, por centro de custo (empreendimento).

--

-- Universo: contratos de venda (documentIdentificationId = 'CT'),

--   sem sub judice (subJudicie = 'N'), companyGroup valido e sem Bloko.

--   Base: looker_studio.recebiveis_situacao_parcela (a mesma do grafico

--   atual recebiveis_diario_acumulado).

--

-- RECEBIDO (colunas): Conta = 'Efeito Caixa' (banco), pela data de

--   pagamento, cor = SituacaoParcela no momento do pagamento

--   (Ato / Quitacao / Venda a vista / Antecipado / Adimplente /

--   Atrasado / Inadimplente). No mes atual o acumulado para em HOJE.

--

-- COMPETENCIA (linha): parcelas pelo dia de VENCIMENTO.

--   paga  -> o que foi recebido dela (Efeito Caixa)

--   aberta-> valor original

--

-- PREVISTO (linha), por centro de custo:

--   a. carteira no dia 1 do mes: parcelas emitidas antes do dia 1 e que

--      ainda estavam em aberto no dia 1 (pagas no dia 1 ou depois, ou

--      ainda no A Receber). Contrato distratado antes do dia 1 sai.

--   b. contrato no dia 1: Adimplente (nada vencido) / Atrasado (vencida

--      mais antiga com ate 90 dias) / Inadimplente (mais de 90)

--   c. parcela: 'mes' (vence no mes) / 'vencida' (venceu antes) /

--      'futura' (so antecipacao). Ato, Quitacao e Venda a vista FORA.

--   d. taxa = pago dentro do mes (Efeito Caixa) / carteira do dia 1, nos

--      3 meses anteriores, por situacao x classe. Centro de custo com

--      amostra < R$ 50 mil -> taxa da carteira inteira.

--   e. ajuste por dias uteis: taxa x (dias uteis do mes / media dos dias

--      uteis da amostra), teto 100%.

--   f. previsto = carteira do dia 1 x taxa ajustada.

--   g. dias: 'mes' segue o padrao historico "vence no dia X -> pago no

--      dia Y"; 'vencida' e antecipacao seguem o padrao historico por

--      dia util (1o dia util, 2o...). Tudo cai em dia util (feriados

--      bancarios nacionais).

--   h. + antecipacoes: media mensal das futuras pagas na amostra, com o

--      mesmo ajuste de dias uteis.

--   "Pago" = entrou no banco (Conta = 'Efeito Caixa').

--

-- Bloko / Parceiro: mesma proporcao Bloko/Bruto do centro de custo.

-- SEM periodo fixo: todos os meses com 3 meses de amostra; o periodo e o

-- filtro do Looker (MesReferencia / DataReferencia).

--

-- Depende de: looker_studio.recebiveis_situacao_parcela,

--             analytics.dim_empreendimentos_vendas

-- ####################################################################



DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.recebiveis_diario_previsto`;-- [otimizacao] CTE 'base' usada 5x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE base AS
  SELECT

    CAST(ChaveGeral AS STRING)                        AS ChaveGeral,

    CAST(ChaveEspecifica AS STRING)                   AS ChaveEspecifica,

    OrigemBase,

    Conta,

    SituacaoParcela,

    CAST(paymentTerm_id AS STRING)                    AS paymentTerm_id,

    SAFE_CAST(costCenterId AS INT64)                  AS costCenterId,

    costCenterName,

    companyGroup,

    companyName,

    dueDate,

    paymentDate,

    COALESCE(issueDate, installmentBaseDate, contractDate) AS inicio,

    cancellationDate,

    CAST(IFNULL(ValorBruto, 0)    AS FLOAT64)         AS ValorBruto,

    CAST(IFNULL(ValorBloko, 0)    AS FLOAT64)         AS ValorBloko,

    CAST(IFNULL(ValorParceiro, 0) AS FLOAT64)         AS ValorParceiro,

    CAST(COALESCE(originalAmount, ValorBruto, 0) AS FLOAT64) AS original

  FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`

  WHERE documentIdentificationId = 'CT'

    AND subJudicie = 'N'

    AND companyGroup IS NOT NULL

    AND TRIM(companyGroup) <> ''

    AND companyGroup <> 'Bloko Capital'

    AND ChaveEspecifica IS NOT NULL

    AND dueDate IS NOT NULL;

-- [otimizacao] CTE 'pagamentos' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE pagamentos AS
  SELECT ChaveGeral, ChaveEspecifica, dueDate, costCenterId, paymentDate,

         SituacaoParcela, ValorBruto, ValorBloko, ValorParceiro

  FROM base

  WHERE OrigemBase = 'Recebidas'

    AND Conta = 'Efeito Caixa'

    AND paymentDate IS NOT NULL;

-- [otimizacao] CTE 'limites' usada 9x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE limites AS
  SELECT DATE_ADD(DATE_TRUNC(MIN(paymentDate), MONTH), INTERVAL 3 MONTH) AS mes_inicio

  FROM pagamentos;

-- [otimizacao] CTE 'anos' usada 6x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE anos AS
WITH
hoje AS (

  SELECT

    CURRENT_DATE('America/Sao_Paulo')                    AS d,

    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual

),

anos_base AS (

  SELECT y

  FROM limites, hoje,

  UNNEST(GENERATE_ARRAY(EXTRACT(YEAR FROM limites.mes_inicio) - 1,

                        EXTRACT(YEAR FROM hoje.d) + 1)) AS y

),

pascoa_1 AS (

  SELECT y, MOD(y, 19) AS a, DIV(y, 100) AS b, MOD(y, 100) AS c FROM anos_base

),

pascoa_2 AS (

  SELECT y, a, c,

         MOD(b, 4) AS e,

         MOD(19 * a + b - DIV(b, 4) - DIV(b - DIV(b + 8, 25) + 1, 3) + 15, 30) AS h

  FROM pascoa_1

),

pascoa_3 AS (

  SELECT y, a, h, MOD(32 + 2 * e + 2 * DIV(c, 4) - h - MOD(c, 4), 7) AS l FROM pascoa_2

)
SELECT * FROM (


  SELECT y,

         DATE(y,

              DIV(h + l - 7 * DIV(a + 11 * h + 22 * l, 451) + 114, 31),

              MOD(h + l - 7 * DIV(a + 11 * h + 22 * l, 451) + 114, 31) + 1) AS pascoa

  FROM pascoa_3


);

-- [otimizacao] CTE 'dias' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE dias AS
WITH
hoje AS (

  SELECT

    CURRENT_DATE('America/Sao_Paulo')                    AS d,

    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual

),

feriados AS (

  SELECT DATE(y, md.m, md.dd) AS d

  FROM anos,

  UNNEST([STRUCT(1 AS m, 1 AS dd), (4, 21), (5, 1), (9, 7), (10, 12),

          (11, 2), (11, 15), (12, 25)]) AS md

  UNION ALL

  SELECT DATE(y, 11, 20) FROM anos WHERE y >= 2024              -- Consciencia Negra

  UNION ALL

  SELECT DATE_SUB(pascoa, INTERVAL 48 DAY) FROM anos         -- Carnaval (seg)

  UNION ALL

  SELECT DATE_SUB(pascoa, INTERVAL 47 DAY) FROM anos         -- Carnaval (ter)

  UNION ALL

  SELECT DATE_SUB(pascoa, INTERVAL 2 DAY)  FROM anos         -- Sexta-feira Santa

  UNION ALL

  SELECT DATE_ADD(pascoa, INTERVAL 60 DAY) FROM anos         -- Corpus Christi

)
SELECT * FROM (


  SELECT

    dia AS Data,

    DATE_TRUNC(dia, MONTH) AS Mes,

    EXTRACT(DAYOFWEEK FROM dia) NOT IN (1, 7)

      AND dia NOT IN (SELECT f.d FROM feriados f) AS util

  FROM limites, hoje,

  UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(limites.mes_inicio, INTERVAL 4 MONTH),

                             LAST_DAY(hoje.d, MONTH))) AS dia


);

-- [otimizacao] CTE 'dias_uteis' usada 5x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE dias_uteis AS
  SELECT

    Data, Mes,

    ROW_NUMBER() OVER (PARTITION BY Mes ORDER BY Data) AS k,

    COUNT(*)     OVER (PARTITION BY Mes)               AS n

  FROM dias

  WHERE util;

-- [otimizacao] CTE 'qtd_uteis' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE qtd_uteis AS
  SELECT Mes, MAX(n) AS du FROM dias_uteis GROUP BY 1;

-- [otimizacao] CTE 'dia_util_de' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE dia_util_de AS
  SELECT

    Data,

    Mes,

    COALESCE(

      FIRST_VALUE(IF(util, Data, NULL) IGNORE NULLS) OVER (

        PARTITION BY Mes ORDER BY Data

        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING),

      MAX(IF(util, Data, NULL)) OVER (PARTITION BY Mes)

    ) AS DataUtil

  FROM dias;

-- [otimizacao] CTE 'carteira' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE carteira AS
WITH
hoje AS (

  SELECT

    CURRENT_DATE('America/Sao_Paulo')                    AS d,

    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual

),

parcela AS (

  SELECT

    ChaveEspecifica,

    dueDate,

    ANY_VALUE(ChaveGeral)                              AS ChaveGeral,

    ANY_VALUE(costCenterId)                            AS costCenterId,

    MIN(inicio)                                        AS inicio,

    MAX(original)                                      AS original,

    LOGICAL_OR(OrigemBase = 'A Receber')               AS aberta,

    MAX(IF(OrigemBase = 'Recebidas', paymentDate, NULL)) AS ultimo_pagamento,

    LOGICAL_OR(paymentTerm_id IN ('AT', 'QT')

               OR SituacaoParcela IN ('Ato', 'Quitação', 'Venda à vista')) AS fora

  FROM base

  GROUP BY ChaveEspecifica, dueDate

),

distrato AS (

  SELECT ChaveGeral, MIN(cancellationDate) AS data_distrato

  FROM base

  WHERE cancellationDate IS NOT NULL

  GROUP BY 1

)
SELECT * FROM (


  SELECT

    p.ChaveEspecifica,

    p.dueDate,

    p.ChaveGeral,

    p.costCenterId,

    p.original,

    p.fora,

    M AS Mes,

    CASE

      WHEN DATE_TRUNC(p.dueDate, MONTH) = M THEN 'mes'

      WHEN p.dueDate < M                    THEN 'vencida'

      ELSE                                       'futura'

    END AS classe

  FROM parcela p

  CROSS JOIN hoje h

  CROSS JOIN limites l

  LEFT JOIN distrato ds

    ON ds.ChaveGeral = p.ChaveGeral,

  UNNEST(GENERATE_DATE_ARRAY(

    GREATEST(

      DATE_ADD(DATE_TRUNC(COALESCE(p.inicio, DATE_SUB(p.dueDate, INTERVAL 12 MONTH)), MONTH),

               INTERVAL 1 MONTH),

      DATE_SUB(l.mes_inicio, INTERVAL 3 MONTH)),

    IF(p.aberta, h.mes_atual, DATE_TRUNC(p.ultimo_pagamento, MONTH)),

    INTERVAL 1 MONTH)) AS M

  WHERE (p.aberta OR p.ultimo_pagamento IS NOT NULL)

    AND (ds.data_distrato IS NULL OR ds.data_distrato >= M)


);

-- [otimizacao] CTE 'pago_mes' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE pago_mes AS
  SELECT ChaveEspecifica, dueDate, DATE_TRUNC(paymentDate, MONTH) AS Mes,

         paymentDate, SUM(ValorBruto) AS pago

  FROM pagamentos

  GROUP BY 1, 2, 3, 4;

-- [otimizacao] CTE 'carteira_classificada' usada 5x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE carteira_classificada AS
WITH
situacao_contrato AS (

  SELECT

    ChaveGeral,

    Mes,

    CASE

      WHEN MIN(IF(classe = 'vencida', dueDate, NULL)) IS NULL THEN 'Adimplente'

      WHEN DATE_DIFF(Mes, MIN(IF(classe = 'vencida', dueDate, NULL)), DAY) <= 90 THEN 'Atrasado'

      ELSE 'Inadimplente'

    END AS situacao

  FROM carteira

  GROUP BY 1, 2

),

pago_mes_total AS (

  SELECT ChaveEspecifica, dueDate, Mes, SUM(pago) AS pago

  FROM pago_mes

  GROUP BY 1, 2, 3

)
SELECT * FROM (


  SELECT

    c.*,

    s.situacao,

    IFNULL(pt.pago, 0) AS pago_no_mes

  FROM carteira c

  JOIN situacao_contrato s

    ON s.ChaveGeral = c.ChaveGeral AND s.Mes = c.Mes

  LEFT JOIN pago_mes_total pt

    ON pt.ChaveEspecifica = c.ChaveEspecifica

   AND pt.dueDate = c.dueDate

   AND pt.Mes = c.Mes

  WHERE NOT c.fora


);

-- [otimizacao] CTE 'meses_alvo' usada 6x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE meses_alvo AS
  SELECT DISTINCT Mes AS T

  FROM carteira_classificada, limites

  WHERE Mes >= limites.mes_inicio;

-- [otimizacao] CTE 'media_uteis' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE media_uteis AS
  SELECT t.T, AVG(q.du) AS du_amostra, ANY_VALUE(qa.du) AS du_mes

  FROM meses_alvo t

  JOIN qtd_uteis q

    ON q.Mes BETWEEN DATE_SUB(t.T, INTERVAL 3 MONTH) AND DATE_SUB(t.T, INTERVAL 1 MONTH)

  JOIN qtd_uteis qa

    ON qa.Mes = t.T

  GROUP BY 1;

-- [otimizacao] CTE 'taxa_cc' usada 3x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE taxa_cc AS
WITH
amostra_grupo AS (

  SELECT costCenterId, Mes, situacao, classe,

         SUM(original)    AS aberto,

         SUM(pago_no_mes) AS pago

  FROM carteira_classificada

  WHERE classe IN ('mes', 'vencida')

  GROUP BY 1, 2, 3, 4

)
SELECT * FROM (


  SELECT t.T, a.costCenterId, a.situacao, a.classe,

         SUM(a.aberto) AS aberto, SUM(a.pago) AS pago

  FROM meses_alvo t

  JOIN amostra_grupo a

    ON a.Mes BETWEEN DATE_SUB(t.T, INTERVAL 3 MONTH) AND DATE_SUB(t.T, INTERVAL 1 MONTH)

  GROUP BY 1, 2, 3, 4


);

-- [otimizacao] CTE 'previsto_grupo' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE previsto_grupo AS
WITH
amostra_cc_total AS (

  SELECT T, costCenterId, SUM(aberto) AS aberto_total

  FROM taxa_cc

  GROUP BY 1, 2

),

taxa_geral AS (

  SELECT T, situacao, classe, SAFE_DIVIDE(SUM(pago), SUM(aberto)) AS taxa

  FROM taxa_cc

  GROUP BY 1, 2, 3

),

carteira_alvo AS (

  SELECT c.Mes AS T, c.costCenterId, c.situacao, c.classe,

         EXTRACT(DAY FROM c.dueDate) AS dia_venc,

         SUM(c.original) AS aberto

  FROM carteira_classificada c

  JOIN meses_alvo t ON t.T = c.Mes

  WHERE c.classe IN ('mes', 'vencida')

  GROUP BY 1, 2, 3, 4, 5

)
SELECT * FROM (


  SELECT

    ca.T, ca.costCenterId, ca.situacao, ca.classe, ca.dia_venc,

    ca.aberto

    * LEAST(1,

        COALESCE(

          IF(IFNULL(ct.aberto_total, 0) >= 50000, SAFE_DIVIDE(tc.pago, tc.aberto), NULL),

          tg.taxa,

          0)

        * SAFE_DIVIDE(mu.du_mes, mu.du_amostra)

      ) AS previsto

  FROM carteira_alvo ca

  JOIN media_uteis mu ON mu.T = ca.T

  LEFT JOIN taxa_cc tc

    ON tc.T = ca.T AND tc.costCenterId = ca.costCenterId

   AND tc.situacao = ca.situacao AND tc.classe = ca.classe

  LEFT JOIN amostra_cc_total ct

    ON ct.T = ca.T AND ct.costCenterId = ca.costCenterId

  LEFT JOIN taxa_geral tg

    ON tg.T = ca.T AND tg.situacao = ca.situacao AND tg.classe = ca.classe


);

-- [otimizacao] CTE 'pagos_detalhe' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE pagos_detalhe AS
  SELECT c.Mes, c.classe, EXTRACT(DAY FROM c.dueDate) AS dia_venc,

         pm.paymentDate, pm.pago

  FROM carteira_classificada c

  JOIN pago_mes pm

    ON pm.ChaveEspecifica = c.ChaveEspecifica

   AND pm.dueDate = c.dueDate

   AND pm.Mes = c.Mes;

-- [otimizacao] CTE 'padrao_util' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE padrao_util AS
  SELECT t.T, p.classe, u.k,

         SAFE_DIVIDE(SUM(p.pago),

                     SUM(SUM(p.pago)) OVER (PARTITION BY t.T, p.classe)) AS peso

  FROM meses_alvo t

  JOIN pagos_detalhe p

    ON p.classe IN ('vencida', 'futura')

   AND p.Mes BETWEEN DATE_SUB(t.T, INTERVAL 3 MONTH) AND DATE_SUB(t.T, INTERVAL 1 MONTH)

  JOIN dia_util_de du ON du.Data = p.paymentDate

  JOIN dias_uteis u   ON u.Data = du.DataUtil

  GROUP BY 1, 2, 3;

-- [otimizacao] CTE 'previsto_util_base' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE previsto_util_base AS
WITH
antecipacao AS (

  SELECT

    t.T, c.costCenterId,

    SUM(c.pago_no_mes) / 3 * ANY_VALUE(SAFE_DIVIDE(mu.du_mes, mu.du_amostra)) AS previsto

  FROM meses_alvo t

  JOIN media_uteis mu ON mu.T = t.T

  JOIN carteira_classificada c

    ON c.classe = 'futura'

   AND c.Mes BETWEEN DATE_SUB(t.T, INTERVAL 3 MONTH) AND DATE_SUB(t.T, INTERVAL 1 MONTH)

  GROUP BY 1, 2

)
SELECT * FROM (


  SELECT costCenterId, T, 'vencida' AS classe, SUM(previsto) AS previsto

  FROM previsto_grupo WHERE classe = 'vencida' GROUP BY 1, 2

  UNION ALL

  SELECT costCenterId, T, 'futura', previsto FROM antecipacao


);

-- [otimizacao] CTE 'previsto_dia' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE previsto_dia AS
WITH
ultimo_util AS (

  SELECT Mes, MAX(Data) AS DataUtil FROM dias_uteis GROUP BY 1

),

padrao_mes AS (

  SELECT t.T, p.dia_venc, EXTRACT(DAY FROM p.paymentDate) AS dia_pag,

         SAFE_DIVIDE(SUM(p.pago),

                     SUM(SUM(p.pago)) OVER (PARTITION BY t.T, p.dia_venc)) AS peso

  FROM meses_alvo t

  JOIN pagos_detalhe p

    ON p.classe = 'mes'

   AND p.Mes BETWEEN DATE_SUB(t.T, INTERVAL 3 MONTH) AND DATE_SUB(t.T, INTERVAL 1 MONTH)

  GROUP BY 1, 2, 3

),

previsto_mes_dia AS (

  SELECT g.costCenterId, g.T,

         du.DataUtil AS Data,

         g.previsto * IFNULL(pm.peso, 1) AS previsto

  FROM previsto_grupo g

  LEFT JOIN padrao_mes pm

    ON pm.T = g.T AND pm.dia_venc = g.dia_venc

  JOIN dia_util_de du

    ON du.Data = DATE(EXTRACT(YEAR FROM g.T), EXTRACT(MONTH FROM g.T),

                      LEAST(IFNULL(pm.dia_pag, g.dia_venc),

                            EXTRACT(DAY FROM LAST_DAY(g.T, MONTH))))

  WHERE g.classe = 'mes'

),

sem_padrao AS (

  SELECT b.costCenterId, b.T, b.classe, b.previsto

  FROM previsto_util_base b

  LEFT JOIN (SELECT DISTINCT T, classe FROM padrao_util) pu

    ON pu.T = b.T AND pu.classe = b.classe

  WHERE pu.T IS NULL

),

previsto_util_dia AS (

  SELECT b.costCenterId, b.T,

         COALESCE(u.Data, uu.DataUtil) AS Data,

         b.previsto * pu.peso AS previsto

  FROM previsto_util_base b

  JOIN padrao_util pu ON pu.T = b.T AND pu.classe = b.classe

  LEFT JOIN dias_uteis u ON u.Mes = b.T AND u.k = pu.k

  LEFT JOIN ultimo_util uu ON uu.Mes = b.T

  UNION ALL

  -- sem historico: divide igual pelos dias uteis

  SELECT sp.costCenterId, sp.T, u.Data, sp.previsto / u.n

  FROM sem_padrao sp

  JOIN dias_uteis u ON u.Mes = sp.T

)
SELECT * FROM (


  SELECT costCenterId, Data, SUM(previsto) AS Previsto

  FROM (

    SELECT costCenterId, Data, previsto FROM previsto_mes_dia

    UNION ALL

    SELECT costCenterId, Data, previsto FROM previsto_util_dia

  )

  GROUP BY 1, 2


);

-- [otimizacao] CTE 'recebido_dia' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE recebido_dia AS
  SELECT

    costCenterId,

    paymentDate AS Data,

    SUM(IF(SituacaoParcela = 'Adimplente',    ValorBruto, 0)) AS Adimplente,

    SUM(IF(SituacaoParcela = 'Atrasado',      ValorBruto, 0)) AS Atrasado,

    SUM(IF(SituacaoParcela = 'Inadimplente',  ValorBruto, 0)) AS Inadimplente,

    SUM(IF(SituacaoParcela = 'Antecipado',    ValorBruto, 0)) AS Antecipado,

    SUM(IF(SituacaoParcela = 'Quitação',      ValorBruto, 0)) AS Quitacao,

    SUM(IF(SituacaoParcela = 'Venda à vista', ValorBruto, 0)) AS VendaAVista,

    SUM(IF(SituacaoParcela = 'Ato',           ValorBruto, 0)) AS Ato,

    SUM(ValorBruto)    AS Recebido_Bruto,

    SUM(ValorBloko)    AS Recebido_Bloko,

    SUM(ValorParceiro) AS Recebido_Parceiro

  FROM pagamentos

  GROUP BY 1, 2;

-- [otimizacao] CTE 'competencia_dia' usada 2x: calculada 1 vez como tabela temporaria
CREATE OR REPLACE TEMP TABLE competencia_dia AS
  SELECT costCenterId, dueDate AS Data,

         SUM(IF(OrigemBase = 'A Receber', original,

                IF(Conta = 'Efeito Caixa', ValorBruto, 0))) AS Competencia,

         SUM(IF(OrigemBase = 'A Receber', original, 0))     AS EmAberto

  FROM base

  GROUP BY 1, 2;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_diario_previsto`

CLUSTER BY companyGroup, costCenterId, MesReferencia

AS
WITH
hoje AS (

  SELECT

    CURRENT_DATE('America/Sao_Paulo')                    AS d,

    DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH) AS mes_atual

),

centro AS (

  SELECT

    costCenterId,

    ANY_VALUE(costCenterName) AS costCenterName,

    ANY_VALUE(companyGroup)   AS companyGroup,

    ANY_VALUE(companyName)    AS companyName,

    IFNULL(SAFE_DIVIDE(SUM(ValorBloko), SUM(ValorBruto)), 1)    AS pBloko,

    IFNULL(SAFE_DIVIDE(SUM(ValorParceiro), SUM(ValorBruto)), 0) AS pParceiro

  FROM base

  GROUP BY 1

),

centro_mes AS (

  SELECT DISTINCT costCenterId, DATE_TRUNC(Data, MONTH) AS Mes

  FROM (

    SELECT costCenterId, Data FROM recebido_dia

    UNION ALL SELECT costCenterId, Data FROM competencia_dia

    UNION ALL SELECT costCenterId, Data FROM previsto_dia

  ), limites, hoje

  WHERE Data >= limites.mes_inicio

    AND Data <= LAST_DAY(hoje.d, MONTH)

),

grade AS (

  SELECT cm.costCenterId, cm.Mes, d AS Data

  FROM centro_mes cm,

  UNNEST(GENERATE_DATE_ARRAY(cm.Mes, LAST_DAY(cm.Mes, MONTH))) AS d

),

diario AS (

  SELECT

    g.costCenterId, g.Mes, g.Data,

    IFNULL(r.Adimplente, 0)        AS Adimplente_ValorBruto,

    IFNULL(r.Atrasado, 0)          AS Atrasado_ValorBruto,

    IFNULL(r.Inadimplente, 0)      AS Inadimplente_ValorBruto,

    IFNULL(r.Antecipado, 0)        AS Antecipado_ValorBruto,

    IFNULL(r.Quitacao, 0)          AS Quitacao_ValorBruto,

    IFNULL(r.VendaAVista, 0)       AS VendaAVista_ValorBruto,

    IFNULL(r.Ato, 0)               AS Ato_ValorBruto,

    IFNULL(r.Recebido_Bruto, 0)    AS Recebido_Bruto,

    IFNULL(r.Recebido_Bloko, 0)    AS Recebido_Bloko,

    IFNULL(r.Recebido_Parceiro, 0) AS Recebido_Parceiro,

    IFNULL(c.Competencia, 0)       AS Competencia_Bruto,

    IFNULL(c.EmAberto, 0)          AS EmAberto_Bruto,

    IFNULL(p.Previsto, 0)          AS Previsto_Bruto

  FROM grade g

  LEFT JOIN recebido_dia r    ON r.costCenterId = g.costCenterId AND r.Data = g.Data

  LEFT JOIN competencia_dia c ON c.costCenterId = g.costCenterId AND c.Data = g.Data

  LEFT JOIN previsto_dia p    ON p.costCenterId = g.costCenterId AND p.Data = g.Data

),

empreendimento AS (

  SELECT SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,

         ANY_VALUE(projectName) AS projectName,

         ANY_VALUE(enterpriseName) AS enterpriseName

  FROM `dadosfinanceiro-501613.analytics.dim_empreendimentos_vendas`

  WHERE SAFE_CAST(enterpriseId AS INT64) IS NOT NULL

  GROUP BY 1

)
SELECT

  d.Data                                    AS DataReferencia,

  d.Mes                                     AS MesReferencia,

  EXTRACT(DAY FROM d.Data)                  AS Dia,

  FORMAT('%02d', EXTRACT(DAY FROM d.Data))  AS DiaTexto,      -- '01'..'31' (eixo do grafico)

  IFNULL(du.util, FALSE)                    AS EhDiaUtil,     -- sabado/domingo/feriado = FALSE

  d.Mes = h.mes_atual                       AS EhMesAtual,

  d.Data <= h.d                             AS EhAteHoje,



  d.costCenterId,

  ce.costCenterName,

  ce.companyGroup,

  ce.companyName,

  e.projectName,

  e.enterpriseName,



  -- valores do DIA

  ROUND(d.Recebido_Bruto, 2)                         AS Recebido_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(d.Recebido_Bruto, 2)) AS RecebidoNoDia_ValorBruto, -- vazio depois de hoje

  ROUND(d.Recebido_Bloko, 2)                         AS Recebido_ValorBloko,

  ROUND(d.Recebido_Parceiro, 2)                      AS Recebido_ValorParceiro,

  ROUND(d.Previsto_Bruto, 2)                         AS Previsto_ValorBruto,

  ROUND(d.Previsto_Bruto * ce.pBloko, 2)             AS Previsto_ValorBloko,

  ROUND(d.Previsto_Bruto * ce.pParceiro, 2)          AS Previsto_ValorParceiro,

  ROUND(IF(d.Data <= h.d, d.Previsto_Bruto, 0), 2)   AS PrevistoAteHoje_ValorBruto,

  ROUND(IF(d.Data <= h.d, d.Previsto_Bruto * ce.pBloko, 0), 2)    AS PrevistoAteHoje_ValorBloko,

  ROUND(IF(d.Data <= h.d, d.Previsto_Bruto * ce.pParceiro, 0), 2) AS PrevistoAteHoje_ValorParceiro,

  ROUND(d.Competencia_Bruto, 2)                      AS Competencia_ValorBruto,

  ROUND(d.Competencia_Bruto * ce.pBloko, 2)          AS Competencia_ValorBloko,

  ROUND(d.Competencia_Bruto * ce.pParceiro, 2)       AS Competencia_ValorParceiro,



  -- ACUMULADOS do mes (recebido para em hoje no mes atual)

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Adimplente_ValorBruto)   OVER w, 2)) AS acumAdimplente_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Atrasado_ValorBruto)     OVER w, 2)) AS acumAtrasado_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Inadimplente_ValorBruto) OVER w, 2)) AS acumInadimplente_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Antecipado_ValorBruto)   OVER w, 2)) AS acumAntecipado_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Quitacao_ValorBruto)     OVER w, 2)) AS acumQuitacao_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.VendaAVista_ValorBruto)  OVER w, 2)) AS acumVendaAVista_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Ato_ValorBruto)          OVER w, 2)) AS acumAto_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Recebido_Bruto)          OVER w, 2)) AS acumRecebidas_ValorBruto,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Recebido_Bloko)          OVER w, 2)) AS acumRecebidas_ValorBloko,

  IF(d.Data > h.d, NULL, ROUND(SUM(d.Recebido_Parceiro)       OVER w, 2)) AS acumRecebidas_ValorParceiro,



  ROUND(SUM(d.Previsto_Bruto)                 OVER w, 2) AS acumPrevisto_ValorBruto,

  ROUND(SUM(d.Previsto_Bruto * ce.pBloko)     OVER w, 2) AS acumPrevisto_ValorBloko,

  ROUND(SUM(d.Previsto_Bruto * ce.pParceiro)  OVER w, 2) AS acumPrevisto_ValorParceiro,



  ROUND(SUM(d.Competencia_Bruto)                OVER w, 2) AS acumCompetencia_ValorBruto,

  ROUND(SUM(d.Competencia_Bruto * ce.pBloko)    OVER w, 2) AS acumCompetencia_ValorBloko,

  ROUND(SUM(d.Competencia_Bruto * ce.pParceiro) OVER w, 2) AS acumCompetencia_ValorParceiro,



  ROUND(SUM(d.EmAberto_Bruto) OVER w, 2)                 AS acumAReceber



FROM diario d

CROSS JOIN hoje h

LEFT JOIN centro ce          ON ce.costCenterId = d.costCenterId

LEFT JOIN empreendimento e   ON e.enterpriseId  = d.costCenterId

LEFT JOIN dias du            ON du.Data = d.Data

WINDOW w AS (

  PARTITION BY d.costCenterId, d.Mes

  ORDER BY d.Data

  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

);





-- ####################################################################

-- LOOKER_STUDIO.RECEBIVEIS_DIARIO_PREVISTO_TABELA

-- Tabela "Ver dia a dia" embaixo do grafico (Tabela dinamica no Looker):

--   Dimensao da linha  = Linha      ('1. Recebido no dia' / '2. Previsto

--                                     no dia' / '3. Competencia do dia')

--   Dimensao da coluna = DiaTexto   ('01'..'31')

--   Metrica            = ValorMil   (R$ mil, SOMA)

-- Mesmos filtros do grafico (companyGroup, projectName, MesReferencia...).

-- ####################################################################

CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.recebiveis_diario_previsto_tabela`

CLUSTER BY companyGroup, MesReferencia

AS

SELECT

  t.DataReferencia, t.MesReferencia, t.Dia, t.DiaTexto, t.EhDiaUtil,

  t.EhMesAtual, t.EhAteHoje,

  t.costCenterId, t.costCenterName, t.companyGroup, t.companyName,

  t.projectName, t.enterpriseName,

  l.Ordem,

  l.Linha,

  l.ValorBruto,

  l.ValorBloko,

  l.ValorParceiro,

  ROUND(l.ValorBruto / 1000, 3) AS ValorMil

FROM `dadosfinanceiro-501613.looker_studio.recebiveis_diario_previsto` t,

UNNEST([

  STRUCT(1 AS Ordem, '1. Recebido no dia' AS Linha,

         t.RecebidoNoDia_ValorBruto AS ValorBruto,

         IF(t.EhAteHoje, t.Recebido_ValorBloko, NULL) AS ValorBloko,

         IF(t.EhAteHoje, t.Recebido_ValorParceiro, NULL) AS ValorParceiro),

  STRUCT(2, '2. Previsto no dia',

         t.Previsto_ValorBruto, t.Previsto_ValorBloko, t.Previsto_ValorParceiro),

  STRUCT(3, '3. Competência do dia',

         t.Competencia_ValorBruto, t.Competencia_ValorBloko, t.Competencia_ValorParceiro)

]) l;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA: mes atual e 6 anteriores (carteira inteira)

--   previsto_mes x recebido_mes (meses fechados devem ficar perto de 100%)

-- ####################################################################

-- SELECT

--   MesReferencia,

--   ROUND(SUM(Previsto_ValorBruto))     AS previsto_mes,

--   ROUND(SUM(Recebido_ValorBruto))     AS recebido_mes,

--   ROUND(SUM(Competencia_ValorBruto))  AS competencia_mes,

--   ROUND(100 * SAFE_DIVIDE(SUM(Recebido_ValorBruto), SUM(Previsto_ValorBruto)), 1) AS pct_recebido_previsto

-- FROM `dadosfinanceiro-501613.looker_studio.recebiveis_diario_previsto`

-- WHERE MesReferencia >= DATE_SUB(DATE_TRUNC(CURRENT_DATE('America/Sao_Paulo'), MONTH), INTERVAL 6 MONTH)

-- GROUP BY 1

-- ORDER BY 1;