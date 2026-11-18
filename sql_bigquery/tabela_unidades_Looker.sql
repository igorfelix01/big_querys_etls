-- ####################################################################

-- LOOKER_STUDIO.TABELA_UNIDADES

--

-- Base do visual "Resumo Unidades" do BI:

--   Linhas  : companyGroup, Projeto (projectName)   -> NomeCompanhias

--   Colunas : Classificacao Unidade

--   Valor   : Contagem de cod_unidade

--   Filtro  : companyGroup nao e (Em branco)

--

-- FONTES:

--   raw.atualizacao_unidade_status  (1 linha por unidade)

--   analytics.dim_nome_companhias   (empreendimentos = enterpriseId)

--   analytics.dim_situacoes         (cod_situacao = situationId)

--

-- Chaves conferidas no diagnostico:

--   empreendimentos x enterpriseId : 27.526 de 27.853 unidades casam

--   cod_situacao    x situationId  : 27.312 de 27.853 unidades casam

--

-- Uma linha por unidade (sem agregar), para o Looker montar a tabela

-- dinamica com qualquer filtro.

-- ####################################################################





DROP TABLE IF EXISTS

  `dadosfinanceiro-501613.looker_studio.tabela_unidades`;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.looker_studio.tabela_unidades`



CLUSTER BY

  companyGroup,

  projectName,

  ClassificacaoUnidade



AS



WITH



-- NomeCompanhias: 1 linha por enterpriseId (relacionamento do BI e

-- muitos-para-um; se houver enterpriseId repetido na planilha, fica o

-- primeiro - ver validacao 3)

nome_companhias AS (

  SELECT

    enterpriseId,

    companyGroup,

    companyId,

    companyName,

    projectName,

    enterpriseName

  FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

  WHERE enterpriseId IS NOT NULL

  QUALIFY ROW_NUMBER() OVER (

    PARTITION BY enterpriseId

    ORDER BY companyId, projectName

  ) = 1

),



situacoes AS (

  SELECT

    situationId,

    `Descrição`               AS DescricaoSituacao,

    `Classificação Unidades`  AS ClassificacaoUnidades,

    `Classificação Distratos` AS ClassificacaoDistratos

  FROM `dadosfinanceiro-501613.analytics.dim_situacoes`

  QUALIFY ROW_NUMBER() OVER (PARTITION BY situationId ORDER BY situationId) = 1

)



SELECT

  u.PK,

  u.cod_unidade,

  u.unidades,

  u.unidade_sienge,

  u.subdominio,



  SAFE_CAST(TRIM(u.empreendimentos) AS INT64) AS enterpriseId,

  u.empreendimento_sienge,



  -- NomeCompanhias

  nc.companyGroup,

  nc.companyId,

  nc.companyName,

  nc.projectName,

  nc.enterpriseName,



  -- Situacao

  SAFE_CAST(u.cod_situacao AS INT64)   AS situationId,

  u.situacao_unidade                   AS ClassificacaoUnidade,   -- colunas do visual

  s.ClassificacaoUnidades,                                        -- via dim_situacoes

  s.DescricaoSituacao,

  s.ClassificacaoDistratos,



  u.status,

  u.url_unidade,

  u.data_ultima_atualizacao



FROM `dadosfinanceiro-501613.raw.atualizacao_unidade_status` u



LEFT JOIN nome_companhias nc

  ON nc.enterpriseId = SAFE_CAST(TRIM(u.empreendimentos) AS INT64)



LEFT JOIN situacoes s

  ON s.situationId = SAFE_CAST(u.cod_situacao AS INT64);
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- ####################################################################

-- VALIDACAO

-- ####################################################################



-- 1) mesma matriz do BI (comparar com "Resumo Unidades")

--    NULL = coluna sem titulo do BI

-- SELECT

--   companyGroup,

--   COUNT(cod_unidade)                                                        AS total,

--   COUNTIF(ClassificacaoUnidade IS NULL OR TRIM(ClassificacaoUnidade) = '')  AS sem_classificacao,

--   COUNTIF(ClassificacaoUnidade = 'Carteira Ativa')                          AS carteira_ativa,

--   COUNTIF(ClassificacaoUnidade = 'Contrato Quitado')                        AS contrato_quitado,

--   COUNTIF(ClassificacaoUnidade = 'Em Estoque')                              AS em_estoque,

--   COUNTIF(ClassificacaoUnidade = 'Não Considerar')                          AS nao_considerar

-- FROM `dadosfinanceiro-501613.looker_studio.tabela_unidades`

-- WHERE companyGroup IS NOT NULL

-- GROUP BY companyGroup

-- ORDER BY companyGroup;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- 2) coluna do visual e situacao_unidade ou Classificacao Unidades?

--    (se as duas forem iguais, tanto faz)

-- SELECT

--   ClassificacaoUnidade,

--   ClassificacaoUnidades,

--   COUNT(*) AS unidades

-- FROM `dadosfinanceiro-501613.looker_studio.tabela_unidades`

-- WHERE companyGroup IS NOT NULL

-- GROUP BY 1, 2

-- ORDER BY unidades DESC;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- 3) enterpriseId repetido na NomeCompanhias (planilha)

-- SELECT

--   enterpriseId,

--   COUNT(*) AS qtd,

--   STRING_AGG(DISTINCT companyGroup, ' | ') AS grupos,

--   STRING_AGG(DISTINCT projectName,  ' | ') AS projetos

-- FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

-- GROUP BY enterpriseId

-- HAVING COUNT(*) > 1;
-- [CONFERENCIA desativada na atualizacao automatica para ganhar tempo:
--  para conferir, copie o trecho abaixo sem os '-- ' e rode no BigQuery]






-- 4) empreendimentos sem cadastro na NomeCompanhias (ficam fora, como

--    no filtro "companyGroup nao e (Em branco)" do BI)

-- SELECT

--   empreendimentos,

--   COUNT(*) AS unidades

-- FROM `dadosfinanceiro-501613.raw.atualizacao_unidade_status` u

-- WHERE SAFE_CAST(TRIM(u.empreendimentos) AS INT64) NOT IN (

--   SELECT enterpriseId

--   FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`

--   WHERE enterpriseId IS NOT NULL

-- )

-- GROUP BY empreendimentos

-- ORDER BY unidades DESC;