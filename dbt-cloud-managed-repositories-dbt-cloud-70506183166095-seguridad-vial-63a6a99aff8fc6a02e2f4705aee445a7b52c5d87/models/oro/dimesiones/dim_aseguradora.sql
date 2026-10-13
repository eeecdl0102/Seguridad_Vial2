-- Modelo dbt: dim_aseguradoras.sql
-- Consolidación de compañías aseguradoras y tipos de póliza a partir de la plataforma de seguros

WITH aseguradoras_limpias AS (
    SELECT DISTINCT
        UPPER(TRIM(nombre_compania)) AS nombre_aseguradora,
        UPPER(TRIM(tipo_poliza)) AS tipo_seguro
    FROM {{ ref('plata_seguros') }}
    WHERE nombre_compania IS NOT NULL 
      AND UPPER(TRIM(nombre_compania)) != 'NO ESPECIFICADO'
      AND UPPER(TRIM(nombre_compania)) != ''
)

SELECT
    ROW_NUMBER() OVER (ORDER BY nombre_aseguradora, tipo_seguro) AS aseguradora_key,
    nombre_aseguradora,
    tipo_seguro
FROM aseguradoras_limpias