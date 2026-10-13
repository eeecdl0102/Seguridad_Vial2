{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'hechos']
) }}

-- FIX 1: TRY_TO_DECIMAL(monto) sin escala trunca a NUMBER(38,0) -> perdia los
--        centavos de TODOS los montos. Se agrega precision/escala explicita.
-- FIX 2: "personas" y "vehiculos" ahora deduplican (QUALIFY) antes del JOIN,
--        evitando que un mismo documento/placa con varias filas en la
--        dimension (dim_persona por perfil, dim_vehiculo por
--        direccion_desplazamiento) duplique reclamos de seguro.

WITH seguros AS (
    SELECT
        numero_reclamo,
        fecha_reclamo,
        placa,
        numero_documento_asegurado,
        nombre_compania,
        tipo_poliza,
        monto_reclamado,
        monto_indemnizado,
        estado_reclamo,
        id_reporte_accidente_relacionado
    FROM {{ ref('plata_seguros') }}
    WHERE numero_reclamo IS NOT NULL
      AND TRIM(numero_reclamo) <> ''
),

fechas AS (
    SELECT fecha_key, fecha_completa
    FROM {{ ref('dim_fecha') }}
),

-- FIX 2a
personas AS (
    SELECT
        persona_key,
        REGEXP_REPLACE(UPPER(TRIM(numero_documento)), '[^A-Z0-9]', '') AS doc_norm
    FROM {{ ref('dim_persona') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_REPLACE(UPPER(TRIM(numero_documento)), '[^A-Z0-9]', '')
        ORDER BY persona_key
    ) = 1
),

-- FIX 2b: dim_vehiculo tiene 1 fila por (placa, direccion_desplazamiento);
-- aqui solo necesitamos 1 vehiculo_key por placa, sin importar esa direccion.
vehiculos AS (
    SELECT
        vehiculo_key,
        UPPER(TRIM(REPLACE(placa, '-', ''))) AS placa
    FROM {{ ref('dim_vehiculo') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(REPLACE(placa, '-', '')))
        ORDER BY vehiculo_key
    ) = 1
),

aseguradoras AS (
    SELECT
        aseguradora_key,
        UPPER(TRIM(nombre_aseguradora)) AS nombre_aseguradora,
        UPPER(TRIM(tipo_seguro))        AS tipo_seguro
    FROM {{ ref('dim_aseguradora') }}
)

SELECT
    ROW_NUMBER() OVER (ORDER BY s.numero_reclamo) AS seguro_key,

    NULLIF(TRIM(s.id_reporte_accidente_relacionado), '') AS codigo_informe_policial,
    COALESCE(f.fecha_key, 0) AS fecha_reclamo_key,
    COALESCE(TO_VARCHAR(p.persona_key), '0') AS persona_key,
    COALESCE(TO_VARCHAR(v.vehiculo_key), '0') AS vehiculo_key,
    COALESCE(a.aseguradora_key, 0) AS aseguradora_key,

    -- FIX 1: precision y escala explicitas (12,2) para no perder centavos
    COALESCE(TRY_TO_DECIMAL(TO_VARCHAR(s.monto_reclamado), 12, 2), 0)   AS monto_reclamado,
    COALESCE(TRY_TO_DECIMAL(TO_VARCHAR(s.monto_indemnizado), 12, 2), 0) AS monto_pagado,

    UPPER(TRIM(COALESCE(s.estado_reclamo, 'NO ESPECIFICADO'))) AS estado_reclamo,
    1 AS cantidad_reclamos

FROM seguros s

LEFT JOIN fechas f
    ON CAST(s.fecha_reclamo AS DATE) = f.fecha_completa

LEFT JOIN personas p
    ON REGEXP_REPLACE(UPPER(TRIM(s.numero_documento_asegurado)), '[^A-Z0-9]', '') = p.doc_norm

LEFT JOIN vehiculos v
    ON UPPER(TRIM(REPLACE(s.placa, '-', ''))) = v.placa

LEFT JOIN aseguradoras a
    ON UPPER(TRIM(s.nombre_compania)) = a.nombre_aseguradora
   AND CASE WHEN UPPER(TRIM(s.tipo_poliza)) = 'SOAT' THEN 'SOAT' ELSE 'PRIVADO' END = a.tipo_seguro