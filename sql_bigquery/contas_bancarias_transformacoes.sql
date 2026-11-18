CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.contas_bancarias` AS

SELECT

  CAST(accountNumber AS STRING) AS accountNumber,

  CAST(Conta AS STRING) AS Conta

FROM `dadosfinanceiro-501613.trusted.contas_bancarias`;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_contas_bancarias` AS

SELECT

  accountNumber,

  Conta

FROM `dadosfinanceiro-501613.trusted.contas_bancarias`;