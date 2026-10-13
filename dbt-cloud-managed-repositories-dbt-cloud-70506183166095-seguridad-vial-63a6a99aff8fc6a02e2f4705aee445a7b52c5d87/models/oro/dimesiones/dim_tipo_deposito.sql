

WITH depositos_base AS (
    SELECT DISTINCT
        UPPER(TRIM(COALESCE(nombre_lugar_deposito, 'NO ESPECIFICADO'))) AS nombre_deposito,
        UPPER(TRIM(COALESCE(tipo_administracion, 'NO ESPECIFICADO'))) AS tipo_administracion,
        UPPER(TRIM(COALESCE(macrodistrito_deposito, 'NO ESPECIFICADO'))) AS macrodistrito
    FROM {{ ref('plata_depositos') }}
    WHERE nombre_lugar_deposito IS NOT NULL
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['nombre_deposito', 'tipo_administracion', 'macrodistrito']) }} AS tipo_deposito_key,
    nombre_deposito,
    tipo_administracion,
    macrodistrito
FROM depositos_base