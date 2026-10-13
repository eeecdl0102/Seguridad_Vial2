{% set rel = source('la_paz_vial', 'ACCIDENTES') %}

WITH fuente_bruta AS (
    SELECT
        {{ pick_column(rel, ['ID_REPORTE_ACCIDENTE', 'ID_REPORTE']) }}                                   AS id_reporte_accidente,
        {{ pick_column(rel, ['FECHA_HORA']) }}                                                           AS fecha_hora,
        {{ pick_column(rel, ['MACRODISTRITO']) }}                                                        AS macrodistrito,
        {{ pick_column(rel, ['ZONA_BARRIO', 'BARRIO']) }}                                                AS zona_barrio,
        {{ pick_column(rel, ['DIRECCION_EXACTA', 'DIRECCION']) }}                                        AS direccion_exacta,
        {{ pick_column(rel, ['CALLE_PRINCIPAL']) }}                                                      AS calle_principal,
        {{ pick_column(rel, ['CALLE_SECUNDARIA']) }}                                                     AS calle_secundaria,
        {{ pick_column(rel, ['LATITUD']) }}                                                              AS latitud,
        {{ pick_column(rel, ['LONGITUD']) }}                                                             AS longitud,
        {{ pick_column(rel, ['TIPO_ACCIDENTE']) }}                                                       AS tipo_accidente,
        {{ pick_column(rel, ['CAUSA_ACCIDENTE']) }}                                                      AS causa_accidente,
        {{ pick_column(rel, ['CLIMA']) }}                                                                AS clima,
        {{ pick_column(rel, ['GRAVEDAD_ACCIDENTE_REPORTADA', 'GRAVEDAD_ACCIDENTE', 'GRAVEDAD']) }}       AS gravedad_reportada,
        {{ pick_column(rel, ['UNIDAD_POLICIAL'], required=false) }}                                      AS unidad_policial,
        {{ pick_column(rel, ['UNIDAD_POLICIAL_MACRODISTRITO'], required=false) }}                        AS unidad_policial_macrodistrito,
        {{ pick_column(rel, ['CANTIDAD_VEHICULOS_REPORTADOS', 'CANTIDAD_VEHICULOS'], required=false) }}  AS cantidad_vehiculos,
        {{ pick_column(rel, ['CANTIDAD_PERSONAS_REPORTADOS', 'CANTIDAD_PERSONAS_REPORTADAS', 'CANTIDAD_PERSONAS'], required=false) }} AS cantidad_personas,
        {{ pick_column(rel, ['NARRATIVA_HECHOS', 'NARRATIVA'], required=false) }}                        AS narrativa_hechos,
        {{ pick_column(rel, ['_AIRBYTE_EXTRACTED_AT'], required=false) }}                                AS extraido_en
    FROM {{ rel }}
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(UPPER(CAST(id_reporte_accidente AS VARCHAR)))
            ORDER BY extraido_en DESC NULLS LAST
        ) AS rn
    FROM fuente_bruta
),

fechas_parseadas AS (
    SELECT *,
        -- Pasa por VARCHAR: funciona si la columna es TIMESTAMP o texto
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(CAST(fecha_hora AS VARCHAR)),
            TRY_TO_TIMESTAMP_NTZ(CAST(fecha_hora AS VARCHAR), 'DD/MM/YYYY HH24:MI:SS'),
            TRY_TO_TIMESTAMP_NTZ(CAST(fecha_hora AS VARCHAR), 'DD/MM/YYYY')
        ) AS fecha_hora_parsed,
        TRY_TO_DOUBLE(CAST(latitud  AS VARCHAR)) AS latitud_num,
        TRY_TO_DOUBLE(CAST(longitud AS VARCHAR)) AS longitud_num,
        TRY_TO_NUMBER(CAST(cantidad_vehiculos AS VARCHAR)) AS cant_veh_num,
        TRY_TO_NUMBER(CAST(cantidad_personas  AS VARCHAR)) AS cant_per_num
    FROM deduplicado
    WHERE rn = 1
),

normalizado AS (
    SELECT
        TRIM(UPPER(CAST(id_reporte_accidente AS VARCHAR))) AS id_reporte_accidente,
        fecha_hora_parsed AS fecha_hora,

        YEAR(fecha_hora_parsed)      AS anio,
        MONTH(fecha_hora_parsed)     AS mes,
        DAY(fecha_hora_parsed)       AS dia,
        HOUR(fecha_hora_parsed)      AS hora,
        DAYOFWEEK(fecha_hora_parsed) AS dia_semana,

        TRIM(UPPER(CASE WHEN macrodistrito IS NULL OR TRIM(CAST(macrodistrito AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(macrodistrito AS VARCHAR) END)) AS macrodistrito,

        TRIM(UPPER(CASE WHEN zona_barrio IS NULL OR TRIM(CAST(zona_barrio AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(zona_barrio AS VARCHAR) END)) AS zona_barrio,

        REGEXP_REPLACE(TRIM(UPPER(CAST(direccion_exacta AS VARCHAR))), '\\s+', ' ')  AS direccion_exacta,
        REGEXP_REPLACE(TRIM(UPPER(CAST(calle_principal AS VARCHAR))), '\\s+', ' ')   AS calle_principal,
        REGEXP_REPLACE(TRIM(UPPER(CAST(calle_secundaria AS VARCHAR))), '\\s+', ' ')  AS calle_secundaria,

        CASE WHEN latitud_num  BETWEEN -90  AND 90  THEN ROUND(latitud_num, 6)  END AS latitud,
        CASE WHEN longitud_num BETWEEN -180 AND 180 THEN ROUND(longitud_num, 6) END AS longitud,

        TRIM(UPPER(CASE WHEN tipo_accidente IS NULL OR TRIM(CAST(tipo_accidente AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(tipo_accidente AS VARCHAR) END)) AS tipo_accidente,

        TRIM(UPPER(CASE WHEN causa_accidente IS NULL OR TRIM(CAST(causa_accidente AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(causa_accidente AS VARCHAR) END)) AS causa_accidente,

        TRIM(UPPER(CASE WHEN clima IS NULL OR TRIM(CAST(clima AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(clima AS VARCHAR) END)) AS clima,

        CASE WHEN gravedad_reportada IS NULL
                  OR UPPER(TRIM(CAST(gravedad_reportada AS VARCHAR))) NOT IN ('LEVE','MODERADO','GRAVE','MORTAL')
             THEN 'LEVE'
             ELSE UPPER(TRIM(CAST(gravedad_reportada AS VARCHAR))) END AS gravedad_accidente,

        TRIM(UPPER(CASE WHEN unidad_policial IS NULL OR TRIM(CAST(unidad_policial AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO' ELSE CAST(unidad_policial AS VARCHAR) END)) AS unidad_policial,

        TRIM(UPPER(CASE WHEN unidad_policial_macrodistrito IS NULL
                          OR TRIM(CAST(unidad_policial_macrodistrito AS VARCHAR)) = ''
                        THEN 'NO ESPECIFICADO'
                        ELSE CAST(unidad_policial_macrodistrito AS VARCHAR) END)) AS unidad_policial_macrodistrito,

        CASE WHEN cant_veh_num < 0 OR cant_veh_num > 50  THEN NULL ELSE cant_veh_num END AS cantidad_vehiculos,
        CASE WHEN cant_per_num < 0 OR cant_per_num > 100 THEN NULL ELSE cant_per_num END AS cantidad_personas,

        REGEXP_REPLACE(TRIM(UPPER(CAST(narrativa_hechos AS VARCHAR))), '\\s+', ' ') AS narrativa_hechos,

        (HOUR(fecha_hora_parsed) >= 22 OR HOUR(fecha_hora_parsed) <= 5) AS es_nocturno,
        (UPPER(TRIM(CAST(gravedad_reportada AS VARCHAR))) IN ('GRAVE','MORTAL')) AS es_grave_o_mortal
    FROM fechas_parseadas
)

SELECT *
FROM normalizado
WHERE fecha_hora IS NOT NULL
  AND id_reporte_accidente IS NOT NULL