CREATE OR REPLACE TABLE `dadosfinanceiro-501613.analytics.dim_calendario` AS

WITH limites AS (

  SELECT

    DATE '2000-01-01' AS data_inicio,

    DATE '2040-12-31' AS data_fim

),



datas AS (

  SELECT

    data

  FROM limites,

  UNNEST(GENERATE_DATE_ARRAY(data_inicio, data_fim, INTERVAL 1 DAY)) AS data

)



SELECT

  data AS Data,

  EXTRACT(YEAR FROM data) AS Ano,

  EXTRACT(MONTH FROM data) AS Mes,

  EXTRACT(DAY FROM data) AS Dia,

  EXTRACT(QUARTER FROM data) AS Trimestre,



  FORMAT_DATE('%Y-%m', data) AS AnoMes,

  FORMAT_DATE('%m/%Y', data) AS MesAno,



  CASE EXTRACT(MONTH FROM data)

    WHEN 1 THEN 'Janeiro'

    WHEN 2 THEN 'Fevereiro'

    WHEN 3 THEN 'Março'

    WHEN 4 THEN 'Abril'

    WHEN 5 THEN 'Maio'

    WHEN 6 THEN 'Junho'

    WHEN 7 THEN 'Julho'

    WHEN 8 THEN 'Agosto'

    WHEN 9 THEN 'Setembro'

    WHEN 10 THEN 'Outubro'

    WHEN 11 THEN 'Novembro'

    WHEN 12 THEN 'Dezembro'

  END AS NomeMes,



  CASE EXTRACT(DAYOFWEEK FROM data)

    WHEN 1 THEN 'Domingo'

    WHEN 2 THEN 'Segunda-feira'

    WHEN 3 THEN 'Terça-feira'

    WHEN 4 THEN 'Quarta-feira'

    WHEN 5 THEN 'Quinta-feira'

    WHEN 6 THEN 'Sexta-feira'

    WHEN 7 THEN 'Sábado'

  END AS NomeDiaSemana,



  EXTRACT(DAYOFWEEK FROM data) AS NumeroDiaSemana,



  DATE_TRUNC(data, MONTH) AS InicioMes,

  LAST_DAY(data, MONTH) AS FimMes,



  DATE_TRUNC(data, YEAR) AS InicioAno,

  LAST_DAY(data, YEAR) AS FimAno

FROM datas;