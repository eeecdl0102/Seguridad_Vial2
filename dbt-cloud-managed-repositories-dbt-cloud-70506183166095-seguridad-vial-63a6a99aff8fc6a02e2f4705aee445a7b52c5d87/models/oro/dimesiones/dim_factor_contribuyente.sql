

WITH factores AS (
    SELECT DISTINCT UPPER(causa_accidente) AS descripcion_factor
    FROM {{ ref('plata_accidentes') }}
    WHERE causa_accidente IS NOT NULL 
      AND UPPER(causa_accidente) != 'NO ESPECIFICADO'
)

SELECT
    ROW_NUMBER() OVER (ORDER BY descripcion_factor) AS factor_contribuyente_key,
    descripcion_factor,
    CASE
        -- Factores Humanos (Conductores, velocidad, distracciones, alcohol, inexperiencia, falta de prioridad)
        WHEN descripcion_factor ILIKE '%ALCOHOL%' 
          OR descripcion_factor ILIKE '%DROGA%' 
          OR descripcion_factor ILIKE '%DISTRACCION%' 
          OR descripcion_factor ILIKE '%TELEFONO%' 
          OR descripcion_factor ILIKE '%INEXPERIENCIA%' 
          OR descripcion_factor ILIKE '%VELOCIDAD%' 
          OR descripcion_factor ILIKE '%PRIORIDAD%' THEN 'HUMANO'
          
        -- Factores Vehiculares (Fallos mecánicos, frenos, defectos)
        WHEN descripcion_factor ILIKE '%DEFECTUOSO%' 
          OR descripcion_factor ILIKE '%FRENOS%' 
          OR descripcion_factor ILIKE '%MECANICA%' THEN 'VEHICULAR'
          
        -- Factores Ambientales / Infraestructura (Vías, clima adverso, semáforos, señales)
        WHEN descripcion_factor ILIKE '%VIA%' 
          OR descripcion_factor ILIKE '%CLIMA%' 
          OR descripcion_factor ILIKE '%SENAL%' 
          OR descripcion_factor ILIKE '%SEMAFORO%' THEN 'AMBIENTAL / INFRAESTRUCTURA'
          
        -- Cualquier otro caso no contemplado explícitamente
        ELSE 'OTRO / NO ESPECIFICADO'
    END AS categoria_factor
FROM factores