CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.cobranca3p` AS

SELECT

  SAFE_CAST(cdEmpresa AS INT64) AS cdEmpresa,

  CAST(nmEmpresa AS STRING) AS nmEmpresa,

  SAFE_CAST(dtVencto AS DATE) AS dtVencto,

  CAST(nmCliente AS STRING) AS nmCliente,

  CAST(nuDocumento AS STRING) AS nuDocumento,

  SAFE_CAST(nuTitulo AS INT64) AS nuTitulo,

  SAFE_CAST(nuParcela AS INT64) AS nuParcela,

  CAST(cdTipoCondicao AS STRING) AS cdTipoCondicao,



  SAFE_CAST(REPLACE(CAST(vlOriginal AS STRING), ',', '.') AS FLOAT64) AS vlOriginal,

  SAFE_CAST(cdIndexador AS INT64) AS cdIndexador,

  SAFE_CAST(REPLACE(CAST(vlCorrecao AS STRING), ',', '.') AS INT64) AS vlCorrecao,

  SAFE_CAST(REPLACE(CAST(vlJuroContr AS STRING), ',', '.') AS INT64) AS vlJuroContr,

  SAFE_CAST(REPLACE(CAST(vlSaldoAtual AS STRING), ',', '.') AS FLOAT64) AS vlSaldoAtual,

  SAFE_CAST(nuDiasAtraso AS INT64) AS nuDiasAtraso,

  SAFE_CAST(REPLACE(CAST(vlJuro AS STRING), ',', '.') AS FLOAT64) AS vlJuro,

  SAFE_CAST(REPLACE(CAST(vlMulta AS STRING), ',', '.') AS FLOAT64) AS vlMulta,

  SAFE_CAST(REPLACE(CAST(vlOutro AS STRING), ',', '.') AS INT64) AS vlOutro,

  SAFE_CAST(REPLACE(CAST(vlDesconto AS STRING), ',', '.') AS INT64) AS vlDesconto,

  SAFE_CAST(REPLACE(CAST(vlSeguro AS STRING), ',', '.') AS INT64) AS vlSeguro,

  SAFE_CAST(REPLACE(CAST(vlTaxaAdm AS STRING), ',', '.') AS INT64) AS vlTaxaAdm,

  SAFE_CAST(REPLACE(CAST(vlTotal AS STRING), ',', '.') AS FLOAT64) AS vlTotal,



  CAST(nuUnidadePrincipal AS STRING) AS nuUnidadePrincipal,

  CAST(NumeroCPFCNPJ AS STRING) AS NumeroCPFCNPJ,

  CAST(NomeDoEmpreendimento AS STRING) AS NomeDoEmpreendimento,

  CAST(DescricaoDoPortador AS STRING) AS DescricaoDoPortador,

  CAST(SituacaoTitulo AS STRING) AS SituacaoTitulo,

  CAST(OperacaoDeCobranca AS STRING) AS OperacaoDeCobranca,

  CAST(Chave_recebidos AS STRING) AS Chave_recebidos,

  SAFE_CAST(CentroCusto AS INT64) AS CentroCusto,

  CAST(Chave AS STRING) AS Chave,



  CAST(Empreendimento_Corrigido AS STRING) AS Empreendimento_Corrigido,

  CAST(Chave_especificacao AS STRING) AS Chave_especificacao,

  CAST(Elegibilidade_Parcela AS STRING) AS Elegibilidade_Parcela,

  CAST(Elegibilidade_Contrato2 AS STRING) AS Elegibilidade_Contrato2,



  SAFE_CAST(REPLACE(CAST(percentual_Bloko AS STRING), ',', '.') AS FLOAT64) AS percentual_Bloko,

  SAFE_CAST(col_1o_Mes_Capitalizacao AS INT64) AS col_1o_Mes_Capitalizacao,

  SAFE_CAST(Meses_de_capitalizacao AS INT64) AS Meses_de_capitalizacao,



  CAST(Tipo_Especificacao AS STRING) AS Tipo_Especificacao,

  CAST(Especificacao AS STRING) AS Especificacao,



  SAFE_CAST(REPLACE(CAST(Valor_Futuro AS STRING), ',', '.') AS FLOAT64) AS Valor_Futuro,

  SAFE_CAST(REPLACE(CAST(Valor_Presente AS STRING), ',', '.') AS FLOAT64) AS Valor_Presente,

  SAFE_CAST(REPLACE(CAST(Tt_Rcb_Bloko AS STRING), ',', '.') AS FLOAT64) AS Tt_Rcb_Bloko,

  SAFE_CAST(REPLACE(CAST(Tt_Rcb_Parceiro AS STRING), ',', '.') AS FLOAT64) AS Tt_Rcb_Parceiro,

  SAFE_CAST(REPLACE(CAST(VF_Bloko AS STRING), ',', '.') AS FLOAT64) AS VF_Bloko,

  SAFE_CAST(REPLACE(CAST(VF_Parceiro AS STRING), ',', '.') AS FLOAT64) AS VF_Parceiro,

  SAFE_CAST(REPLACE(CAST(VP_Bloko AS STRING), ',', '.') AS FLOAT64) AS VP_Bloko,

  SAFE_CAST(REPLACE(CAST(VP_Parceiro AS STRING), ',', '.') AS FLOAT64) AS VP_Parceiro,



  CAST(Vencido_A_vencer AS STRING) AS Vencido_A_vencer,



  SAFE_CAST(REPLACE(CAST(Preco_Tabela AS STRING), ',', '.') AS FLOAT64) AS Preco_Tabela,

  SAFE_CAST(REPLACE(CAST(VlPago AS STRING), ',', '.') AS FLOAT64) AS VlPago,

  SAFE_CAST(QtdParcelasPagas AS INT64) AS QtdParcelasPagas,



  CAST(UltimoPagamento AS STRING) AS UltimoPagamento,



  SAFE_CAST(REPLACE(CAST(VlrAberto AS STRING), ',', '.') AS FLOAT64) AS VlrAberto,

  SAFE_CAST(REPLACE(CAST(VlrContrato AS STRING), ',', '.') AS FLOAT64) AS VlrContrato,

  SAFE_CAST(REPLACE(CAST(LTV_Contrato AS STRING), ',', '.') AS FLOAT64) AS LTV_Contrato,

  SAFE_CAST(REPLACE(CAST(LTV_Tabela AS STRING), ',', '.') AS FLOAT64) AS LTV_Tabela,



  CAST(Status_obra AS STRING) AS Status_obra,

  CAST(Juridico_autal AS STRING) AS Juridico_autal,



  SAFE_CAST(REPLACE(CAST(Vencido_VF AS STRING), ',', '.') AS FLOAT64) AS Vencido_VF,

  SAFE_CAST(REPLACE(CAST(A_vencer_VF AS STRING), ',', '.') AS INT64) AS A_vencer_VF,

  SAFE_CAST(REPLACE(CAST(Vencido_VP AS STRING), ',', '.') AS FLOAT64) AS Vencido_VP,

  SAFE_CAST(REPLACE(CAST(A_vencer_VP AS STRING), ',', '.') AS INT64) AS A_vencer_VP,

  SAFE_CAST(REPLACE(CAST(Ajuste_AVP AS STRING), ',', '.') AS INT64) AS Ajuste_AVP,



  CAST(Aging_AVP AS STRING) AS Aging_AVP



FROM `dadosfinanceiro-501613.raw.cobranca3p`;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_cobranca3p` AS

SELECT

  *

FROM `dadosfinanceiro-501613.trusted.cobranca3p`;