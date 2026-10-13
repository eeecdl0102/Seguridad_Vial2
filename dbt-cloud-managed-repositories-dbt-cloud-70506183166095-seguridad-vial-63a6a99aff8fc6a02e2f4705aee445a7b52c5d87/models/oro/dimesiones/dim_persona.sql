WITH personas AS (
    SELECT
        p.*,
        REPLACE(REPLACE(UPPER(TRIM(p.numero_documento)), '-', ''), ' ', '') AS doc_norm
    FROM {{ ref('plata_personas') }} p
),

victimas AS (
    SELECT
        v.*,
        REPLACE(REPLACE(UPPER(TRIM(v.numero_documento_victima)), '-', ''), ' ', '') AS doc_norm
    FROM {{ ref('plata_victimas') }} v
),

perfiles_base AS (
    SELECT
        p.numero_documento,
        CASE
            WHEN UPPER(p.categoria_licencia) = 'SIN LICENCIA'   THEN 'PEATON'
            WHEN UPPER(p.categoria_licencia) IN ('M', 'P')      THEN 'MOTOCICLISTA'
            WHEN UPPER(p.categoria_licencia) IN ('A', 'B', 'C') THEN 'CONDUCTOR'
            ELSE 'OTRO'
        END AS tipo_persona,
        CASE
            WHEN UPPER(p.categoria_licencia) = 'SIN LICENCIA' THEN 'N-A'
            ELSE 'CONDUCTOR'
        END AS rol,
        UPPER(p.genero) AS sexo,
        CASE
            WHEN p.edad_calculada < 18              THEN '0-17'
            WHEN p.edad_calculada BETWEEN 18 AND 25 THEN '18-25'
            WHEN p.edad_calculada BETWEEN 26 AND 40 THEN '26-40'
            WHEN p.edad_calculada BETWEEN 41 AND 65 THEN '41-65'
            WHEN p.edad_calculada > 65              THEN '65+'
            ELSE 'DESCONOCIDO'
        END AS rango_edad,
        'SIN LESION / NO APLICA'                 AS severidad_lesion,
        'N/A'                                    AS equipo_seguridad,
        COALESCE(UPPER(p.categoria_licencia), 'SIN DATO') AS estado_licencia_conducir,
        'N/A'                                    AS posicion_en_vehiculo,
        'N/A'                                    AS rol_peaton,
        'N/A'                                    AS accion_peaton,
        FALSE                                    AS expulsion
    FROM personas p
    -- si la persona ya aparece como víctima, se representa solo con su perfil de víctima
    WHERE NOT EXISTS (SELECT 1 FROM victimas v WHERE v.doc_norm = p.doc_norm)
),

perfiles_victima AS (
    SELECT DISTINCT
        COALESCE(p.numero_documento, v.numero_documento_victima) AS numero_documento,
        UPPER(v.tipo_usuario) AS tipo_persona,
        CASE
            WHEN UPPER(v.tipo_usuario) = 'PEATON'                      THEN 'PEATON'
            WHEN UPPER(v.tipo_usuario) IN ('MOTOCICLISTA', 'CICLISTA') THEN UPPER(v.tipo_usuario)
            ELSE 'OCUPANTE'
        END AS rol,
        COALESCE(UPPER(p.genero), 'DESCONOCIDO') AS sexo,
        CASE
            WHEN p.edad_calculada IS NULL           THEN 'DESCONOCIDO'
            WHEN p.edad_calculada < 18              THEN '0-17'
            WHEN p.edad_calculada BETWEEN 18 AND 25 THEN '18-25'
            WHEN p.edad_calculada BETWEEN 26 AND 40 THEN '26-40'
            WHEN p.edad_calculada BETWEEN 41 AND 65 THEN '41-65'
            ELSE '65+'
        END AS rango_edad,
        COALESCE(UPPER(v.gravedad_lesion), 'SIN LESION / NO APLICA') AS severidad_lesion,
        CASE
            WHEN UPPER(TO_VARCHAR(v.uso_casco))    IN ('SI', 'TRUE')  THEN 'CASCO'
            WHEN UPPER(TO_VARCHAR(v.uso_cinturon)) IN ('SI', 'TRUE')  THEN 'CINTURON'
            WHEN UPPER(TO_VARCHAR(v.uso_casco))    IN ('NO', 'FALSE')
              OR UPPER(TO_VARCHAR(v.uso_cinturon)) IN ('NO', 'FALSE') THEN 'NINGUNO'
            ELSE 'N/A'
        END AS equipo_seguridad,
        COALESCE(UPPER(p.categoria_licencia), 'SIN DATO') AS estado_licencia_conducir,
        COALESCE(UPPER(v.posicion_en_vehiculo), 'N/A')    AS posicion_en_vehiculo,
        COALESCE(UPPER(v.rol_peaton), 'N/A')              AS rol_peaton,
        COALESCE(UPPER(v.accion_peaton), 'N/A')           AS accion_peaton,
        COALESCE(UPPER(TO_VARCHAR(v.expulsion)) IN ('SI', 'TRUE'), FALSE) AS expulsion
    FROM victimas v
    LEFT JOIN personas p
        ON v.doc_norm = p.doc_norm
),

todos AS (
    SELECT * FROM perfiles_base
    UNION ALL
    SELECT * FROM perfiles_victima
)

SELECT
    {{ dbt_utils.generate_surrogate_key([
        'numero_documento',
        "COALESCE(tipo_persona, 'UNKNOWN')",
        "COALESCE(rol, 'UNKNOWN')",
        "COALESCE(rango_edad, 'UNKNOWN')",
        "COALESCE(severidad_lesion, 'N/A')",
        "COALESCE(equipo_seguridad, 'N/A')",
        "COALESCE(posicion_en_vehiculo, 'N/A')",
        "COALESCE(rol_peaton, 'N/A')",
        "COALESCE(accion_peaton, 'N/A')",
        "COALESCE(TO_VARCHAR(expulsion), 'N/A')"
    ]) }} AS persona_key,
    numero_documento,
    tipo_persona,
    rol,
    sexo,
    rango_edad,
    severidad_lesion,
    equipo_seguridad,
    estado_licencia_conducir,
    posicion_en_vehiculo,
    rol_peaton,
    accion_peaton,
    expulsion
FROM todos
QUALIFY ROW_NUMBER() OVER (PARTITION BY persona_key ORDER BY numero_documento) = 1