CREATE OR REPLACE VIEW `dadosfinanceiro-501613.analytics.dim_empreendimentos_vendas` AS

SELECT

  companyGroup,

  companyId,

  companyName,

  projectName,

  enterpriseId,

  enterpriseName

FROM `dadosfinanceiro-501613.analytics.dim_nome_companhias`;