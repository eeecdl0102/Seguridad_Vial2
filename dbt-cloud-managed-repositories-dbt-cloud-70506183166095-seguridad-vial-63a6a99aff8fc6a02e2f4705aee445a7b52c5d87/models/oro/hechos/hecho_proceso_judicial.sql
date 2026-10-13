{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'hechos']
) }}

WITH procesos AS (

    SELECT

        numero_causa,

        fecha_denuncia,

        fecha_apertura_proceso,

        fecha_sentencia,

        numero_documento_imputado,

        estado_proceso,

        macrodistrito,

        tipo_denuncia,

        nombre_juzgado,

        resumen_denuncia,

        NULLIF(
            TRIM(id_reporte_accidente_relacionado),
            ''
        ) AS codigo_informe_policial

    FROM {{ ref('plata_judiciales') }}

    WHERE numero_causa IS NOT NULL
      AND TRIM(numero_causa) <> ''

),

fechas AS (

    SELECT
        fecha_key,
        fecha_completa

    FROM {{ ref('dim_fecha') }}

),

ubicaciones AS (

    SELECT

        ubicacion_key,

        UPPER(TRIM(macrodistrito)) AS macrodistrito,

        UPPER(TRIM(zona_barrio)) AS zona_barrio,

        UPPER(TRIM(calle_principal)) AS calle_principal,

        UPPER(TRIM(calle_secundaria)) AS calle_secundaria

    FROM {{ ref('dim_ubicacion') }}

),

personas AS (

    SELECT

        persona_key,

        REGEXP_REPLACE(
            UPPER(TRIM(numero_documento)),
            '[^A-Z0-9]',
            ''
        ) AS doc_norm

    FROM {{ ref('dim_persona') }}

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY
            REGEXP_REPLACE(
                UPPER(TRIM(numero_documento)),
                '[^A-Z0-9]',
                ''
            )

        ORDER BY persona_key

    ) = 1

),

estados AS (

    SELECT

        estado_proceso_key,

        UPPER(TRIM(nombre_estado)) AS nombre_estado

    FROM {{ ref('dim_estado_proceso') }}

),

base AS (

    SELECT

        numero_causa,

        fecha_denuncia,

        fecha_apertura_proceso,

        fecha_sentencia,

        numero_documento_imputado,

        estado_proceso,

        macrodistrito,

        tipo_denuncia,

        nombre_juzgado,

        resumen_denuncia,

        codigo_informe_policial

    FROM procesos

)

SELECT

    ROW_NUMBER() OVER (
        ORDER BY b.numero_causa
    ) AS proceso_key,

    b.codigo_informe_policial,

    COALESCE(
        TO_VARCHAR(u.ubicacion_key),
        '0'
    ) AS ubicacion_key,

    COALESCE(
        TO_VARCHAR(p.persona_key),
        '0'
    ) AS persona_key,

    COALESCE(
        fd.fecha_key,
        0
    ) AS fecha_denuncia_key,

    COALESCE(
        fa.fecha_key,
        0
    ) AS fecha_apertura_proceso_key,

    COALESCE(
        fs.fecha_key,
        0
    ) AS fecha_sentencia_key,

    COALESCE(
        e.estado_proceso_key,
        0
    ) AS estado_proceso_key,

    b.tipo_denuncia,

    b.nombre_juzgado,

    b.resumen_denuncia,

    CASE
        WHEN b.fecha_apertura_proceso IS NOT NULL
        THEN DATEDIFF(
            DAY,
            b.fecha_denuncia,
            b.fecha_apertura_proceso
        )
        ELSE NULL
    END AS dias_denuncia_apertura,

    CASE
        WHEN b.fecha_apertura_proceso IS NOT NULL
         AND b.fecha_sentencia IS NOT NULL
        THEN DATEDIFF(
            DAY,
            b.fecha_apertura_proceso,
            b.fecha_sentencia
        )
        ELSE NULL
    END AS dias_apertura_sentencia,

    1 AS cantidad_procesos

FROM base b

LEFT JOIN fechas fd

    ON CAST(b.fecha_denuncia AS DATE)
     = fd.fecha_completa

LEFT JOIN fechas fa

    ON CAST(b.fecha_apertura_proceso AS DATE)
     = fa.fecha_completa

LEFT JOIN fechas fs

    ON CAST(b.fecha_sentencia AS DATE)
     = fs.fecha_completa

LEFT JOIN personas p

    ON REGEXP_REPLACE(
        UPPER(TRIM(b.numero_documento_imputado)),
        '[^A-Z0-9]',
        ''
    ) = p.doc_norm

LEFT JOIN ubicaciones u

    ON UPPER(TRIM(b.macrodistrito))
        = u.macrodistrito

   AND u.zona_barrio = 'NO ESPECIFICADO'

   AND u.calle_principal = 'NO ESPECIFICADO'

   AND u.calle_secundaria = 'NO ESPECIFICADO'

LEFT JOIN estados e

    ON UPPER(TRIM(b.estado_proceso))
        = e.nombre_estado