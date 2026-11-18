-- ####################################################################

-- LOOKER_STUDIO.<tabela>_projeto  (VIEWS com a coluna projectName)

--

-- Para o seletor "Projeto" do Looker filtrar TODAS as fontes:

--   o seletor usa analytics.dim_empreendimentos_vendas[projectName] e cada

--   fonte precisa ter um campo com o MESMO nome (projectName) e os mesmos

--   valores. Este script cria, para cada tabela do looker_studio que ainda

--   nao tem projectName, uma VIEW "<tabela>_projeto" = tabela + projectName.

--   As tabelas originais NAO mudam (nada do que ja foi validado muda).

--

-- Como acha o projeto de cada linha (o 1o campo que a tabela tiver):

--   1. enterpriseId   -> dim_empreendimentos_vendas

--   2. costCenterId   -> enterpriseId -> dim_empreendimentos_vendas (igual ao BI)

--   3. ChaveGeral     -> centro de custo do contrato (saldo_devedor) -> dim

--   4. enterpriseName -> dim_empreendimentos_vendas

--   Tabelas ja agregadas, sem nenhum desses campos (cards/medidores/

--   competencia...), NAO tem como ser filtradas por projeto: ficam de fora

--   e aparecem na conferencia final (coluna sem_campo_de_ligacao).

--

-- No Looker: em cada fonte, Editar -> Editar conexao -> escolher a view

--   "<tabela>_projeto" -> Reconectar -> Aplicar. Os campos continuam os

--   mesmos (os graficos nao quebram) e aparece o campo projectName.

--

-- Depende de: todas as tabelas looker_studio, analytics.saldo_devedor,

--             analytics.dim_empreendimentos_vendas

-- ####################################################################



DECLARE comando STRING;



-- 0) linhas de cada tabela do looker_studio (isto tambem faz este arquivo

--    rodar DEPOIS de todas elas no ATUALIZAR_TUDO)

CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.looker_contagem_tabelas` AS

SELECT 'apresentacao_recebimentos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.apresentacao_recebimentos`) AS linhas

UNION ALL

SELECT 'cri_pmt_amortizacao' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.cri_pmt_amortizacao`) AS linhas

UNION ALL

SELECT 'data_atualizacao' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.data_atualizacao`) AS linhas

UNION ALL

SELECT 'distratos_vgv_recebido' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.distratos_vgv_recebido`) AS linhas

UNION ALL

SELECT 'obras_tabela_credores' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.obras_tabela_credores`) AS linhas

UNION ALL

SELECT 'recebidas' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebidas`) AS linhas

UNION ALL

SELECT 'recebiveis_areceber_ano_venda' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_areceber_ano_venda`) AS linhas

UNION ALL

SELECT 'recebiveis_base' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_base`) AS linhas

UNION ALL

SELECT 'recebiveis_cards_carteira' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_carteira`) AS linhas

UNION ALL

SELECT 'recebiveis_cards_contratos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_contratos`) AS linhas

UNION ALL

SELECT 'recebiveis_cards_gauge_v2' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_gauge_v2`) AS linhas

UNION ALL

SELECT 'recebiveis_cards_gauge_v4' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_gauge_v4`) AS linhas

UNION ALL

SELECT 'recebiveis_cards_medias' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_medias`) AS linhas

UNION ALL

SELECT 'recebiveis_cards_situacao_v1' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_cards_situacao_v1`) AS linhas

UNION ALL

SELECT 'recebiveis_carteira_atrasada' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_carteira_atrasada`) AS linhas

UNION ALL

SELECT 'recebiveis_competencia_previsto_recebido_barras' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_barras`) AS linhas

UNION ALL

SELECT 'recebiveis_competencia_previsto_recebido_mensal' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_competencia_previsto_recebido_mensal`) AS linhas

UNION ALL

SELECT 'recebiveis_composicao_competencia' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_composicao_competencia`) AS linhas

UNION ALL

SELECT 'recebiveis_contratos_nao_pagos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_contratos_nao_pagos`) AS linhas

UNION ALL

SELECT 'recebiveis_detalhe_atrasados' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_detalhe_atrasados`) AS linhas

UNION ALL

SELECT 'recebiveis_diario_acumulado' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_diario_acumulado`) AS linhas

UNION ALL

SELECT 'recebiveis_grafico_mensal' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_grafico_mensal`) AS linhas

UNION ALL

SELECT 'recebiveis_historico_contrato' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_historico_contrato`) AS linhas

UNION ALL

SELECT 'recebiveis_historico_mensal' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_historico_mensal`) AS linhas

UNION ALL

SELECT 'recebiveis_matriz_projetos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_matriz_projetos`) AS linhas

UNION ALL

SELECT 'recebiveis_recebido_ano_venda' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_recebido_ano_venda`) AS linhas

UNION ALL

SELECT 'recebiveis_situacao_parcela' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_situacao_parcela`) AS linhas

UNION ALL

SELECT 'recebiveis_tabela_contratos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.recebiveis_tabela_contratos`) AS linhas

UNION ALL

SELECT 'renegociacao_base' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.renegociacao_base`) AS linhas

UNION ALL

SELECT 'renegociacao_eventos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.renegociacao_eventos`) AS linhas

UNION ALL

SELECT 'renegociacao_numero' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.renegociacao_numero`) AS linhas

UNION ALL

SELECT 'renegociacao_recebimentos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.renegociacao_recebimentos`) AS linhas

UNION ALL

SELECT 'tabela_unidades' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.tabela_unidades`) AS linhas

UNION ALL

SELECT 'vendas_contratos_ativos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.vendas_contratos_ativos`) AS linhas

UNION ALL

SELECT 'vendas_segmentacao_contratos_ativos' AS tabela, (SELECT COUNT(*) FROM `dadosfinanceiro-501613.looker_studio.vendas_segmentacao_contratos_ativos`) AS linhas;



-- 1) projeto de cada empreendimento

CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_projeto_por_empreendimento` AS

SELECT

  SAFE_CAST(enterpriseId AS INT64) AS enterpriseId,

  ANY_VALUE(projectName)           AS projectName,

  ANY_VALUE(enterpriseName)        AS enterpriseName

FROM `dadosfinanceiro-501613.analytics.dim_empreendimentos_vendas`

WHERE SAFE_CAST(enterpriseId AS INT64) IS NOT NULL

GROUP BY 1;



-- 2) projeto de cada contrato (centro de custo do contrato -> empreendimento)

CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_projeto_por_contrato` AS

WITH contrato AS (

  SELECT

    CAST(ChaveGeral AS STRING)       AS ChaveGeral,

    SAFE_CAST(costCenterId AS INT64) AS enterpriseId

  FROM `dadosfinanceiro-501613.analytics.saldo_devedor`

  WHERE ChaveGeral IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (

    PARTITION BY ChaveGeral

    ORDER BY IF(OrigemBase = 'A Receber', 0, 1), dueDate DESC

  ) = 1

)

SELECT c.ChaveGeral, c.enterpriseId, p.projectName

FROM contrato c

LEFT JOIN `dadosfinanceiro-501613.analytics.dim_projeto_por_empreendimento` p

  ON p.enterpriseId = c.enterpriseId;



-- 3) uma view "<tabela>_projeto" para cada tabela que ainda nao tem projectName

FOR t IN (

  SELECT

    c.table_name,

    LOGICAL_OR(c.column_name = 'projectName')    AS tem_projeto,

    LOGICAL_OR(c.column_name = 'enterpriseId')   AS tem_enterpriseId,

    LOGICAL_OR(c.column_name = 'costCenterId')   AS tem_costCenterId,

    LOGICAL_OR(c.column_name = 'ChaveGeral')     AS tem_ChaveGeral,

    LOGICAL_OR(c.column_name = 'enterpriseName') AS tem_enterpriseName

  FROM `dadosfinanceiro-501613.looker_studio.INFORMATION_SCHEMA.COLUMNS` c

  JOIN `dadosfinanceiro-501613.looker_studio.INFORMATION_SCHEMA.TABLES` tb

    ON tb.table_name = c.table_name

  WHERE tb.table_type = 'BASE TABLE'

  GROUP BY c.table_name

)

DO

  SET comando = CASE

    WHEN t.tem_projeto THEN NULL

    WHEN t.tem_enterpriseId THEN FORMAT("""

      CREATE OR REPLACE VIEW `dadosfinanceiro-501613.looker_studio.%s_projeto` AS

      SELECT t.*, p.projectName

      FROM `dadosfinanceiro-501613.looker_studio.%s` t

      LEFT JOIN `dadosfinanceiro-501613.analytics.dim_projeto_por_empreendimento` p

        ON p.enterpriseId = SAFE_CAST(t.enterpriseId AS INT64)""", t.table_name, t.table_name)

    WHEN t.tem_costCenterId THEN FORMAT("""

      CREATE OR REPLACE VIEW `dadosfinanceiro-501613.looker_studio.%s_projeto` AS

      SELECT t.*, p.projectName

      FROM `dadosfinanceiro-501613.looker_studio.%s` t

      LEFT JOIN `dadosfinanceiro-501613.analytics.dim_projeto_por_empreendimento` p

        ON p.enterpriseId = SAFE_CAST(SAFE_CAST(CAST(t.costCenterId AS STRING) AS FLOAT64) AS INT64)""", t.table_name, t.table_name)

    WHEN t.tem_ChaveGeral THEN FORMAT("""

      CREATE OR REPLACE VIEW `dadosfinanceiro-501613.looker_studio.%s_projeto` AS

      SELECT t.*, p.projectName

      FROM `dadosfinanceiro-501613.looker_studio.%s` t

      LEFT JOIN `dadosfinanceiro-501613.analytics.dim_projeto_por_contrato` p

        ON p.ChaveGeral = CAST(t.ChaveGeral AS STRING)""", t.table_name, t.table_name)

    WHEN t.tem_enterpriseName THEN FORMAT("""

      CREATE OR REPLACE VIEW `dadosfinanceiro-501613.looker_studio.%s_projeto` AS

      SELECT t.*, p.projectName

      FROM `dadosfinanceiro-501613.looker_studio.%s` t

      LEFT JOIN (

        SELECT enterpriseName, ANY_VALUE(projectName) AS projectName

        FROM `dadosfinanceiro-501613.analytics.dim_projeto_por_empreendimento`

        GROUP BY enterpriseName

      ) p

        ON p.enterpriseName = t.enterpriseName""", t.table_name, t.table_name)

    ELSE NULL

  END;



  IF comando IS NOT NULL THEN

    EXECUTE IMMEDIATE comando;

  END IF;

END FOR;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- CONFERENCIA

-- tabela -> como liga o projeto (ou porque ficou de fora)

-- ####################################################################

-- SELECT

--   c.table_name AS tabela,

--   CASE

--     WHEN LOGICAL_OR(c.column_name = 'projectName')    THEN 'ja tem projectName (usar a propria tabela)'

--     WHEN LOGICAL_OR(c.column_name = 'enterpriseId')   THEN 'view _projeto (por enterpriseId)'

--     WHEN LOGICAL_OR(c.column_name = 'costCenterId')   THEN 'view _projeto (por costCenterId)'

--     WHEN LOGICAL_OR(c.column_name = 'ChaveGeral')     THEN 'view _projeto (por ChaveGeral)'

--     WHEN LOGICAL_OR(c.column_name = 'enterpriseName') THEN 'view _projeto (por enterpriseName)'

--     ELSE 'sem_campo_de_ligacao (tabela ja agregada - nao filtra por projeto)'

--   END AS situacao

-- FROM `dadosfinanceiro-501613.looker_studio.INFORMATION_SCHEMA.COLUMNS` c

-- JOIN `dadosfinanceiro-501613.looker_studio.INFORMATION_SCHEMA.TABLES` tb

--   ON tb.table_name = c.table_name

-- WHERE tb.table_type = 'BASE TABLE'

-- GROUP BY c.table_name

-- ORDER BY situacao, tabela;