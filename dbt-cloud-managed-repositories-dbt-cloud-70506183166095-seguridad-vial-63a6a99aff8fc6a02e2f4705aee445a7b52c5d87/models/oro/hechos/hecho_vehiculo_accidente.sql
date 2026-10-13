{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'hechos']
) }}

WITH vehiculos_base AS (

    SELECT DISTINCT

        id_reporte_accidente,

        UPPER(
            TRIM(
                REPLACE(placa, '-', '')
            )
        ) AS placa,

        UPPER(
            TRIM(
                COALESCE(
                    direccion_desplazamiento,
                    'NO ESPECIFICADO'
                )
            )
        ) AS direccion_desplazamiento

    FROM {{ ref('plata_vehiculos_accidente') }}

    WHERE id_reporte_accidente IS NOT NULL
      AND TRIM(id_reporte_accidente) <> ''
      AND placa IS NOT NULL
      AND TRIM(placa) <> ''

),

accidentes AS (

    SELECT
        codigo_informe_policial,
        fecha_key,
        hora_key,
        ubicacion_key,
        factor_contribuyente_key

    FROM {{ ref('hecho_accidente') }}

)

SELECT

    ROW_NUMBER() OVER (
        ORDER BY
            v.id_reporte_accidente,
            v.placa,
            v.direccion_desplazamiento
    ) AS vehiculo_accidente_key,

    v.id_reporte_accidente AS codigo_informe_policial,

    COALESCE(a.fecha_key, 0) AS fecha_key,

    COALESCE(a.hora_key, 0) AS hora_key,

    COALESCE(
        TO_VARCHAR(a.ubicacion_key),
        '0'
    ) AS ubicacion_key,

    {{ dbt_utils.generate_surrogate_key([
        'v.placa',
        'v.direccion_desplazamiento'
    ]) }} AS vehiculo_key,

    COALESCE(
        a.factor_contribuyente_key,
        0
    ) AS factor_contribuyente_key,

    1 AS conteo_vehiculo

FROM vehiculos_base v

LEFT JOIN accidentes a
    ON v.id_reporte_accidente = a.codigo_informe_policial