WITH base AS (
    SELECT
        UPPER(tipo_infraccion) AS tipo_infraccion,
        UPPER(categoria_infraccion) AS categoria_infraccion,
        AVG(monto_multa) AS monto_base_multa
    FROM {{ ref('plata_infracciones') }}
    GROUP BY UPPER(tipo_infraccion), UPPER(categoria_infraccion)
)
SELECT
    ROW_NUMBER() OVER (ORDER BY tipo_infraccion) AS tipo_infraccion_key,
    tipo_infraccion AS descripcion_infraccion,
    categoria_infraccion,
    monto_base_multa
FROM base