WITH estados_limpios AS (
    SELECT DISTINCT
        UPPER(TRIM(estado_proceso)) AS nombre_estado
    FROM {{ ref('plata_judiciales') }}
    WHERE estado_proceso IS NOT NULL 
      AND UPPER(TRIM(estado_proceso)) != 'NO ESPECIFICADO'
      AND UPPER(TRIM(estado_proceso)) != ''
)

SELECT
    ROW_NUMBER() OVER (ORDER BY nombre_estado) AS estado_proceso_key,
    nombre_estado,
    CASE
        WHEN nombre_estado IN ('EN CURSO') THEN 'EN TRAMITE'
        WHEN nombre_estado IN ('RESUELTO', 'ARCHIVADO') THEN 'CONCLUIDO'
        WHEN nombre_estado IN ('APELACION') THEN 'EN REVISION'
        ELSE 'EN TRAMITE' -- Aquí caerá 'SUSPENDIDO' y cualquier variación futura
    END AS etapa_categoria
FROM estados_limpios