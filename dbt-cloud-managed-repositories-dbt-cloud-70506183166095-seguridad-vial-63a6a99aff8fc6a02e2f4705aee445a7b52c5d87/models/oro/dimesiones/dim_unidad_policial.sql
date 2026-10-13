-- Modelo dbt: dim_unidad_policial.sql
-- Consolidación de unidades policiales lista para la Capa Oro

WITH unidades AS (
    SELECT DISTINCT
        UPPER(unidad_policial) AS nombre_unidad,
        UPPER(macrodistrito) AS macrodistrito_declarado
    FROM {{ ref('plata_accidentes') }}
    WHERE unidad_policial IS NOT NULL 
      AND UPPER(unidad_policial) != 'NO ESPECIFICADO'
    
    UNION
    
    SELECT DISTINCT
        UPPER(unidad_policial),
        UPPER(macrodistrito)
    FROM {{ ref('plata_infracciones') }}
    WHERE unidad_policial IS NOT NULL 
      AND UPPER(unidad_policial) != 'NO ESPECIFICADO'
)

SELECT
    ROW_NUMBER() OVER (ORDER BY nombre_unidad, macrodistrito_declarado) AS unidad_policial_key,
    nombre_unidad,
    
    -- Clasificación del alcance de la jurisdicción
    CASE
        WHEN macrodistrito_declarado = 'TODA LA CIUDAD' THEN 'METROPOLITANA'
        ELSE 'LOCAL'
    END AS alcance_jurisdiccion,
    
    -- Macrodistrito asignado (NULL si operan en toda la ciudad)
    CASE
        WHEN macrodistrito_declarado = 'TODA LA CIUDAD' THEN NULL
        ELSE macrodistrito_declarado
    END AS macrodistrito_asignado,
    
    'TRANSITO' AS tipo_unidad

FROM unidades