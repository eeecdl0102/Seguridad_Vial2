{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'hechos']
) }}

-- FIX: "personas" ahora deduplica (QUALIFY) antes del JOIN, evitando que un
-- mismo documento con varias filas en dim_persona (perfiles distintos por
-- accidente) multiplique la fila de la victima.

WITH victimas AS (
    SELECT
        id_reporte_accidente,
        numero_documento_victima,
        gravedad_lesion
    FROM {{ ref('plata_victimas') }}
    WHERE id_reporte_accidente IS NOT NULL
      AND TRIM(id_reporte_accidente) <> ''
      AND numero_documento_victima IS NOT NULL
      AND TRIM(numero_documento_victima) <> ''
),

accidentes AS (
    SELECT codigo_informe_policial, fecha_key, hora_key, ubicacion_key
    FROM {{ ref('hecho_accidente') }}
),

-- FIX: dedupe por documento
personas AS (
    SELECT
        persona_key,
        REGEXP_REPLACE(UPPER(TRIM(numero_documento)), '[^A-Z0-9]', '') AS doc_norm
    FROM {{ ref('dim_persona') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_REPLACE(UPPER(TRIM(numero_documento)), '[^A-Z0-9]', '')
        ORDER BY persona_key
    ) = 1
)

SELECT
    ROW_NUMBER() OVER (ORDER BY v.id_reporte_accidente, v.numero_documento_victima) AS victima_key,

    v.id_reporte_accidente AS codigo_informe_policial,
    COALESCE(a.fecha_key, 0)     AS fecha_key,
    COALESCE(a.hora_key, 0)      AS hora_key,
    COALESCE(TO_VARCHAR(a.ubicacion_key), '0') AS ubicacion_key,
    COALESCE(TO_VARCHAR(p.persona_key), '0')   AS persona_key,

    CASE WHEN v.gravedad_lesion IN ('LEVE', 'MODERADA', 'MODERADO', 'GRAVE', 'MORTAL')
         THEN 1 ELSE 0 END AS es_herido,
    CASE WHEN v.gravedad_lesion = 'MORTAL' THEN 1 ELSE 0 END AS es_fallecido,
    1 AS cantidad_victimas

FROM victimas v

LEFT JOIN accidentes a
    ON v.id_reporte_accidente = a.codigo_informe_policial

LEFT JOIN personas p
    ON REGEXP_REPLACE(UPPER(TRIM(v.numero_documento_victima)), '[^A-Z0-9]', '') = p.doc_norm