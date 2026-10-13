-- models/plata/plata_personas.sql
-- Lee directamente del source: SEGURIDAD_VIAL_DB.BRONCE.PERSONAS (Estructura Airbyte)
-- Granularidad: 1 fila = 1 persona del pool
-- Destino: SEGURIDAD_VIAL_DB.PLATA.PLATA_PERSONAS

WITH fuente_bruta AS (

    SELECT 
        NUMERO_DOC AS numero_documento,
        TIPO_DOCUMENTO AS tipo_documento,
        NOMBRES AS nombres,
        APELLIDOS AS apellidos,
        FECHA_NACIMIENTO AS fecha_nacimiento,
        EDAD_DECLARA AS edad_declarada,
        GENERO AS genero,
        NUMERO_LICENCIA AS numero_licencia,
        CATEGORIA_LICENCIA AS categoria_licencia,
        TELEFONO AS telefono,
        PERFIL_RIESGO AS perfil_riesgo
    FROM {{ source('la_paz_vial', 'PERSONAS') }}

),

deduplicado AS (

    SELECT
        f.*,
        ROW_NUMBER() OVER (
            PARTITION BY f.numero_documento
            ORDER BY f.numero_documento
        ) AS rn
    FROM fuente_bruta f

),

fechas_parseadas AS (

    SELECT
        d.*,
        COALESCE(
            TRY_TO_DATE(
                CAST(d.fecha_nacimiento AS VARCHAR),
                'YYYY-MM-DD'
            ),
            TRY_TO_DATE(
                CAST(d.fecha_nacimiento AS VARCHAR),
                'DD/MM/YYYY'
            ),
            TRY_TO_DATE(
                CAST(d.fecha_nacimiento AS VARCHAR)
            )
        ) AS fecha_nacimiento_parsed

    FROM deduplicado d
    WHERE d.rn = 1

),

normalizado AS (

    SELECT

        /* =========================================================
           IDENTIFICACIÓN
           ========================================================= */

        TRIM(
            UPPER(
                CAST(numero_documento AS VARCHAR)
            )
        ) AS numero_documento,

        TRIM(
            UPPER(
                CASE
                    WHEN tipo_documento IS NULL
                         OR TRIM(CAST(tipo_documento AS VARCHAR)) = ''
                    THEN 'CI'
                    ELSE CAST(tipo_documento AS VARCHAR)
                END
            )
        ) AS tipo_documento,


        /* =========================================================
           DATOS PERSONALES (EN MAYÚSCULAS CONSERVANDO LA 'Ñ')
           ========================================================= */

        TRIM(
            UPPER(
                CASE
                    WHEN nombres IS NULL
                         OR TRIM(CAST(nombres AS VARCHAR)) = ''
                    THEN 'NO ESPECIFICADO'
                    ELSE CAST(nombres AS VARCHAR)
                END
            )
        ) AS nombres,

        TRIM(
            UPPER(
                CASE
                    WHEN apellidos IS NULL
                         OR TRIM(CAST(apellidos AS VARCHAR)) = ''
                    THEN 'NO ESPECIFICADO'
                    ELSE CAST(apellidos AS VARCHAR)
                END
            )
        ) AS apellidos,

        fecha_nacimiento_parsed AS fecha_nacimiento,


        /* =========================================================
           EDAD DECLARADA
           ========================================================= */

        CASE
            WHEN edad_declarada IS NULL THEN NULL

            WHEN TRY_TO_NUMBER(
                CAST(edad_declarada AS VARCHAR)
            ) < 0 THEN NULL

            WHEN TRY_TO_NUMBER(
                CAST(edad_declarada AS VARCHAR)
            ) > 120 THEN NULL

            ELSE TRY_TO_NUMBER(
                CAST(edad_declarada AS VARCHAR)
            )
        END AS edad_declarada,


        /* =========================================================
           GÉNERO
           ========================================================= */

        TRIM(
            UPPER(
                CASE
                    WHEN genero IS NULL
                         OR TRIM(CAST(genero AS VARCHAR)) = ''
                    THEN 'NO ESPECIFICADO'
                    ELSE CAST(genero AS VARCHAR)
                END
            )
        ) AS genero,


        /* =========================================================
           LICENCIA
           ========================================================= */

        CASE
            WHEN numero_licencia IS NULL
                 OR TRIM(CAST(numero_licencia AS VARCHAR)) = ''
            THEN NULL
            ELSE TRIM(
                UPPER(
                    CAST(numero_licencia AS VARCHAR)
                )
            )
        END AS numero_licencia,

        TRIM(
            UPPER(
                CASE
                    WHEN categoria_licencia IS NULL
                         OR TRIM(CAST(categoria_licencia AS VARCHAR)) = ''
                    THEN 'SIN LICENCIA'
                    ELSE CAST(categoria_licencia AS VARCHAR)
                END
            )
        ) AS categoria_licencia,


        /* =========================================================
           CONTACTO
           ========================================================= */

        CASE
            WHEN telefono IS NULL
                 OR TRIM(CAST(telefono AS VARCHAR)) = ''
            THEN NULL
            ELSE TRIM(
                CAST(telefono AS VARCHAR)
            )
        END AS telefono,


        /* =========================================================
           PERFIL DE RIESGO
           ========================================================= */

        TRIM(
            UPPER(
                CASE
                    WHEN perfil_riesgo IS NULL
                         OR TRIM(CAST(perfil_riesgo AS VARCHAR)) = ''
                    THEN 'BAJO'

                    WHEN UPPER(
                        TRIM(
                            CAST(perfil_riesgo AS VARCHAR)
                        )
                    ) NOT IN (
                        'ALTO',
                        'MODERADO',
                        'BAJO'
                    )
                    THEN 'BAJO'

                    ELSE CAST(perfil_riesgo AS VARCHAR)
                END
            )
        ) AS perfil_riesgo,


        /* =========================================================
           EDAD CALCULADA
           ========================================================= */

        CASE

            WHEN fecha_nacimiento_parsed IS NULL
            THEN NULL

            ELSE
                DATEDIFF(
                    YEAR,
                    fecha_nacimiento_parsed,
                    CURRENT_DATE()
                )

                -

                CASE
                    WHEN DATE_FROM_PARTS(
                        YEAR(CURRENT_DATE()),
                        MONTH(fecha_nacimiento_parsed),
                        DAY(fecha_nacimiento_parsed)
                    ) > CURRENT_DATE()
                    THEN 1
                    ELSE 0
                END

        END AS edad_calculada

    FROM fechas_parseadas

)


/* =============================================================
   RESULTADO FINAL
   ============================================================= */

SELECT
    numero_documento,
    tipo_documento,
    nombres,
    apellidos,
    fecha_nacimiento,
    edad_declarada,
    edad_calculada,
    genero,
    numero_licencia,
    categoria_licencia,
    telefono,
    perfil_riesgo

FROM normalizado

WHERE numero_documento IS NOT NULL
  AND TRIM(numero_documento) != ''
  AND UPPER(TRIM(numero_documento)) != 'SIN_DOCUMENTO'