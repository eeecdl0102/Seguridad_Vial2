{{ config(
    materialized='table',
    schema='oro'
) }}

WITH todas_las_fechas AS (

    SELECT fecha_hora AS fecha
    FROM {{ ref('plata_accidentes') }}

    UNION

    SELECT fecha_hora
    FROM {{ ref('plata_infracciones') }}

    UNION

    SELECT fecha_ingreso
    FROM {{ ref('plata_depositos') }}

    UNION

    SELECT fecha_hora_llamada
    FROM {{ ref('plata_llamadas') }}

    UNION

    SELECT fecha_reclamo
    FROM {{ ref('plata_seguros') }}

    UNION

    SELECT fecha_denuncia
    FROM {{ ref('plata_judiciales') }}

    UNION

    SELECT fecha_apertura_proceso
    FROM {{ ref('plata_judiciales') }}

    UNION

    SELECT fecha_sentencia
    FROM {{ ref('plata_judiciales') }}

),

fechas_unicas AS (

    SELECT DISTINCT
        DATE(fecha) AS fecha_completa

    FROM todas_las_fechas

    WHERE fecha IS NOT NULL

)

SELECT

    TO_NUMBER(
        TO_CHAR(fecha_completa, 'YYYYMMDD')
    ) AS fecha_key,

    fecha_completa,

    DAY(fecha_completa) AS dia,

    MONTH(fecha_completa) AS mes,

    CASE MONTH(fecha_completa)

        WHEN 1 THEN 'ENERO'
        WHEN 2 THEN 'FEBRERO'
        WHEN 3 THEN 'MARZO'
        WHEN 4 THEN 'ABRIL'
        WHEN 5 THEN 'MAYO'
        WHEN 6 THEN 'JUNIO'
        WHEN 7 THEN 'JULIO'
        WHEN 8 THEN 'AGOSTO'
        WHEN 9 THEN 'SEPTIEMBRE'
        WHEN 10 THEN 'OCTUBRE'
        WHEN 11 THEN 'NOVIEMBRE'
        WHEN 12 THEN 'DICIEMBRE'

    END AS nombre_mes,

    QUARTER(fecha_completa) AS trimestre,

    YEAR(fecha_completa) AS anio,

    CASE DAYOFWEEK(fecha_completa)

        WHEN 0 THEN 'DOMINGO'
        WHEN 1 THEN 'LUNES'
        WHEN 2 THEN 'MARTES'
        WHEN 3 THEN 'MIÉRCOLES'
        WHEN 4 THEN 'JUEVES'
        WHEN 5 THEN 'VIERNES'
        WHEN 6 THEN 'SÁBADO'

    END AS dia_semana,

    CASE
        WHEN DAYOFWEEK(fecha_completa) IN (0, 6)
        THEN TRUE
        ELSE FALSE
    END AS es_fin_semana,

    FALSE AS es_feriado

FROM fechas_unicas