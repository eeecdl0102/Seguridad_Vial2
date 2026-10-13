-- models/plata/plata_depositos.sql

WITH fuente_bruta AS (
    SELECT *
    FROM {{ source('la_paz_vial', 'DEPOSITOS_VEHICULOS') }}
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY numero_registro
            ORDER BY fecha_ingreso DESC
        ) AS rn
    FROM fuente_bruta
),

fechas_parseadas AS (
    SELECT *,
        COALESCE(
            TRY_TO_TIMESTAMP(CAST(fecha_ingreso AS VARCHAR), 'YYYY-MM-DD HH24:MI:SS'),
            TRY_TO_TIMESTAMP(CAST(fecha_ingreso AS VARCHAR), 'YYYY-MM-DD'),
            TRY_CAST(fecha_ingreso AS TIMESTAMP_NTZ)
        ) AS fecha_ingreso_parsed,
        COALESCE(
            TRY_TO_DATE(CAST(fecha_salida AS VARCHAR), 'YYYY-MM-DD'),
            TRY_TO_DATE(CAST(fecha_salida AS VARCHAR), 'DD/MM/YYYY'),
            TRY_CAST(fecha_salida AS DATE)
        ) AS fecha_salida_parsed
    FROM deduplicado
    WHERE rn = 1
),

normalizado AS (
    SELECT
        numero_registro,
        fecha_ingreso_parsed AS fecha_ingreso,
        fecha_salida_parsed AS fecha_salida,

        -- Validar coherencia: salida no puede ser antes de ingreso
        CASE 
            WHEN fecha_salida_parsed < DATE(fecha_ingreso_parsed) THEN NULL
            ELSE fecha_salida_parsed 
        END AS fecha_salida_validada,

        -- Aplicando REGEXP_REPLACE para conservar solo letras (A-Z, Ñ, tildes) y espacios
        REGEXP_REPLACE(TRIM(UPPER(placa)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS placa, -- Nota: Si la placa incluye números, deja [^A-ZÁÉÍÓÚÑ0-9\\s]. Si solo quieres letras y Ñ: [^A-ZÁÉÍÓÚÑ\\s]

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN nombre_lugar_deposito IS NULL OR TRIM(nombre_lugar_deposito) = '' THEN 'NO ESPECIFICADO'
                    ELSE nombre_lugar_deposito 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS nombre_lugar_deposito,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN macrodistrito_deposito IS NULL OR TRIM(macrodistrito_deposito) = '' THEN 'NO ESPECIFICADO'
                    ELSE macrodistrito_deposito 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS macrodistrito_deposito,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN tipo_administracion IS NULL OR TRIM(tipo_administracion) = '' THEN 'NO ESPECIFICADO'
                    ELSE tipo_administracion 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS tipo_administracion,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN motivo_deposito IS NULL OR TRIM(motivo_deposito) = '' THEN 'NO ESPECIFICADO'
                    ELSE motivo_deposito 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS motivo_deposito,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN estado_vehiculo_deposito IS NULL OR TRIM(estado_vehiculo_deposito) = '' THEN 'INTEGRO'
                    ELSE estado_vehiculo_deposito 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS estado_vehiculo_deposito,

        -- Dias de estadia: validar
        CASE 
            WHEN dias_estadia_reportados < 0 THEN NULL
            WHEN dias_estadia_reportados > 365 THEN NULL
            ELSE dias_estadia_reportados
        END AS dias_estadia_reportados,

        -- Costo: validar
        CASE 
            WHEN costo_almacenaje < 0 THEN NULL
            ELSE ROUND(costo_almacenaje, 2)
        END AS costo_almacenaje,

        REGEXP_REPLACE(TRIM(UPPER(id_reporte_accidente_relacionado)), '[^A-ZÁÉÍÓÚÑ\\s_-]', '') AS id_reporte_accidente_relacionado,

        -- Calcular dias reales de estadia 
        CASE 
            WHEN fecha_salida_validada IS NOT NULL 
            THEN DATEDIFF(day, DATE(fecha_ingreso_parsed), fecha_salida_validada)
            ELSE NULL
        END AS dias_estadia_calculados,

        -- Flag
        CASE WHEN fecha_salida_validada IS NOT NULL THEN TRUE ELSE FALSE END AS vehiculo_retirado

    FROM fechas_parseadas
)

SELECT *
FROM normalizado
WHERE numero_registro IS NOT NULL