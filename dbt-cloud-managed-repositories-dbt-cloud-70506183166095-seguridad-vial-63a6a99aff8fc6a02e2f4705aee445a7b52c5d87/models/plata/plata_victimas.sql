-- models/plata/plata_victimas.sql
-- Lee directo del source: SEGURIDAD_VIAL_DB.BRONCE.ACCIDENTE_VICTIMAS
-- Granularidad: 1 fila = 1 victima por accidente
-- Destino: SEGURIDAD_VIAL_DB.PLATA.plata_victimas

WITH fuente_bruta AS (
    SELECT *
    FROM {{ source('la_paz_vial', 'ACCIDENTE_VICTIMAS') }}
),

deduplicado AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY id_reporte_accidente, numero_documento_victima
            ORDER BY 1
        ) AS rn
    FROM fuente_bruta
),

normalizado AS (
    SELECT
        REGEXP_REPLACE(TRIM(UPPER(id_reporte_accidente)), '[^A-ZÁÉÍÓÚÑ0-9\\s_-]', '') AS id_reporte_accidente,

        -- Documento de la victima (permitiendo letras, Ñ, números, espacios y guiones bajos para 'SIN_DOCUMENTO')
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN numero_documento_victima IS NULL OR TRIM(numero_documento_victima) = '' THEN 'SIN_DOCUMENTO'
                    ELSE numero_documento_victima 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ0-9\\s_]', ''
        ) AS numero_documento_victima,

        -- Tipo de usuario / rol
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN tipo_usuario IS NULL OR TRIM(tipo_usuario) = '' THEN 'NO ESPECIFICADO'
                    ELSE tipo_usuario 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS tipo_usuario,

        -- Gravedad de la lesion 
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN gravedad_lesion IS NULL OR TRIM(gravedad_lesion) = '' THEN 'LEVE'
                    WHEN UPPER(TRIM(gravedad_lesion)) NOT IN ('LEVE', 'MODERADA', 'GRAVE', 'MORTAL') THEN 'LEVE'
                    ELSE gravedad_lesion
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS gravedad_lesion,

        -- Uso de casco (solo aplica a motociclistas y ciclistas)
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN uso_casco IS NULL OR TRIM(uso_casco) = '' THEN 'N/A'
                    ELSE uso_casco 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s/]', ''
        ) AS uso_casco,

        -- Uso de cinturon (solo aplica a ocupantes de vehiculo)
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN uso_cinturon IS NULL OR TRIM(uso_cinturon) = '' THEN 'N/A'
                    ELSE uso_cinturon 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s/]', ''
        ) AS uso_cinturon,

        -- Posicion en el vehiculo
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN posicion_en_vehiculo IS NULL OR TRIM(posicion_en_vehiculo) = '' THEN 'NO APLICA'
                    ELSE posicion_en_vehiculo 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS posicion_en_vehiculo,

        -- Expulsion
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN expulsion IS NULL OR TRIM(expulsion) = '' THEN 'NO APLICA'
                    ELSE expulsion 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS expulsion,

        -- Rol de peaton
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN rol_peaton IS NULL OR TRIM(rol_peaton) = '' THEN 'NO APLICA'
                    ELSE rol_peaton 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS rol_peaton,

        -- Accion del peaton
        REGEXP_REPLACE(
            TRIM(UPPER(
                CASE 
                    WHEN accion_peaton IS NULL OR TRIM(accion_peaton) = '' THEN 'NO APLICA'
                    ELSE accion_peaton 
                END
            )), 
            '[^A-ZÁÉÍÓÚÑ\\s]', ''
        ) AS accion_peaton,

        -- Flags derivados
        CASE WHEN UPPER(TRIM(gravedad_lesion)) IN ('GRAVE', 'MORTAL') 
             THEN TRUE ELSE FALSE 
        END AS es_lesion_grave_o_mortal,

        CASE WHEN UPPER(TRIM(uso_casco)) = 'NO' 
                  AND UPPER(TRIM(tipo_usuario)) IN ('MOTOCICLISTA', 'CICLISTA')
             THEN TRUE ELSE FALSE 
        END AS sin_casco_moto_bici,

        CASE WHEN UPPER(TRIM(uso_cinturon)) = 'NO' 
                  AND UPPER(TRIM(tipo_usuario)) IN ('CONDUCTOR', 'PASAJERO')
             THEN TRUE ELSE FALSE 
        END AS sin_cinturon

    FROM deduplicado
    WHERE rn = 1
)

SELECT *
FROM normalizado
WHERE id_reporte_accidente IS NOT NULL