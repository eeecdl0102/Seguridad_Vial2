{{ config(
    materialized='table',
    schema='oro',
    tags=['oro', 'dimensiones']
) }}

WITH niveles AS (
    SELECT * FROM VALUES
        ('NO ESPECIFICADO', 0, 0),
        ('LEVE',            1, 0),
        ('MODERADO',        1, 0),
        ('GRAVE',           1, 0),
        ('MORTAL',          1, 1)
    AS t(nivel_severidad, bandera_lesion, bandera_fallecimiento)
),

involucrados AS (
    SELECT * FROM VALUES
        (0, 0),
        (0, 1),
        (1, 0),
        (1, 1)
    AS t(bandera_peaton_involucrado, bandera_ciclista_involucrado)
),

combinaciones AS (
    SELECT
        n.nivel_severidad,
        (n.bandera_fallecimiento = 1)        AS bandera_fallecimiento,
        (n.bandera_lesion = 1)               AS bandera_lesion,
        (i.bandera_peaton_involucrado = 1)   AS bandera_peaton_involucrado,
        (i.bandera_ciclista_involucrado = 1) AS bandera_ciclista_involucrado
    FROM niveles n
    CROSS JOIN involucrados i
)

SELECT
    {{ dbt_utils.generate_surrogate_key([
        'nivel_severidad',
        'bandera_fallecimiento',
        'bandera_lesion',
        'bandera_peaton_involucrado',
        'bandera_ciclista_involucrado'
    ]) }} AS severidad_key,
    nivel_severidad,
    bandera_fallecimiento,
    bandera_lesion,
    bandera_peaton_involucrado,
    bandera_ciclista_involucrado
FROM combinaciones

UNION ALL

-- fila por defecto para accidentes que no encuentren severidad
SELECT
    '0',
    'DESCONOCIDO',
    FALSE,
    FALSE,
    FALSE,
    FALSE