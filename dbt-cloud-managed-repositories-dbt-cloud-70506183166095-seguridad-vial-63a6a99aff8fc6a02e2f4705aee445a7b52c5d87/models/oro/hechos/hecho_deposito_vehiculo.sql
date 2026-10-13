{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'hechos']
) }}

/*
HECHO_DEPOSITO_VEHICULO (Oro) -- este archivo faltaba (6 de 7 hechos ya
existian, este era el que faltaba crear).
Grano: 1 fila = 1 ingreso de vehiculo a deposito.
Fuente: plata_depositos.
dim_tipo_deposito ya trae el macrodistrito internamente (Oro-Dimensiones),
por eso este hecho no necesita un ubicacion_key propio.
*/

WITH depositos AS (
    SELECT
        numero_registro,
        fecha_ingreso,
        fecha_salida,
        placa,
        nombre_lugar_deposito,
        macrodistrito_deposito,
        tipo_administracion,
        motivo_deposito,
        estado_vehiculo_deposito,
        dias_estadia_reportados,
        dias_estadia_calculados,
        costo_almacenaje,
        id_reporte_accidente_relacionado,
        vehiculo_retirado
    FROM {{ ref('plata_depositos') }}
    WHERE numero_registro IS NOT NULL
      AND TRIM(numero_registro) <> ''
),

fechas AS (
    SELECT fecha_key, fecha_completa
    FROM {{ ref('dim_fecha') }}
),

-- dedupe por placa: dim_vehiculo tiene 1 fila por (placa, direccion_desplazamiento)
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

tipos_deposito AS (
    SELECT
        tipo_deposito_key,
        UPPER(TRIM(nombre_deposito))     AS nombre_deposito,
        UPPER(TRIM(tipo_administracion)) AS tipo_administracion,
        UPPER(TRIM(macrodistrito))       AS macrodistrito
    FROM {{ ref('dim_tipo_deposito') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(nombre_deposito))
        ORDER BY tipo_deposito_key
    ) = 1
)

SELECT
    ROW_NUMBER() OVER (ORDER BY d.numero_registro) AS deposito_key,

    NULLIF(TRIM(d.id_reporte_accidente_relacionado), '') AS codigo_informe_policial,
    COALESCE(TO_VARCHAR(v.vehiculo_key), '0')       AS vehiculo_key,
    COALESCE(TO_VARCHAR(td.tipo_deposito_key), '0') AS tipo_deposito_key,
    COALESCE(fi.fecha_key, 0)           AS fecha_ingreso_key,
    fs.fecha_key                        AS fecha_salida_key,   -- nulo si sigue en deposito

    d.motivo_deposito,
    d.estado_vehiculo_deposito,
    d.dias_estadia_reportados,
    COALESCE(d.dias_estadia_calculados,
             DATEDIFF('day', CAST(d.fecha_ingreso AS DATE), CAST(d.fecha_salida AS DATE))
    ) AS dias_en_deposito,
    d.costo_almacenaje,
    IFF(d.fecha_salida IS NULL, TRUE, FALSE) AS permanece_en_deposito,
    1 AS cantidad_ingresos_deposito

FROM depositos d

LEFT JOIN fechas fi
    ON CAST(d.fecha_ingreso AS DATE) = fi.fecha_completa

LEFT JOIN fechas fs
    ON CAST(d.fecha_salida AS DATE) = fs.fecha_completa

LEFT JOIN vehiculos v
    ON UPPER(TRIM(REPLACE(d.placa, '-', ''))) = v.placa

LEFT JOIN tipos_deposito td
    ON UPPER(TRIM(d.nombre_lugar_deposito)) = td.nombre_deposito