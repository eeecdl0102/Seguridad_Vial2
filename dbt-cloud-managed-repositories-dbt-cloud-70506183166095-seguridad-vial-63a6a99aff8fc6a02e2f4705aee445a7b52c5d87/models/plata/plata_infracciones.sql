-- models/plata/plata_infracciones.sql

WITH fuente_bruta AS (
    SELECT *
    FROM {{ source('la_paz_vial', 'INFRACCIONES') }}
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY numero_acta
            ORDER BY fecha_hora DESC
        ) AS rn
    FROM fuente_bruta
),

fechas_parseadas AS (
    SELECT *,
        COALESCE(
            -- Intentamos parsear diferentes formatos de texto a timestamp
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'YYYY-MM-DD HH24:MI:SS'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'YYYY-MM-DD HH24:MI'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'YYYY-MM-DD'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'DD/MM/YYYY HH24:MI:SS'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'DD/MM/YYYY'),
            -- Usamos CAST directo en lugar de TRY_CAST para evitar el error de compilación 
            -- cuando la columna original ya es de tipo TIMESTAMP_NTZ
            CAST(fecha_hora AS TIMESTAMP_NTZ)
        ) AS fecha_hora_parsed
    FROM deduplicado
    WHERE rn = 1
),

normalizado AS (
    SELECT
        numero_acta,
        fecha_hora_parsed AS fecha_hora,

        -- Fecha descompuesta
        YEAR(fecha_hora_parsed) AS anio,
        MONTH(fecha_hora_parsed) AS mes,
        DAY(fecha_hora_parsed) AS dia,
        HOUR(fecha_hora_parsed) AS hora,
        DAYOFWEEK(fecha_hora_parsed) AS dia_semana,

        -- Ubicación (todo en mayúsculas y limpiando caracteres especiales, conservando la Ñ)
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN macrodistrito IS NULL OR TRIM(macrodistrito) = '' THEN 'NO ESPECIFICADO'
                    ELSE macrodistrito 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS macrodistrito,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN zona_barrio IS NULL OR TRIM(zona_barrio) = '' THEN 'NO ESPECIFICADO'
                    ELSE zona_barrio 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS zona_barrio,

        REGEXP_REPLACE(REGEXP_REPLACE(TRIM(UPPER(direccion_exacta)), '\\s+', ' '), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS direccion_exacta,
        REGEXP_REPLACE(REGEXP_REPLACE(TRIM(UPPER(calle_principal)), '\\s+', ' '), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS calle_principal,
        REGEXP_REPLACE(REGEXP_REPLACE(TRIM(UPPER(calle_secundaria)), '\\s+', ' '), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS calle_secundaria,

        -- Coordenadas
        CASE WHEN latitud BETWEEN -90 AND 90 THEN ROUND(latitud, 6) ELSE NULL END AS latitud,
        CASE WHEN longitud BETWEEN -180 AND 180 THEN ROUND(longitud, 6) ELSE NULL END AS longitud,

        -- Vehículo y conductor (conservando letras, Ñ y números)
        REGEXP_REPLACE(TRIM(UPPER(placa)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS placa,
        REGEXP_REPLACE(TRIM(UPPER(numero_documento_conductor)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS numero_documento_conductor,

        -- Tipo y categoría de infracción
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN tipo_infraccion IS NULL OR TRIM(tipo_infraccion) = '' THEN 'NO ESPECIFICADO'
                    ELSE tipo_infraccion 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS tipo_infraccion,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN categoria_infraccion IS NULL OR TRIM(categoria_infraccion) = '' THEN 'NO ESPECIFICADO'
                    ELSE categoria_infraccion 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS categoria_infraccion,

        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN gravedad_infraccion IS NULL OR TRIM(gravedad_infraccion) = '' THEN 'LEVE'
                    WHEN UPPER(TRIM(gravedad_infraccion)) NOT IN ('LEVE', 'GRAVE') THEN 'LEVE'
                    ELSE gravedad_infraccion
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS gravedad_infraccion,

        -- Monto: validar positivo
        CASE 
            WHEN monto_multa IS NULL OR monto_multa < 0 THEN NULL
            ELSE ROUND(monto_multa, 2)
        END AS monto_multa,

        -- Oficial (se permiten números/guiones bajos convertidos por REGEXP o ajustados a códigos alfanuméricos)
        REGEXP_REPLACE(TRIM(UPPER(oficial_id)), '[^A-ZÁÉÍÓÚÑ0-9_\\s]', '') AS oficial_id,
        REGEXP_REPLACE(TRIM(UPPER(unidad_policial)), '[^A-ZÁÉÍÓÚÑ0-9\\s]', '') AS unidad_policial,

        -- Estado de la multa
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN estado_multa IS NULL OR TRIM(estado_multa) = '' THEN 'PENDIENTE'
                    ELSE estado_multa 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS estado_multa,

        -- Pagada (booleano)
        CASE 
            WHEN esta_pagada IS NULL THEN FALSE
            WHEN esta_pagada = TRUE THEN TRUE
            ELSE FALSE
        END AS esta_pagada,

        -- Link a accidente
        REGEXP_REPLACE(TRIM(UPPER(id_reporte_accidente_relacionado)), '[^A-ZÁÉÍÓÚÑ0-9\\s_-]', '') AS id_reporte_accidente_relacionado,

        -- Flags derivados (logística de pago)
        CASE WHEN HOUR(fecha_hora_parsed) BETWEEN 2 AND 4 THEN TRUE ELSE FALSE END AS es_hora_rara,
        CASE WHEN DAYOFWEEK(fecha_hora_parsed) IN (6, 0) THEN TRUE ELSE FALSE END AS es_fin_de_semana,

        -- Flag de posible fraude 
        CASE 
            WHEN UPPER(TRIM(oficial_id)) LIKE 'OFICIAL_FRAUDE_%' THEN TRUE
            ELSE FALSE
        END AS es_oficial_sospechoso,

        -- Flag de concentración 
        CASE 
            WHEN UPPER(TRIM(oficial_id)) LIKE 'OFICIAL_CONCENTRADO_%' THEN TRUE
            ELSE FALSE
        END AS es_oficial_concentrado

    FROM fechas_parseadas
)

SELECT *
FROM normalizado
WHERE fecha_hora IS NOT NULL
  AND numero_acta IS NOT NULL