{% set rel = source('la_paz_vial', 'VEHICULOS') %}

WITH fuente_bruta AS (
    SELECT
        {{ pick_column(rel, ['PLACA']) }}                                         AS placa,
        {{ pick_column(rel, ['TIPO_VEHICULO', 'TIPO_VEH']) }}                     AS tipo_vehiculo,
        {{ pick_column(rel, ['MARCA']) }}                                         AS marca,
        {{ pick_column(rel, ['MODELO']) }}                                        AS modelo,
        {{ pick_column(rel, ['ANIO_FABRICACION', 'ANIO_FABRICAC']) }}             AS anio_fabricacion,
        {{ pick_column(rel, ['COLOR']) }}                                         AS color,
        {{ pick_column(rel, ['DOCUMENTO_PROPIETARIO', 'DOC_PROPIETARIO']) }}      AS documento_propietario,
        {{ pick_column(rel, ['_AIRBYTE_EXTRACTED_AT'], required=false) }}         AS extraido_en
    FROM {{ rel }}
),

placas_limpias AS (
    SELECT
        TRIM(UPPER(CAST(placa AS VARCHAR))) AS placa,
        tipo_vehiculo, marca, modelo, anio_fabricacion,
        color, documento_propietario, extraido_en
    FROM fuente_bruta
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY placa
            ORDER BY extraido_en DESC NULLS LAST
        ) AS rn
    FROM placas_limpias
),

anios_parseados AS (
    SELECT *,
        -- funciona si la columna es NUMBER o VARCHAR
        TRY_TO_NUMBER(CAST(anio_fabricacion AS VARCHAR)) AS anio_fab_parsed
    FROM deduplicado
    WHERE rn = 1
),

normalizado AS (
    SELECT
        placa,

        TRIM(UPPER(CASE WHEN tipo_vehiculo IS NULL OR TRIM(CAST(tipo_vehiculo AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(tipo_vehiculo AS VARCHAR) END)) AS tipo_vehiculo,

        TRIM(UPPER(CASE WHEN marca IS NULL OR TRIM(CAST(marca AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(marca AS VARCHAR) END)) AS marca,

        TRIM(UPPER(CASE WHEN modelo IS NULL OR TRIM(CAST(modelo AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(modelo AS VARCHAR) END)) AS modelo,

        CASE WHEN anio_fab_parsed BETWEEN 1900 AND YEAR(CURRENT_DATE())
             THEN anio_fab_parsed ELSE NULL END AS anio_fabricacion,

        CASE WHEN anio_fab_parsed BETWEEN 1900 AND YEAR(CURRENT_DATE())
             THEN YEAR(CURRENT_DATE()) - anio_fab_parsed ELSE NULL END AS antiguedad_anios,

        TRIM(UPPER(CASE WHEN color IS NULL OR TRIM(CAST(color AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(color AS VARCHAR) END)) AS color,

        TRIM(UPPER(CAST(documento_propietario AS VARCHAR))) AS documento_propietario
    FROM anios_parseados
)

SELECT *
FROM normalizado
WHERE placa IS NOT NULL
  AND placa != ''
  AND placa != 'SIN_PLACA'