-- models/plata/plata_llamadas.sql
-- Lee directo del source: SEGURIDAD_VIAL_DB.BRONCE.LLAMADAS_EMERGENCIA
-- Granularidad: 1 fila = 1 llamada
-- Destino: SEGURIDAD_VIAL_DB.PLATA.plata_llamadas

WITH fuente_bruta AS (
    SELECT *
    FROM {{ source('la_paz_vial', 'LLAMADAS_EMERGENCIA') }}
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY id_llamada
            ORDER BY fecha_hora_llamada DESC
        ) AS rn
    FROM fuente_bruta
),

fechas_parseadas AS (
    SELECT *,
        COALESCE(
            TRY_TO_TIMESTAMP(CAST(fecha_hora_llamada AS VARCHAR), 'YYYY-MM-DD HH24:MI:SS'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora_llamada AS VARCHAR), 'YYYY-MM-DD HH24:MI'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora_llamada AS VARCHAR), 'YYYY-MM-DD'),
            TRY_CAST(fecha_hora_llamada AS TIMESTAMP_NTZ)
        ) AS fecha_hora_llamada_parsed
    FROM deduplicado
    WHERE rn = 1
),

normalizado AS (
    SELECT
        REGEXP_REPLACE(TRIM(UPPER(id_llamada)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS id_llamada,
        fecha_hora_llamada_parsed AS fecha_hora_llamada,

        -- Fecha descompuesta
        YEAR(fecha_hora_llamada_parsed) AS anio,
        MONTH(fecha_hora_llamada_parsed) AS mes,
        DAY(fecha_hora_llamada_parsed) AS dia,
        HOUR(fecha_hora_llamada_parsed) AS hora,
        DAYOFWEEK(fecha_hora_llamada_parsed) AS dia_semana,

        -- Duracion: validar
        CASE 
            WHEN duracion_segundos < 0 THEN NULL
            WHEN duracion_segundos > 3600 THEN NULL
            ELSE duracion_segundos
        END AS duracion_segundos,

        -- Transcripcion: limpiar espacios, caracteres especiales y llevar a mayusculas
        REGEXP_REPLACE(REGEXP_REPLACE(TRIM(UPPER(transcripcion)), '\\s+', ' '), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS transcripcion,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN categoria_referencia IS NULL OR TRIM(categoria_referencia) = '' THEN 'NO ESPECIFICADO'
                    ELSE categoria_referencia 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS categoria_referencia,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN urgencia_referencia IS NULL OR TRIM(urgencia_referencia) = '' THEN 'NO ESPECIFICADO'
                    ELSE urgencia_referencia 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS urgencia_referencia,

        REGEXP_REPLACE(REGEXP_REPLACE(TRIM(UPPER(referencia_verbal_lugar)), '\\s+', ' '), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS referencia_verbal_lugar,

        -- Validar link a accidente 
        CASE 
            WHEN REGEXP_REPLACE(TRIM(UPPER(id_reporte_accidente_relacionado)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') LIKE 'PTA-%' 
            THEN REGEXP_REPLACE(TRIM(UPPER(id_reporte_accidente_relacionado)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '')
            ELSE NULL
        END AS id_reporte_accidente_relacionado,

        -- Flags derivados
        CASE WHEN UPPER(TRIM(urgencia_referencia)) = 'URGENTE' THEN TRUE ELSE FALSE END AS es_urgente,
        CASE WHEN UPPER(TRIM(categoria_referencia)) = 'FALSA ALARMA' THEN TRUE ELSE FALSE END AS es_falsa_alarma,
        CASE WHEN id_reporte_accidente_relacionado IS NOT NULL THEN TRUE ELSE FALSE END AS tiene_link_accidente

    FROM fechas_parseadas
)

SELECT *
FROM normalizado
WHERE fecha_hora_llamada IS NOT NULL