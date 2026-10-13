-- models/plata/plata_accidentes.sql

WITH fuente_bruta AS (
    SELECT *
    FROM {{ source('la_paz_vial', 'ACCIDENTES') }}
),

-- 1. DEDUPLICACION: quedarse con 1 fila por id_reporte_accidente
deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY id_reporte_accidente
            ORDER BY fecha_hora DESC
        ) AS rn
    FROM fuente_bruta
),

-- 2. PARSEO DE FECHAS (multiformato por si acaso y manejo seguro de tipos)
fechas_parseadas AS (
    SELECT *,
        COALESCE(
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'YYYY-MM-DD HH24:MI:SS'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'YYYY-MM-DD HH24:MI'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'YYYY-MM-DD'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'DD/MM/YYYY HH24:MI:SS'),
            TRY_TO_TIMESTAMP(CAST(fecha_hora AS VARCHAR), 'DD/MM/YYYY'),
            TRY_CAST(fecha_hora AS TIMESTAMP_NTZ)
        ) AS fecha_hora_parsed
    FROM deduplicado
    WHERE rn = 1
),

-- 3. NORMALIZACION DE TEXTOS Y CATEGORIAS (todo en mayusculas conservando la Ñ)
normalizado AS (
    SELECT
        id_reporte_accidente,
        fecha_hora_parsed AS fecha_hora,

        -- Fecha descompuesta (util para joins y agregaciones)
        YEAR(fecha_hora_parsed) AS anio,
        MONTH(fecha_hora_parsed) AS mes,
        DAY(fecha_hora_parsed) AS dia,
        HOUR(fecha_hora_parsed) AS hora,
        DAYOFWEEK(fecha_hora_parsed) AS dia_semana,

        -- Macrodistrito: estandarizar a mayusculas (respetando Ñ)
        TRIM(UPPER(
            CASE 
                WHEN macrodistrito IS NULL OR TRIM(macrodistrito) = '' THEN 'NO ESPECIFICADO'
                ELSE macrodistrito 
            END
        )) AS macrodistrito,

        -- Barrio: estandarizar a mayusculas (respetando Ñ)
        TRIM(UPPER(
            CASE 
                WHEN zona_barrio IS NULL OR TRIM(zona_barrio) = '' THEN 'NO ESPECIFICADO'
                ELSE zona_barrio 
            END
        )) AS zona_barrio,

        -- Direccion: limpiar espacios y llevar a mayusculas (respetando Ñ)
        REGEXP_REPLACE(TRIM(UPPER(direccion_exacta)), '\\s+', ' ') AS direccion_exacta,
        REGEXP_REPLACE(TRIM(UPPER(calle_principal)), '\\s+', ' ') AS calle_principal,
        REGEXP_REPLACE(TRIM(UPPER(calle_secundaria)), '\\s+', ' ') AS calle_secundaria,

        -- Coordenadas: validar rangos geograficos
        CASE 
            WHEN latitud BETWEEN -90 AND 90 THEN ROUND(latitud, 6)
            ELSE NULL 
        END AS latitud,
        CASE 
            WHEN longitud BETWEEN -180 AND 180 THEN ROUND(longitud, 6)
            ELSE NULL 
        END AS longitud,

        -- Tipo de accidente
        TRIM(UPPER(
            CASE 
                WHEN tipo_accidente IS NULL OR TRIM(tipo_accidente) = '' THEN 'NO ESPECIFICADO'
                ELSE tipo_accidente 
            END
        )) AS tipo_accidente,

        -- Causa del accidente 
        TRIM(UPPER(
            CASE 
                WHEN causa_accidente IS NULL OR TRIM(causa_accidente) = '' THEN 'NO ESPECIFICADO'
                ELSE causa_accidente 
            END
        )) AS causa_accidente,

        -- Clima
        TRIM(UPPER(
            CASE 
                WHEN clima IS NULL OR TRIM(clima) = '' THEN 'NO ESPECIFICADO'
                ELSE clima 
            END
        )) AS clima,

        -- Gravedad: validar dominio
        TRIM(UPPER(
            CASE 
                WHEN gravedad_accidente_reportada IS NULL 
                     OR TRIM(gravedad_accidente_reportada) = '' 
                THEN 'LEVE'
                WHEN UPPER(TRIM(gravedad_accidente_reportada)) NOT IN (
                    'LEVE', 'MODERADO', 'GRAVE', 'MORTAL'
                ) THEN 'LEVE'
                ELSE gravedad_accidente_reportada
            END
        )) AS gravedad_accidente,

        -- Unidad policial (en mayusculas)
        TRIM(UPPER(
            CASE 
                WHEN unidad_policial IS NULL OR TRIM(unidad_policial) = '' THEN 'NO ESPECIFICADO'
                ELSE unidad_policial 
            END
        )) AS unidad_policial,

        TRIM(UPPER(
            CASE 
                WHEN unidad_policial_macrodistrito IS NULL OR TRIM(unidad_policial_macrodistrito) = '' THEN 'NO ESPECIFICADO'
                ELSE unidad_policial_macrodistrito 
            END
        )) AS unidad_policial_macrodistrito,

        -- Cantidades: validar positivas
        CASE 
            WHEN cantidad_vehiculos_reportados < 0 THEN NULL
            WHEN cantidad_vehiculos_reportados > 50 THEN NULL
            ELSE cantidad_vehiculos_reportados
        END AS cantidad_vehiculos,

        CASE 
            WHEN cantidad_personas_reportados < 0 THEN NULL
            WHEN cantidad_personas_reportados > 100 THEN NULL
            ELSE cantidad_personas_reportados
        END AS cantidad_personas,

        -- Narrativa: limpiar espacios y llevar a mayusculas (respetando Ñ)
        REGEXP_REPLACE(TRIM(UPPER(narrativa_hechos)), '\\s+', ' ') AS narrativa_hechos,

        -- Flags derivados para facilitar analisis
        CASE WHEN HOUR(fecha_hora_parsed) BETWEEN 22 AND 23 
                  OR HOUR(fecha_hora_parsed) BETWEEN 0 AND 5 
             THEN TRUE ELSE FALSE 
        END AS es_nocturno,

        CASE WHEN UPPER(TRIM(gravedad_accidente_reportada)) IN ('GRAVE', 'MORTAL') 
             THEN TRUE ELSE FALSE 
        END AS es_grave_o_mortal

    FROM fechas_parseadas
)

SELECT *
FROM normalizado
WHERE fecha_hora IS NOT NULL
  AND macrodistrito IS NOT NULL