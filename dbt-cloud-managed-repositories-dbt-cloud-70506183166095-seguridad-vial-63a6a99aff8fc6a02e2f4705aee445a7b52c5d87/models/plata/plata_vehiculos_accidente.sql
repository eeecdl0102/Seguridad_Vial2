-- models/plata/plata_vehiculos_accidente.sql

-- Lee directo del source: SEGURIDAD_VIAL_DB.BRONCE.ACCIDENTE_VEHICULOS
-- Granularidad: 1 fila = 1 vehiculo por accidente
-- Destino: SEGURIDAD_VIAL_DB.PLATA.plata_vehiculos_accidente

WITH fuente_bruta AS (

    SELECT *
    FROM {{ source('la_paz_vial', 'ACCIDENTE_VEHICULOS') }}

),

deduplicado AS (

    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY id_reporte_accidente, placa
            ORDER BY 1
        ) AS rn
    FROM fuente_bruta

),

normalizado AS (

    SELECT

        REGEXP_REPLACE(
            TRIM(UPPER(id_reporte_accidente)),
            '[^A-ZÁÉÍÓÚÑ0-9\\s_-]',
            ''
        ) AS id_reporte_accidente,

        REGEXP_REPLACE(
            TRIM(
                UPPER(
                    CASE
                        WHEN placa IS NULL
                          OR TRIM(placa) = ''
                        THEN 'SIN_PLACA'
                        ELSE placa
                    END
                )
            ),
            '[^A-ZÁÉÍÓÚÑ0-9\\s_-]',
            ''
        ) AS placa,

        REGEXP_REPLACE(
            TRIM(
                UPPER(
                    CASE
                        WHEN direccion_desplazamiento IS NULL
                          OR TRIM(direccion_desplazamiento) = ''
                        THEN 'NO ESPECIFICADO'
                        ELSE direccion_desplazamiento
                    END
                )
            ),
            '[^A-ZÁÉÍÓÚÑ\\s]',
            ''
        ) AS direccion_desplazamiento

    FROM deduplicado

    WHERE rn = 1

)

SELECT *
FROM normalizado

WHERE id_reporte_accidente IS NOT NULL