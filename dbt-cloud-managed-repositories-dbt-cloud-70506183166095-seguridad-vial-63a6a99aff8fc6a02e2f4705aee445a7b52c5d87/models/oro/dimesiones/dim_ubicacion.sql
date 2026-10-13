{{ config(
    materialized='table',
    schema='oro'
) }}

WITH ubicaciones_limpias AS (

    -- ACCIDENTES
    SELECT

        UPPER(TRIM(macrodistrito)) AS macrodistrito,

        UPPER(
            TRIM(
                COALESCE(
                    zona_barrio,
                    'NO ESPECIFICADO'
                )
            )
        ) AS zona_barrio,

        UPPER(
            TRIM(
                COALESCE(
                    calle_principal,
                    'NO ESPECIFICADO'
                )
            )
        ) AS calle_principal,

        UPPER(
            TRIM(
                COALESCE(
                    calle_secundaria,
                    'NO ESPECIFICADO'
                )
            )
        ) AS calle_secundaria,

        UPPER(
            TRIM(
                COALESCE(
                    direccion_exacta,
                    'NO ESPECIFICADO'
                )
            )
        ) AS punto_referencia,

        latitud,
        longitud

    FROM {{ ref('plata_accidentes') }}

    WHERE macrodistrito IS NOT NULL


    UNION ALL


    -- INFRACCIONES
    SELECT

        UPPER(TRIM(macrodistrito)),

        UPPER(
            TRIM(
                COALESCE(
                    zona_barrio,
                    'NO ESPECIFICADO'
                )
            )
        ),

        UPPER(
            TRIM(
                COALESCE(
                    calle_principal,
                    'NO ESPECIFICADO'
                )
            )
        ),

        UPPER(
            TRIM(
                COALESCE(
                    calle_secundaria,
                    'NO ESPECIFICADO'
                )
            )
        ),

        UPPER(
            TRIM(
                COALESCE(
                    direccion_exacta,
                    'NO ESPECIFICADO'
                )
            )
        ),

        latitud,
        longitud

    FROM {{ ref('plata_infracciones') }}

    WHERE macrodistrito IS NOT NULL


    UNION ALL


    -- DEPOSITOS
    SELECT

        UPPER(TRIM(macrodistrito_deposito)),

        'NO ESPECIFICADO',

        'NO ESPECIFICADO',

        'NO ESPECIFICADO',

        UPPER(
            TRIM(
                COALESCE(
                    nombre_lugar_deposito,
                    'NO ESPECIFICADO'
                )
            )
        ),

        CAST(NULL AS FLOAT),

        CAST(NULL AS FLOAT)

    FROM {{ ref('plata_depositos') }}

    WHERE macrodistrito_deposito IS NOT NULL


    UNION ALL


    -- PROCESOS JUDICIALES
    -- Solo conocemos el macrodistrito.
    SELECT

        UPPER(TRIM(macrodistrito)),

        'NO ESPECIFICADO',

        'NO ESPECIFICADO',

        'NO ESPECIFICADO',

        'NO ESPECIFICADO',

        CAST(NULL AS FLOAT),

        CAST(NULL AS FLOAT)

    FROM {{ ref('plata_judiciales') }}

    WHERE macrodistrito IS NOT NULL

),

consolidado AS (

    SELECT

        macrodistrito,
        zona_barrio,
        calle_principal,
        calle_secundaria,

        MAX(punto_referencia) AS punto_referencia,

        AVG(latitud) AS latitud,

        AVG(longitud) AS longitud

    FROM ubicaciones_limpias

    GROUP BY

        macrodistrito,
        zona_barrio,
        calle_principal,
        calle_secundaria

)

SELECT

    {{ dbt_utils.generate_surrogate_key([
        'macrodistrito',
        'zona_barrio',
        'calle_principal',
        'calle_secundaria'
    ]) }} AS ubicacion_key,

    macrodistrito,
    zona_barrio,
    calle_principal,
    calle_secundaria,
    punto_referencia,
    latitud,
    longitud

FROM consolidado