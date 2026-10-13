{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'dimensiones']
) }}

WITH maestro_vehiculos AS (

    SELECT DISTINCT

        UPPER(TRIM(REPLACE(placa, '-', ''))) AS placa_limpia,

        UPPER(TRIM(REPLACE(placa, '-', ''))) AS placa,

        UPPER(TRIM(COALESCE(tipo_vehiculo, 'NO ESPECIFICADO'))) AS tipo_vehiculo,

        UPPER(TRIM(COALESCE(marca, 'NO ESPECIFICADO'))) AS marca,

        UPPER(TRIM(COALESCE(modelo, 'NO ESPECIFICADO'))) AS modelo,

        anio_fabricacion

    FROM {{ ref('plata_vehiculos_maestro') }}

    WHERE placa IS NOT NULL
      AND TRIM(placa) <> ''

),

accidentes_vehiculos AS (

    SELECT DISTINCT

        UPPER(TRIM(REPLACE(placa, '-', ''))) AS placa_limpia,

        UPPER(
            TRIM(
                COALESCE(
                    direccion_desplazamiento,
                    'NO ESPECIFICADO'
                )
            )
        ) AS direccion_desplazamiento

    FROM {{ ref('plata_vehiculos_accidente') }}

    WHERE placa IS NOT NULL
      AND TRIM(placa) <> ''

),

vehiculos_unificados AS (

    SELECT

        COALESCE(
            m.placa,
            a.placa_limpia
        ) AS placa,

        COALESCE(
            m.tipo_vehiculo,
            'NO ESPECIFICADO'
        ) AS tipo_vehiculo,

        COALESCE(
            m.marca,
            'NO ESPECIFICADO'
        ) AS marca,

        COALESCE(
            m.modelo,
            'NO ESPECIFICADO'
        ) AS modelo,

        m.anio_fabricacion,

        CASE

            WHEN COALESCE(m.tipo_vehiculo, '') LIKE '%TAXI%'
              OR COALESCE(m.tipo_vehiculo, '') LIKE '%MICROBUS%'
              OR COALESCE(m.tipo_vehiculo, '') LIKE '%MINIBUS%'
              OR COALESCE(m.tipo_vehiculo, '') LIKE '%AUTOBUS%'
              OR COALESCE(m.tipo_vehiculo, '') LIKE '%BUS%'

            THEN 'PUBLICO'

            WHEN COALESCE(m.tipo_vehiculo, '') LIKE '%CAMION%'
              OR COALESCE(m.tipo_vehiculo, '') LIKE '%FURGONETA%'

            THEN 'CARGA'

            ELSE 'PARTICULAR'

        END AS uso,

        COALESCE(
            a.direccion_desplazamiento,
            'NO ESPECIFICADO'
        ) AS direccion_desplazamiento

    FROM maestro_vehiculos m

    FULL OUTER JOIN accidentes_vehiculos a
        ON m.placa_limpia = a.placa_limpia

),

final AS (

    SELECT DISTINCT
        placa,
        tipo_vehiculo,
        marca,
        modelo,
        anio_fabricacion,
        uso,
        direccion_desplazamiento

    FROM vehiculos_unificados

)

SELECT

    {{ dbt_utils.generate_surrogate_key([
        'placa',
        'direccion_desplazamiento'
    ]) }} AS vehiculo_key,

    placa,
    tipo_vehiculo,
    marca,
    modelo,
    anio_fabricacion,
    uso,
    direccion_desplazamiento

FROM final