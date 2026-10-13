-- models/plata/plata_vehiculos_maestro.sql
-- Limpieza de VEHICULOS (maestro)
-- Lee directo del source: SEGURIDAD_VIAL_DB.BRONCE.VEHICULOS
-- Granularidad: 1 fila = 1 vehiculo
-- Destino: SEGURIDAD_VIAL_DB.PLATA.plata_vehiculos_maestro

WITH fuente_bruta AS (
    SELECT 
        PLACA AS placa,
        TIPO_VEHICULO AS tipo_vehiculo,
        MARCA AS marca,
        MODELO AS modelo,
        -- Mapeamos con el nombre exacto que viene en la tabla Bronce
        ANIO_FABRICAC AS anio_fabricacion,
        COLOR AS color,
        DOCUMENTO_PROPIETARIO AS documento_propietario
    FROM {{ source('la_paz_vial', 'VEHICULOS') }}
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY placa
            ORDER BY 1
        ) AS rn
    FROM fuente_bruta
),

-- Paso intermedio para asegurar que el año de fabricación sea numérico
anios_parseados AS (
    SELECT *,
        COALESCE(
            TRY_CAST(anio_fabricacion AS INTEGER),
            NULL
        ) AS anio_fab_parsed
    FROM deduplicado
    WHERE rn = 1
),

normalizado AS (
    SELECT
        TRIM(UPPER(placa)) AS placa,

        TRIM(UPPER(
            CASE 
                WHEN tipo_vehiculo IS NULL OR TRIM(tipo_vehiculo) = '' THEN 'NO ESPECIFICADO'
                ELSE tipo_vehiculo 
            END
        )) AS tipo_vehiculo,

        TRIM(UPPER(
            CASE 
                WHEN marca IS NULL OR TRIM(marca) = '' THEN 'NO ESPECIFICADO'
                ELSE marca 
            END
        )) AS marca,

        TRIM(UPPER(
            CASE 
                WHEN modelo IS NULL OR TRIM(modelo) = '' THEN 'NO ESPECIFICADO'
                ELSE modelo 
            END
        )) AS modelo,

        -- Año de fabricación (validando rango)
        CASE 
            WHEN anio_fab_parsed < 1900 OR anio_fab_parsed > 2026 THEN NULL
            ELSE anio_fab_parsed
        END AS anio_fabricacion,

        -- Antigüedad calculada usando el campo parseado
        CASE 
            WHEN anio_fab_parsed BETWEEN 1900 AND 2026 
            THEN 2026 - anio_fab_parsed 
            ELSE NULL 
        END AS antiguedad_anios,

        TRIM(UPPER(
            CASE 
                WHEN color IS NULL OR TRIM(color) = '' THEN 'NO ESPECIFICADO'
                ELSE color 
            END
        )) AS color,

        TRIM(UPPER(documento_propietario)) AS documento_propietario

    FROM anios_parseados
)

SELECT *
FROM normalizado
WHERE placa IS NOT NULL
  AND placa != 'SIN_PLACA'