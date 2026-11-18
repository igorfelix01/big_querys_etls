CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.trusted.unidades`

AS



WITH fonte AS (



  SELECT

    subdominio,

    name,

    propertyType,

    commercialStock,

    locationType,

    frameworkType,

    address,

    cibCode,

    incraCode,

    contractNumber,

    note,



    enterpriseId,

    contractId,



    privateArea,



    COALESCE(

      terrainValue,

      0

    ) AS terrainValue,



    indexedQuantity,

    iptuValue,

    evaluation,



    CAST(latitude AS INT64)

      AS situationId,



    longitude

      AS percentual,



    deliveryDate,

    scheduledDeliveryDate



  FROM

    `dadosfinanceiro-501613.raw.unidades`



  WHERE

    longitude IS NOT NULL

),



com_nome_companhias AS (



  SELECT

    u.*,



    n.companyGroup,

    n.companyId,

    n.companyName,

    n.projectName,

    n.enterpriseName



  FROM fonte u



  LEFT JOIN

    `dadosfinanceiro-501613.analytics.dim_nome_companhias` n



    ON

      u.enterpriseId =

      n.enterpriseId

),



com_situacoes AS (



  SELECT

    u.*,



    s.`Descrição`,

    s.`Classificação Unidades`,

    s.`Classificação Distratos`



  FROM com_nome_companhias u



  LEFT JOIN

    `dadosfinanceiro-501613.analytics.dim_situacoes` s



    ON

      u.situationId =

      s.situationId

),



com_nome_lote AS (



  SELECT

    *,



    ARRAY_TO_STRING(

      [

        CAST(projectName AS STRING),

        CAST(name AS STRING)

      ],

      ' - '

    ) AS NomeLote



  FROM com_situacoes

),



com_chave_lote AS (



  SELECT

    *,



    ARRAY_TO_STRING(

      [

        CAST(companyId AS STRING),

        CAST(enterpriseId AS STRING),

        CAST(name AS STRING)

      ],

      '-'

    ) AS ChaveLote



  FROM com_nome_lote

),



com_chave_empreendimento_lote AS (



  SELECT

    *,



    ARRAY_TO_STRING(

      [

        CAST(companyId AS STRING),

        CAST(enterpriseId AS STRING),

        CAST(name AS STRING)

      ],

      '-'

    ) AS ChaveEmpreendimentoLote



  FROM com_chave_lote

),



com_vendas_unidades AS (



  SELECT

    u.*,

    v.receivableBillId



  FROM com_chave_empreendimento_lote u



  LEFT JOIN

    `dadosfinanceiro-501613.trusted.db_vendas_unidades` v



    ON

      u.ChaveLote =

      v.ChaveLote

)



SELECT



  subdominio,



  name AS unidade,



  propertyType,

  commercialStock,

  locationType,

  frameworkType,

  address,

  cibCode,

  incraCode,

  contractNumber,

  note,



  enterpriseId,

  contractId,



  privateArea,

  terrainValue,

  indexedQuantity,

  iptuValue,

  evaluation,



  situationId,

  percentual,



  deliveryDate,

  scheduledDeliveryDate,



  companyGroup,

  companyId,

  companyName,

  projectName,

  enterpriseName,



  `Descrição`,

  `Classificação Unidades`,

  `Classificação Distratos`,



  NomeLote,

  ChaveLote,

  ChaveEmpreendimentoLote,



  receivableBillId



FROM

  com_vendas_unidades;





CREATE OR REPLACE TABLE

  `dadosfinanceiro-501613.analytics.dim_unidades`

AS



SELECT *

FROM

  `dadosfinanceiro-501613.trusted.unidades`;