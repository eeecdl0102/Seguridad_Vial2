-- models/plata/plata_seguros.sql
-- Limpieza de SEGUROS
-- Lee directo del source: SEGURIDAD_VIAL_DB.BRONCE.SEGUROS
-- Granularidad: 1 fila = 1 reclamo
-- Destino: SEGURIDAD_VIAL_DB.PLATA.plata_seguros

WITH fuente_bruta AS (
    SELECT *
    FROM {{ source('la_paz_vial', 'SEGUROS') }}
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY numero_reclamo
            ORDER BY fecha_reclamo DESC
        ) AS rn
    FROM fuente_bruta
),

fechas_parseadas AS (
    SELECT *,
        COALESCE(
            TRY_TO_TIMESTAMP(CAST(fecha_reclamo AS VARCHAR), 'YYYY-MM-DD HH24:MI:SS'),
            TRY_TO_TIMESTAMP(CAST(fecha_reclamo AS VARCHAR), 'YYYY-MM-DD'),
            TRY_CAST(fecha_reclamo AS TIMESTAMP_NTZ)
        ) AS fecha_reclamo_parsed
    FROM deduplicado
    WHERE rn = 1
),

normalizado AS (
    SELECT
        REGEXP_REPLACE(TRIM(UPPER(numero_reclamo)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS numero_reclamo,
        fecha_reclamo_parsed AS fecha_reclamo,

        REGEXP_REPLACE(TRIM(UPPER(placa)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS placa,
        REGEXP_REPLACE(TRIM(UPPER(numero_documento_asegurado)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS numero_documento_asegurado,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN nombre_compania IS NULL OR TRIM(nombre_compania) = '' THEN 'NO ESPECIFICADO'
                    ELSE nombre_compania 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS nombre_compania,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN tipo_poliza IS NULL OR TRIM(tipo_poliza) = '' THEN 'NO ESPECIFICADO'
                    ELSE tipo_poliza 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS tipo_poliza,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN tipo_reclamo IS NULL OR TRIM(tipo_reclamo) = '' THEN 'NO ESPECIFICADO'
                    ELSE tipo_reclamo 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS tipo_reclamo,

        -- Montos: validar positivos
        CASE WHEN monto_reclamado >= 0 THEN ROUND(monto_reclamado, 2) ELSE NULL END AS monto_reclamado,
        CASE WHEN monto_indemnizado >= 0 THEN ROUND(monto_indemnizado, 2) ELSE 0 END AS monto_indemnizado,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN estado_reclamo IS NULL OR TRIM(estado_reclamo) = '' THEN 'EN EVALUACION'
                    WHEN UPPER(TRIM(estado_reclamo)) NOT IN ('APROBADO', 'RECHAZADO', 'EN EVALUACION', 'PAGADO', 'ANULADO')
                    THEN 'EN EVALUACION'
                    ELSE estado_reclamo
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS estado_reclamo,

        REGEXP_REPLACE(TRIM(UPPER(id_reporte_accidente_relacionado)), '[^A-ZÁÉÍÓÚÑ0-9\\s_-]', '') AS id_reporte_accidente_relacionado,

        -- Flags
        CASE WHEN monto_indemnizado > 0 THEN TRUE ELSE FALSE END AS fue_indemnizado,
        CASE WHEN UPPER(TRIM(estado_reclamo)) IN ('PAGADO', 'APROBADO') THEN TRUE ELSE FALSE END AS fue_aprobado_o_pagado

    FROM fechas_parseadas
)

SELECT *
FROM normalizado
WHERE numero_reclamo IS NOT NULL