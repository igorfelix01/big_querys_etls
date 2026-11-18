CREATE OR REPLACE TABLE `dadosfinanceiro-501613.trusted.comparativo` AS

SELECT

  REPLACE(CAST(chave_contrato AS STRING), '_', '-') AS chave_contrato,



  CAST(subdominio_antiga AS STRING) AS subdominio_antiga,

  CAST(company_id_antiga AS INT64) AS company_id_antiga,

  CAST(company_name_antiga AS STRING) AS company_name_antiga,

  CAST(costCenter_id_antiga AS INT64) AS costCenter_id_antiga,

  CAST(costCenter_name_antiga AS STRING) AS costCenter_name_antiga,

  CAST(customer_name_antiga AS STRING) AS customer_name_antiga,

  CAST(ultimo_recebimento_antiga AS DATE) AS ultimo_recebimento_antiga,

  CAST(dias_sem_pagar_antiga AS FLOAT64) AS dias_sem_pagar_antiga,

  CAST(status_inadimplencia_antiga AS STRING) AS status_inadimplencia_antiga,

  CAST(contrato_distratado_antiga AS BOOL) AS contrato_distratado_antiga,

  CAST(contrato_reparcelado_antiga AS BOOL) AS contrato_reparcelado_antiga,

  CAST(Quitado_antiga AS BOOL) AS Quitado_antiga,

  CAST(Quitacao_Negociada_antiga AS BOOL) AS Quitacao_Negociada_antiga,

  CAST(Quitacao_Automatica_antiga AS BOOL) AS Quitacao_Automatica_antiga,

  CAST(Quitacao_Emitida_Nao_Paga_antiga AS BOOL) AS Quitacao_Emitida_Nao_Paga_antiga,

  CAST(saldo_devedor_futuro_antiga AS FLOAT64) AS saldo_devedor_futuro_antiga,

  CAST(primeira_duedate_em_aberto_antiga AS DATE) AS primeira_duedate_em_aberto_antiga,

  CAST(valor_inadimplente_antiga AS FLOAT64) AS valor_inadimplente_antiga,

  CAST(grupo_antiga AS STRING) AS grupo_antiga,



  CAST(subdominio_atual AS STRING) AS subdominio_atual,

  CAST(company_id_atual AS INT64) AS company_id_atual,

  CAST(company_name_atual AS STRING) AS company_name_atual,

  CAST(costCenter_id_atual AS INT64) AS costCenter_id_atual,

  CAST(costCenter_name_atual AS STRING) AS costCenter_name_atual,

  CAST(customer_name_atual AS STRING) AS customer_name_atual,

  CAST(ultimo_recebimento_atual AS DATE) AS ultimo_recebimento_atual,

  CAST(dias_sem_pagar_atual AS FLOAT64) AS dias_sem_pagar_atual,

  CAST(status_inadimplencia_atual AS STRING) AS status_inadimplencia_atual,

  CAST(contrato_distratado_atual AS BOOL) AS contrato_distratado_atual,

  CAST(contrato_reparcelado_atual AS BOOL) AS contrato_reparcelado_atual,

  CAST(Quitado_atual AS BOOL) AS Quitado_atual,

  CAST(Quitacao_Negociada_atual AS BOOL) AS Quitacao_Negociada_atual,

  CAST(Quitacao_Automatica_atual AS BOOL) AS Quitacao_Automatica_atual,

  CAST(Quitacao_Emitida_Nao_Paga_atual AS BOOL) AS Quitacao_Emitida_Nao_Paga_atual,

  CAST(saldo_devedor_futuro_atual AS FLOAT64) AS saldo_devedor_futuro_atual,

  CAST(primeira_duedate_em_aberto_atual AS DATE) AS primeira_duedate_em_aberto_atual,

  CAST(valor_inadimplente_atual AS FLOAT64) AS valor_inadimplente_atual,

  CAST(grupo_atual AS STRING) AS grupo_atual,



  CAST(mudou_status_inadimplencia AS BOOL) AS mudou_status_inadimplencia,

  CAST(subdominio AS STRING) AS subdominio,

  CAST(grupo AS STRING) AS grupo,

  CAST(costCenter_id AS INT64) AS costCenter_id,

  CAST(costCenter_name AS STRING) AS costCenter_name,

  CAST(status_inadimplencia AS STRING) AS status_inadimplencia,

  CAST(dias_sem_pagar AS FLOAT64) AS dias_sem_pagar,

  CAST(ultimo_recebimento AS DATE) AS ultimo_recebimento,

  CAST(status_contrato AS STRING) AS status_contrato,

  CAST(mudou_quitacao AS BOOL) AS mudou_quitacao,

  CAST(mudou_distrato AS BOOL) AS mudou_distrato,

  CAST(mudou_emitida_nao_paga AS BOOL) AS mudou_emitida_nao_paga,

  CAST(mudou_reparcelamento AS BOOL) AS mudou_reparcelamento,

  CAST(dif_saldo_devedor AS FLOAT64) AS dif_saldo_devedor,

  CAST(categoria AS STRING) AS categoria,

  CAST(subJudicie AS STRING) AS subJudicie



FROM `dadosfinanceiro-501613.raw.comparativo`;





CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.fato_comparativo` AS

SELECT

  *

FROM `dadosfinanceiro-501613.trusted.comparativo`;