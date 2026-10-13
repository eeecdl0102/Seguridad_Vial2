{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'hechos']
) }}

-- 1) Accidentes: se deduplica por ID normalizado (sin guiones ni espacios) para poder cruzar tablas
WITH accidentes AS (
    SELECT
        ID_REPORTE_ACCIDENTE,
        REGEXP_REPLACE(UPPER(TRIM(ID_REPORTE_ACCIDENTE)), '[^A-Z0-9]', '') AS id_norm,
        CAST(FECHA_HORA AS TIMESTAMP) AS FECHA_HORA,
        MACRODISTRITO,
        ZONA_BARRIO,
        DIRECCION_EXACTA,
        CAUSA_ACCIDENTE,
        GRAVEDAD_ACCIDENTE,
        UNIDAD_POLICIAL,
        NARRATIVA_HECHOS,
        CANTIDAD_VEHICULOS,
        CANTIDAD_PERSONAS
    FROM {{ ref('plata_accidentes') }}
    WHERE ID_REPORTE_ACCIDENTE IS NOT NULL
      AND TRIM(ID_REPORTE_ACCIDENTE) <> ''
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_REPLACE(UPPER(TRIM(ID_REPORTE_ACCIDENTE)), '[^A-Z0-9]', '')
        ORDER BY FECHA_HORA
    ) = 1
),

vehiculos_agrupados AS (
    SELECT
        REGEXP_REPLACE(UPPER(TRIM(id_reporte_accidente)), '[^A-Z0-9]', '') AS id_norm,
        COUNT(*) AS num_vehiculos_involucrados
    FROM {{ ref('plata_vehiculos_accidente') }}
    WHERE id_reporte_accidente IS NOT NULL
      AND TRIM(id_reporte_accidente) <> ''
    GROUP BY REGEXP_REPLACE(UPPER(TRIM(id_reporte_accidente)), '[^A-Z0-9]', '')
),

-- 2) Víctimas: se clasifica cada fila (sin tildes, mayúsculas, patrones flexibles)
victimas_norm AS (
    SELECT
        REGEXP_REPLACE(UPPER(TRIM(id_reporte_accidente)), '[^A-Z0-9]', '') AS id_norm,
        CASE
            WHEN g LIKE 'MORTAL%' OR g LIKE '%FALLEC%' OR g LIKE 'MUERT%' THEN 4
            WHEN g LIKE 'GRAV%'     THEN 3
            WHEN g LIKE 'MODERAD%'  THEN 2
            WHEN g LIKE 'LEV%'      THEN 1
            ELSE 0
        END AS nivel_lesion_fila,
        IFF(t LIKE 'PEAT%', 1, 0)    AS es_peaton,
        IFF(t LIKE 'CICLIST%', 1, 0) AS es_ciclista
    FROM (
        SELECT
            id_reporte_accidente,
            TRANSLATE(UPPER(TRIM(GRAVEDAD_LESION)), 'ÁÉÍÓÚÜ', 'AEIOUU') AS g,
            TRANSLATE(UPPER(TRIM(TIPO_USUARIO)),    'ÁÉÍÓÚÜ', 'AEIOUU') AS t
        FROM {{ ref('plata_victimas') }}
    )
    WHERE id_reporte_accidente IS NOT NULL
      AND TRIM(id_reporte_accidente) <> ''
),

victimas_y_severidad AS (
    SELECT
        id_norm,
        COUNT(*)                                   AS num_personas_victimas,
        SUM(IFF(nivel_lesion_fila >= 1, 1, 0))     AS num_personas_heridas,
        SUM(IFF(nivel_lesion_fila = 4, 1, 0))      AS num_personas_fallecidas,
        SUM(es_peaton)                             AS num_peatones_involucrados,
        MAX(nivel_lesion_fila)                     AS nivel_lesion,
        MAX(es_peaton)                             AS bandera_peaton,
        MAX(es_ciclista)                           AS bandera_ciclista,
        MAX(IFF(nivel_lesion_fila = 4, 1, 0))      AS bandera_fallecimiento,
        MAX(IFF(nivel_lesion_fila >= 1, 1, 0))     AS bandera_lesion
    FROM victimas_norm
    GROUP BY id_norm
),

-- 3) Dimensiones (deduplicadas: un duplicado en una dim multiplica filas del hecho)
severidad_dim AS (
    SELECT
        SEVERIDAD_KEY AS severidad_key,
        NIVEL_SEVERIDAD AS nivel_severidad,
        BANDERA_FALLECIMIENTO AS bandera_fallecimiento,
        BANDERA_LESION AS bandera_lesion,
        BANDERA_PEATON_INVOLUCRADO AS bandera_peaton_involucrado,
        BANDERA_CICLISTA_INVOLUCRADO AS bandera_ciclista_involucrado
    FROM {{ ref('dim_severidad') }}
),

ubicaciones AS (
    SELECT
        UBICACION_KEY AS ubicacion_key,
        UPPER(TRIM(MACRODISTRITO)) AS macrodistrito,
        UPPER(TRIM(ZONA_BARRIO)) AS zona_barrio
    FROM {{ ref('dim_ubicacion') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(MACRODISTRITO)), UPPER(TRIM(ZONA_BARRIO))
        ORDER BY UBICACION_KEY
    ) = 1
),

factores AS (
    SELECT
        FACTOR_CONTRIBUYENTE_KEY AS factor_key,
        UPPER(TRIM(DESCRIPCION_FACTOR)) AS descripcion_factor
    FROM {{ ref('dim_factor_contribuyente') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(DESCRIPCION_FACTOR))
        ORDER BY FACTOR_CONTRIBUYENTE_KEY
    ) = 1
),

unidades AS (
    SELECT
        UNIDAD_POLICIAL_KEY AS unidad_key,
        UPPER(TRIM(NOMBRE_UNIDAD)) AS nombre_unidad
    FROM {{ ref('dim_unidad_policial') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(NOMBRE_UNIDAD))
        ORDER BY UNIDAD_POLICIAL_KEY
    ) = 1
),

fechas AS (
    SELECT
        FECHA_KEY AS fecha_key,
        CAST(FECHA_COMPLETA AS DATE) AS fecha_completa
    FROM {{ ref('dim_fecha') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CAST(FECHA_COMPLETA AS DATE)
        ORDER BY FECHA_KEY
    ) = 1
),

horas AS (
    SELECT
        HORA_KEY AS hora_key,
        HORA AS hora
    FROM {{ ref('dim_hora') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY HORA
        ORDER BY HORA_KEY
    ) = 1
),

-- 4) Base: un registro por accidente con sus métricas
base AS (
    SELECT
        a.ID_REPORTE_ACCIDENTE,
        a.FECHA_HORA,
        a.MACRODISTRITO,
        a.ZONA_BARRIO,
        a.DIRECCION_EXACTA,
        a.CAUSA_ACCIDENTE,
        a.GRAVEDAD_ACCIDENTE,
        a.UNIDAD_POLICIAL,
        a.NARRATIVA_HECHOS,

        GREATEST(
            COALESCE(a.CANTIDAD_VEHICULOS, 0),
            COALESCE(ve.num_vehiculos_involucrados, 0)
        ) AS num_vehiculos_involucrados,

        COALESCE(v.num_personas_heridas, 0)      AS num_personas_heridas,
        COALESCE(v.num_personas_fallecidas, 0)   AS num_personas_fallecidas,
        COALESCE(v.num_peatones_involucrados, 0) AS num_peatones_involucrados,
        COALESCE(v.bandera_fallecimiento, 0)     AS bandera_fallecimiento,
        COALESCE(v.bandera_lesion, 0)            AS bandera_lesion,
        COALESCE(v.bandera_peaton, 0)            AS bandera_peaton,
        COALESCE(v.bandera_ciclista, 0)          AS bandera_ciclista,

        CASE COALESCE(v.nivel_lesion, 0)
            WHEN 4 THEN 'MORTAL'
            WHEN 3 THEN 'GRAVE'
            WHEN 2 THEN 'MODERADO'
            WHEN 1 THEN 'LEVE'
            ELSE 'NO ESPECIFICADO'
        END AS nivel_severidad

    FROM accidentes a
    LEFT JOIN vehiculos_agrupados ve
        ON a.id_norm = ve.id_norm
    LEFT JOIN victimas_y_severidad v
        ON a.id_norm = v.id_norm
)

SELECT
    ROW_NUMBER() OVER (ORDER BY b.ID_REPORTE_ACCIDENTE) AS accidente_key,
    b.ID_REPORTE_ACCIDENTE AS codigo_informe_policial,

    COALESCE(f.fecha_key, 0)  AS fecha_key,
    COALESCE(h.hora_key, 0)   AS hora_key,
    -- ubicacion_key y severidad_key son hashes (texto): el valor por defecto también va como texto
    COALESCE(TO_VARCHAR(u.ubicacion_key), '0') AS ubicacion_key,
    COALESCE(fc.factor_key, 0)   AS factor_contribuyente_key,
    COALESCE(TO_VARCHAR(sd.severidad_key), '0') AS severidad_key,
    COALESCE(up.unidad_key, 0)   AS unidad_policial_key,

    b.NARRATIVA_HECHOS AS descripcion_hechos,
    b.num_personas_heridas,
    b.num_personas_fallecidas,
    b.num_peatones_involucrados,
    b.num_vehiculos_involucrados,
    1 AS cantidad_accidentes

FROM base b

LEFT JOIN fechas f
    ON CAST(b.FECHA_HORA AS DATE) = f.fecha_completa

LEFT JOIN horas h
    ON HOUR(b.FECHA_HORA) = h.hora

LEFT JOIN ubicaciones u
    ON UPPER(TRIM(b.MACRODISTRITO)) = u.macrodistrito
   AND UPPER(TRIM(b.ZONA_BARRIO)) = u.zona_barrio

LEFT JOIN factores fc
    ON UPPER(TRIM(b.CAUSA_ACCIDENTE)) = fc.descripcion_factor

LEFT JOIN unidades up
    ON UPPER(TRIM(b.UNIDAD_POLICIAL)) = up.nombre_unidad

LEFT JOIN severidad_dim sd
    ON b.nivel_severidad = sd.nivel_severidad
   AND (b.bandera_fallecimiento = 1) = sd.bandera_fallecimiento
   AND (b.bandera_lesion = 1)        = sd.bandera_lesion
   AND (b.bandera_peaton = 1)        = sd.bandera_peaton_involucrado
   AND (b.bandera_ciclista = 1)      = sd.bandera_ciclista_involucrado