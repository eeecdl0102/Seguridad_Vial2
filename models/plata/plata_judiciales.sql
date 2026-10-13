{{ config(
    materialized='table',
    schema='plata',
    tags=['plata']
) }}

WITH fuente_bruta AS (

    SELECT *
    FROM {{ source('la_paz_vial', 'PROCESOS_JUDICIALES') }}

),

deduplicado AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY numero_causa
            ORDER BY fecha_denuncia DESC
        ) AS rn

    FROM fuente_bruta

),

fechas_parseadas AS (

    SELECT

        *,

        COALESCE(
            TRY_TO_DATE(
                CAST(fecha_denuncia AS VARCHAR),
                'YYYY-MM-DD'
            ),
            TRY_TO_DATE(
                CAST(fecha_denuncia AS VARCHAR),
                'DD/MM/YYYY'
            ),
            TRY_CAST(fecha_denuncia AS DATE)
        ) AS fecha_denuncia_parsed,

        COALESCE(
            TRY_TO_DATE(
                CAST(fecha_apertura_proceso AS VARCHAR),
                'YYYY-MM-DD'
            ),
            TRY_TO_DATE(
                CAST(fecha_apertura_proceso AS VARCHAR),
                'DD/MM/YYYY'
            ),
            TRY_CAST(fecha_apertura_proceso AS DATE)
        ) AS fecha_apertura_parsed,

        COALESCE(
            TRY_TO_DATE(
                CAST(fecha_sentencia AS VARCHAR),
                'YYYY-MM-DD'
            ),
            TRY_TO_DATE(
                CAST(fecha_sentencia AS VARCHAR),
                'DD/MM/YYYY'
            ),
            TRY_CAST(fecha_sentencia AS DATE)
        ) AS fecha_sentencia_parsed

    FROM deduplicado

    WHERE rn = 1

),

fechas_validadas AS (

    SELECT

        *,

        CASE
            WHEN fecha_denuncia_parsed IS NULL THEN NULL

            WHEN fecha_apertura_parsed IS NOT NULL
             AND fecha_apertura_parsed < fecha_denuncia_parsed
            THEN NULL

            ELSE fecha_apertura_parsed
        END AS fecha_apertura_validada

    FROM fechas_parseadas

),

normalizado AS (

    SELECT

        REGEXP_REPLACE(
            TRIM(UPPER(numero_causa)),
            '[^A-ZÁÉÍÓÚÑ0-9\\s]',
            ''
        ) AS numero_causa,

        fecha_denuncia_parsed AS fecha_denuncia,

        fecha_apertura_validada AS fecha_apertura_proceso,

        CASE
            WHEN fecha_sentencia_parsed IS NOT NULL
             AND fecha_apertura_validada IS NOT NULL
             AND fecha_sentencia_parsed < fecha_apertura_validada
            THEN NULL

            WHEN fecha_sentencia_parsed IS NOT NULL
             AND fecha_apertura_validada IS NULL
            THEN NULL

            ELSE fecha_sentencia_parsed
        END AS fecha_sentencia,

        REGEXP_REPLACE(
            TRIM(UPPER(numero_documento_imputado)),
            '[^A-ZÁÉÍÓÚÑ0-9\\s]',
            ''
        ) AS numero_documento_imputado,

        REGEXP_REPLACE(
            TRIM(
                UPPER(
                    CASE
                        WHEN tipo_denuncia IS NULL
                          OR TRIM(tipo_denuncia) = ''
                        THEN 'NO ESPECIFICADO'
                        ELSE tipo_denuncia
                    END
                )
            ),
            '[^A-ZÁÉÍÓÚÑ0-9\\s]',
            ''
        ) AS tipo_denuncia,

        REGEXP_REPLACE(
            TRIM(
                UPPER(
                    CASE
                        WHEN nombre_juzgado IS NULL
                          OR TRIM(nombre_juzgado) = ''
                        THEN 'NO ESPECIFICADO'
                        ELSE nombre_juzgado
                    END
                )
            ),
            '[^A-ZÁÉÍÓÚÑ0-9\\s]',
            ''
        ) AS nombre_juzgado,

        REGEXP_REPLACE(
            TRIM(
                UPPER(
                    CASE
                        WHEN estado_proceso IS NULL
                          OR TRIM(estado_proceso) = ''
                        THEN 'EN CURSO'

                        WHEN UPPER(TRIM(estado_proceso))
                            NOT IN (
                                'EN CURSO',
                                'SUSPENDIDO',
                                'RESUELTO',
                                'ARCHIVADO',
                                'APELACION'
                            )
                        THEN 'EN CURSO'

                        ELSE estado_proceso
                    END
                )
            ),
            '[^A-ZÁÉÍÓÚÑ\\s]',
            ''
        ) AS estado_proceso,

        REGEXP_REPLACE(
            TRIM(
                UPPER(
                    CASE
                        WHEN macrodistrito IS NULL
                          OR TRIM(macrodistrito) = ''
                        THEN 'NO ESPECIFICADO'
                        ELSE macrodistrito
                    END
                )
            ),
            '[^A-ZÁÉÍÓÚÑ0-9\\s]',
            ''
        ) AS macrodistrito,

        REGEXP_REPLACE(
            REGEXP_REPLACE(
                TRIM(UPPER(resumen_denuncia)),
                '\\s+',
                ' '
            ),
            '[^A-ZÁÉÍÓÚÑ0-9\\s]',
            ''
        ) AS resumen_denuncia,

        REGEXP_REPLACE(
            TRIM(UPPER(id_reporte_accidente_relacionado)),
            '[^A-ZÁÉÍÓÚÑ0-9\\s_-]',
            ''
        ) AS id_reporte_accidente_relacionado,

        CASE
            WHEN fecha_sentencia_parsed IS NOT NULL
             AND fecha_apertura_validada IS NOT NULL
             AND fecha_sentencia_parsed >= fecha_apertura_validada
            THEN TRUE
            ELSE FALSE
        END AS tiene_sentencia,

        CASE
            WHEN fecha_apertura_validada IS NOT NULL
            THEN TRUE
            ELSE FALSE
        END AS tiene_apertura

    FROM fechas_validadas

)

SELECT *
FROM normalizado

WHERE numero_causa IS NOT NULL