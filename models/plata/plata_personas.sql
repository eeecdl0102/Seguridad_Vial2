{% set rel = source('la_paz_vial', 'PERSONAS') %}

WITH fuente_bruta AS (
    SELECT
        {{ pick_column(rel, ['NUMERO_DOCUMENTO', 'NUMERO_DOC']) }}                 AS numero_documento,
        {{ pick_column(rel, ['TIPO_DOCUMENTO', 'TIPO_DOC']) }}                     AS tipo_documento,
        {{ pick_column(rel, ['NOMBRES', 'NOMBRE']) }}                              AS nombres,
        {{ pick_column(rel, ['APELLIDOS', 'APELLIDO']) }}                          AS apellidos,
        {{ pick_column(rel, ['FECHA_NACIMIENTO', 'FECHA_NAC']) }}                  AS fecha_nacimiento,
        {{ pick_column(rel, ['EDAD_DECLARADA', 'EDAD_DECLARA']) }}                 AS edad_declarada,
        {{ pick_column(rel, ['GENERO']) }}                                         AS genero,
        {{ pick_column(rel, ['NUMERO_LICENCIA', 'NRO_LICENCIA']) }}                AS numero_licencia,
        {{ pick_column(rel, ['CATEGORIA_LICENCIA', 'CATEGORIA_LICENC']) }}         AS categoria_licencia,
        {{ pick_column(rel, ['TELEFONO']) }}                                       AS telefono,
        {{ pick_column(rel, ['PERFIL_RIESGO']) }}                                  AS perfil_riesgo,
        {{ pick_column(rel, ['_AIRBYTE_EXTRACTED_AT'], required=false) }}          AS extraido_en
    FROM {{ rel }}
),

documentos_limpios AS (
    SELECT
        TRIM(UPPER(CAST(numero_documento AS VARCHAR))) AS numero_documento,
        tipo_documento, nombres, apellidos, fecha_nacimiento, edad_declarada,
        genero, numero_licencia, categoria_licencia, telefono, perfil_riesgo, extraido_en
    FROM fuente_bruta
),

deduplicado AS (
    SELECT d.*,
        ROW_NUMBER() OVER (
            PARTITION BY d.numero_documento
            ORDER BY d.extraido_en DESC NULLS LAST
        ) AS rn
    FROM documentos_limpios d
),

fechas_parseadas AS (
    SELECT d.*,
        COALESCE(
            TRY_TO_DATE(CAST(d.fecha_nacimiento AS VARCHAR), 'YYYY-MM-DD'),
            TRY_TO_DATE(CAST(d.fecha_nacimiento AS VARCHAR), 'DD/MM/YYYY'),
            TRY_TO_DATE(CAST(d.fecha_nacimiento AS VARCHAR))
        ) AS fecha_nacimiento_parsed,
        TRY_TO_NUMBER(CAST(d.edad_declarada AS VARCHAR)) AS edad_declarada_parsed
    FROM deduplicado d
    WHERE d.rn = 1
),

normalizado AS (
    SELECT
        numero_documento,

        TRIM(UPPER(CASE WHEN tipo_documento IS NULL OR TRIM(CAST(tipo_documento AS VARCHAR)) = ''
                        THEN 'CI' ELSE CAST(tipo_documento AS VARCHAR) END)) AS tipo_documento,

        TRIM(UPPER(CASE WHEN nombres IS NULL OR TRIM(CAST(nombres AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(nombres AS VARCHAR) END)) AS nombres,

        TRIM(UPPER(CASE WHEN apellidos IS NULL OR TRIM(CAST(apellidos AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(apellidos AS VARCHAR) END)) AS apellidos,

        fecha_nacimiento_parsed AS fecha_nacimiento,

        CASE WHEN edad_declarada_parsed < 0 OR edad_declarada_parsed > 120
             THEN NULL ELSE edad_declarada_parsed END AS edad_declarada,

        TRIM(UPPER(CASE WHEN genero IS NULL OR TRIM(CAST(genero AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(genero AS VARCHAR) END)) AS genero,

        CASE WHEN numero_licencia IS NULL
                  OR TRIM(CAST(numero_licencia AS VARCHAR)) = ''
                  OR UPPER(TRIM(CAST(numero_licencia AS VARCHAR))) = 'SIN LICENCIA'
             THEN NULL
             ELSE TRIM(UPPER(CAST(numero_licencia AS VARCHAR))) END AS numero_licencia,

        TRIM(UPPER(CASE WHEN categoria_licencia IS NULL OR TRIM(CAST(categoria_licencia AS VARCHAR)) = ''
                        THEN 'SIN LICENCIA' ELSE CAST(categoria_licencia AS VARCHAR) END)) AS categoria_licencia,

        CASE WHEN telefono IS NULL OR TRIM(CAST(telefono AS VARCHAR)) = ''
             THEN NULL ELSE TRIM(CAST(telefono AS VARCHAR)) END AS telefono,

        CASE WHEN perfil_riesgo IS NULL
                  OR UPPER(TRIM(CAST(perfil_riesgo AS VARCHAR))) NOT IN ('ALTO', 'MODERADO', 'BAJO')
             THEN 'BAJO'
             ELSE UPPER(TRIM(CAST(perfil_riesgo AS VARCHAR))) END AS perfil_riesgo,

        CASE WHEN fecha_nacimiento_parsed IS NULL THEN NULL
             ELSE DATEDIFF(YEAR, fecha_nacimiento_parsed, CURRENT_DATE())
                  - CASE WHEN DATE_FROM_PARTS(YEAR(CURRENT_DATE()),
                                              MONTH(fecha_nacimiento_parsed),
                                              DAY(fecha_nacimiento_parsed)) > CURRENT_DATE()
                         THEN 1 ELSE 0 END
        END AS edad_calculada
    FROM fechas_parseadas
),

con_flags AS (
    SELECT
        *,
        COALESCE(edad_calculada < 18, FALSE)                          AS es_menor_edad,
        COALESCE(ABS(edad_declarada - edad_calculada) > 1, FALSE)     AS edad_inconsistente,
        COALESCE((numero_licencia IS NOT NULL AND categoria_licencia = 'SIN LICENCIA')
              OR (numero_licencia IS NULL AND categoria_licencia != 'SIN LICENCIA'), FALSE) AS licencia_inconsistente
    FROM normalizado
)

SELECT *
FROM con_flags
WHERE numero_documento IS NOT NULL
  AND numero_documento != ''
  AND numero_documento != 'SIN_DOCUMENTO'