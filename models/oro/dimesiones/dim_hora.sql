

WITH horas AS (
    SELECT SEQ4() AS hora FROM TABLE(GENERATOR(ROWCOUNT => 24))
)
SELECT
    hora * 100 AS hora_key,
    hora,
    0 AS minuto,
    CASE
        WHEN hora BETWEEN 0 AND 5 THEN 'MADRUGADA'
        WHEN hora BETWEEN 6 AND 11 THEN 'MANANA'
        WHEN hora BETWEEN 12 AND 17 THEN 'TARDE'
        ELSE 'NOCHE'
    END AS periodo_dia,
    CASE 
        WHEN hora IN (7, 8, 9, 17, 18, 19) THEN TRUE 
        ELSE FALSE 
    END AS es_hora_pico
FROM horas