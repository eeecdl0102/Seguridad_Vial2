{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'hechos']
) }}

-- 1) Infracciones: se deduplica por acta
WITH infracciones AS (
    SELECT
        numero_acta,
        CAST(fecha_hora AS TIMESTAMP) AS fecha_hora,
        macrodistrito,
        zona_barrio,
        direccion_exacta,
        numero_documento_conductor,
        REGEXP_REPLACE(UPPER(TRIM(numero_documento_conductor)), '[^A-Z0-9]', '') AS doc_norm,
        REGEXP_REPLACE(UPPER(TRIM(placa)), '[^A-Z0-9]', '') AS placa_norm,
        tipo_infraccion,
        unidad_policial,
        id_reporte_accidente_relacionado,
        REGEXP_REPLACE(UPPER(TRIM(id_reporte_accidente_relacionado)), '[^A-Z0-9]', '') AS accidente_norm,
        monto_multa,
        esta_pagada
    FROM {{ ref('plata_infracciones') }}
    WHERE numero_acta IS NOT NULL
      AND TRIM(numero_acta) <> ''
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY numero_acta
        ORDER BY fecha_hora
    ) = 1
),

-- 2) Dimensiones normalizadas y deduplicadas (un duplicado en una dim multiplica filas del hecho)
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

-- ubicación exacta (esquina): macrodistrito + barrio + punto de referencia
ubicaciones_exactas AS (
    SELECT
        UBICACION_KEY AS ubicacion_key,
        UPPER(TRIM(MACRODISTRITO)) AS macrodistrito,
        UPPER(TRIM(ZONA_BARRIO)) AS zona_barrio,
        UPPER(TRIM(PUNTO_REFERENCIA)) AS direccion_exacta
    FROM {{ ref('dim_ubicacion') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(MACRODISTRITO)), UPPER(TRIM(ZONA_BARRIO)), UPPER(TRIM(PUNTO_REFERENCIA))
        ORDER BY UBICACION_KEY
    ) = 1
),

-- respaldo: solo barrio, por si la dirección no coincide con ninguna esquina
ubicaciones_barrio AS (
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

personas AS (
    SELECT
        PERSONA_KEY AS persona_key,
        REGEXP_REPLACE(UPPER(TRIM(NUMERO_DOCUMENTO)), '[^A-Z0-9]', '') AS doc_norm
    FROM {{ ref('dim_persona') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_REPLACE(UPPER(TRIM(NUMERO_DOCUMENTO)), '[^A-Z0-9]', '')
        ORDER BY PERSONA_KEY
    ) = 1
),

vehiculos AS (
    SELECT
        VEHICULO_KEY AS vehiculo_key,
        REGEXP_REPLACE(UPPER(TRIM(PLACA)), '[^A-Z0-9]', '') AS placa_norm
    FROM {{ ref('dim_vehiculo') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_REPLACE(UPPER(TRIM(PLACA)), '[^A-Z0-9]', '')
        ORDER BY VEHICULO_KEY
    ) = 1
),

tipos AS (
    SELECT
        TIPO_INFRACCION_KEY AS tipo_infraccion_key,
        UPPER(TRIM(DESCRIPCION_INFRACCION)) AS descripcion_infraccion
    FROM {{ ref('dim_tipo_infraccion') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(DESCRIPCION_INFRACCION))
        ORDER BY TIPO_INFRACCION_KEY
    ) = 1
),

-- CAMBIO 3: unidad exacta = nombre de la unidad + macrodistrito asignado
unidades_exactas AS (
    SELECT
        UNIDAD_POLICIAL_KEY AS unidad_key,
        UPPER(TRIM(NOMBRE_UNIDAD)) AS nombre_unidad,
        UPPER(TRIM(MACRODISTRITO_ASIGNADO)) AS macrodistrito
    FROM {{ ref('dim_unidad_policial') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(NOMBRE_UNIDAD)), UPPER(TRIM(MACRODISTRITO_ASIGNADO))
        ORDER BY UNIDAD_POLICIAL_KEY
    ) = 1
),

-- respaldo: solo por nombre, si no coincide el macrodistrito
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

-- códigos de accidente con el mismo formato que usa hecho_accidente (ej. PTA-100000)
accidentes_codigo AS (
    SELECT
        REGEXP_REPLACE(UPPER(TRIM(ID_REPORTE_ACCIDENTE)), '[^A-Z0-9]', '') AS accidente_norm,
        ID_REPORTE_ACCIDENTE AS codigo_informe_policial
    FROM {{ ref('plata_accidentes') }}
    WHERE ID_REPORTE_ACCIDENTE IS NOT NULL
      AND TRIM(ID_REPORTE_ACCIDENTE) <> ''
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY REGEXP_REPLACE(UPPER(TRIM(ID_REPORTE_ACCIDENTE)), '[^A-Z0-9]', '')
        ORDER BY FECHA_HORA
    ) = 1
)

SELECT
    ROW_NUMBER() OVER (ORDER BY i.numero_acta) AS infraccion_key,
    i.numero_acta AS codigo_boleta,

    COALESCE(f.fecha_key, 0) AS fecha_key,
    COALESCE(h.hora_key, 0)  AS hora_key,

    -- ubicacion, persona y vehiculo: claves hash (texto), el defecto también va como texto
    COALESCE(TO_VARCHAR(COALESCE(ue.ubicacion_key, ub.ubicacion_key)), '0') AS ubicacion_key,
    COALESCE(TO_VARCHAR(p.persona_key), '0')   AS persona_key,
    COALESCE(TO_VARCHAR(v.vehiculo_key), '0')  AS vehiculo_key,
    -- tipo_infraccion_key y unidad_key son numéricas
    COALESCE(t.tipo_infraccion_key, 0)         AS tipo_infraccion_key,
    -- CAMBIO 3: primero unidad exacta (nombre + macrodistrito), luego solo nombre
    COALESCE(uex.unidad_key, up.unidad_key, 0) AS unidad_policial_key,

    COALESCE(
        ac.codigo_informe_policial,
        NULLIF(TRIM(i.id_reporte_accidente_relacionado), '')
    ) AS codigo_informe_policial,

    -- CAMBIO 1: si el monto falta o no se puede convertir, queda NULL (ya no 0)
    TRY_TO_DECIMAL(TO_VARCHAR(i.monto_multa), 12, 2) AS monto_multa,

    -- CAMBIO 2: si el dato viene vacío, queda NULL (ya no FALSE)
    CASE
        WHEN i.esta_pagada IS NULL THEN NULL
        ELSE COALESCE(
            TRY_TO_BOOLEAN(TO_VARCHAR(i.esta_pagada)),
            UPPER(TRIM(TO_VARCHAR(i.esta_pagada))) IN ('SI', 'SÍ'),
            FALSE
        )
    END AS esta_pagada

FROM infracciones i

LEFT JOIN fechas f
    ON CAST(i.fecha_hora AS DATE) = f.fecha_completa

LEFT JOIN horas h
    ON HOUR(i.fecha_hora) = h.hora

LEFT JOIN ubicaciones_exactas ue
    ON UPPER(TRIM(i.macrodistrito)) = ue.macrodistrito
   AND UPPER(TRIM(i.zona_barrio)) = ue.zona_barrio
   AND UPPER(TRIM(i.direccion_exacta)) = ue.direccion_exacta

LEFT JOIN ubicaciones_barrio ub
    ON UPPER(TRIM(i.macrodistrito)) = ub.macrodistrito
   AND UPPER(TRIM(i.zona_barrio)) = ub.zona_barrio

LEFT JOIN personas p
    ON i.doc_norm = p.doc_norm

LEFT JOIN vehiculos v
    ON i.placa_norm = v.placa_norm

LEFT JOIN tipos t
    ON UPPER(TRIM(i.tipo_infraccion)) = t.descripcion_infraccion

-- CAMBIO 3: join por nombre + macrodistrito
LEFT JOIN unidades_exactas uex
    ON UPPER(TRIM(i.unidad_policial)) = uex.nombre_unidad
   AND UPPER(TRIM(i.macrodistrito)) = uex.macrodistrito

-- respaldo solo por nombre
LEFT JOIN unidades up
    ON UPPER(TRIM(i.unidad_policial)) = up.nombre_unidad

LEFT JOIN accidentes_codigo ac
    ON i.accidente_norm = ac.accidente_norm