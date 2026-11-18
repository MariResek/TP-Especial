-- =============================================================================
-- Base de Datos I - Trabajo Práctico Especial - 2do Cuatrimestre 2026
-- funciones.sql
-- =============================================================================

-- Borrado previo, para poder ejecutar el script más de una vez
DROP TABLE IF EXISTS orden, asignacion, mecanico, vehiculo CASCADE;

-- =============================================================================
-- 4.a) Creación de las tablas
-- =============================================================================

CREATE TABLE vehiculo
(
    patente   VARCHAR(10)  NOT NULL,
    marca     VARCHAR(30)  NOT NULL,
    modelo    VARCHAR(30)  NOT NULL,
    PRIMARY KEY (patente)
);

CREATE TABLE mecanico
(
    legajo        INT          NOT NULL,
    nombre        VARCHAR(50)  NOT NULL,
    especialidad  VARCHAR(15)  NOT NULL,
    PRIMARY KEY (legajo),
    CONSTRAINT check_especialidad
        CHECK (especialidad IN ('Motor', 'Frenos', 'Electricidad', 'Suspensión'))
);

CREATE TABLE asignacion
(
    patente           VARCHAR(10)  NOT NULL,
    legajo            INT          NOT NULL,
    fecha_asignacion  DATE         NOT NULL,
    PRIMARY KEY (patente, legajo),
    FOREIGN KEY (patente) REFERENCES vehiculo,
    FOREIGN KEY (legajo)  REFERENCES mecanico
);

CREATE TABLE orden
(
    nro_orden       INT           NOT NULL,
    patente         VARCHAR(10)   NOT NULL,
    legajo          INT           NOT NULL,
    descripcion     VARCHAR(100)  NOT NULL,
    fecha_apertura  DATE          NOT NULL,
    fecha_inicio    DATE,
    fecha_cierre    DATE,
    horas           DECIMAL(5,1),
    PRIMARY KEY (nro_orden),
    FOREIGN KEY (patente) REFERENCES vehiculo,
    FOREIGN KEY (legajo)  REFERENCES mecanico,

    CONSTRAINT check_inicio
        CHECK (fecha_inicio IS NULL OR fecha_inicio >= fecha_apertura),

    CONSTRAINT check_cierre
        CHECK (fecha_cierre IS NULL
               OR (fecha_inicio IS NOT NULL AND fecha_cierre >= fecha_inicio)),

    CONSTRAINT check_horas
        CHECK ((fecha_cierre IS NULL AND horas IS NULL)
               OR (fecha_cierre IS NOT NULL AND horas IS NOT NULL AND horas > 0))
);

-- =============================================================================
-- 4.b) Trigger: asignación de mecánicos (INSERT / UPDATE en ASIGNACION)
-- =============================================================================

CREATE OR REPLACE FUNCTION valida_asignacion() RETURNS TRIGGER
AS $$
DECLARE
    v_especialidad  mecanico.especialidad%TYPE;
    v_otro          mecanico.legajo%TYPE;
BEGIN
    -- especialidad del mecánico que se está asignando
    SELECT especialidad INTO v_especialidad
    FROM mecanico
    WHERE legajo = new.legajo;

    -- ¿el vehículo tiene OTRO mecánico asignado de esa misma especialidad?
    -- (MIN siempre devuelve una tupla: NULL si no hay ninguno)
    SELECT MIN(a.legajo) INTO v_otro
    FROM asignacion a JOIN mecanico m ON a.legajo = m.legajo
    WHERE a.patente = new.patente
      AND m.especialidad = v_especialidad
      AND a.legajo <> new.legajo;

    IF v_otro IS NOT NULL THEN
        RAISE EXCEPTION 'El vehículo % ya tiene asignado un mecánico de % (legajo %)',
                        new.patente, v_especialidad, v_otro;
    END IF;

    RETURN NULL;   -- trigger AFTER: el valor retornado se ignora
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_valida_asignacion
AFTER INSERT OR UPDATE OF patente, legajo ON asignacion
FOR EACH ROW
EXECUTE PROCEDURE valida_asignacion();

-- =============================================================================
-- 4.b) Trigger: cambio de especialidad (UPDATE en MECANICO)
-- =============================================================================

CREATE OR REPLACE FUNCTION valida_cambio_especialidad() RETURNS TRIGGER
AS $$
DECLARE
    v_cant     INT;
    v_patente  vehiculo.patente%TYPE;
    v_otro     mecanico.legajo%TYPE;
BEGIN
    SELECT COUNT(DISTINCT a.patente), MIN(a.patente) INTO v_cant, v_patente
    FROM asignacion a JOIN mecanico m ON a.legajo = m.legajo
    WHERE a.patente IN (SELECT patente
                        FROM asignacion
                        WHERE legajo = new.legajo)
      AND a.legajo <> new.legajo
      AND m.especialidad = new.especialidad;

    IF v_cant > 0 THEN
        SELECT MIN(a.legajo) INTO v_otro
        FROM asignacion a JOIN mecanico m ON a.legajo = m.legajo
        WHERE a.patente = v_patente
          AND a.legajo <> new.legajo
          AND m.especialidad = new.especialidad;

        RAISE EXCEPTION 'No se puede cambiar la especialidad del mecánico % a %: % vehículo(s) quedarían con dos mecánicos de % (por ejemplo, el vehículo % con los legajos % y %)',
                        new.legajo, new.especialidad, v_cant, new.especialidad,
                        v_patente, v_otro, new.legajo;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_valida_especialidad
AFTER UPDATE OF especialidad ON mecanico
FOR EACH ROW
WHEN (old.especialidad <> new.especialidad)
EXECUTE PROCEDURE valida_cambio_especialidad();

-- =============================================================================
-- 4.c) Validación de órdenes
-- =============================================================================

CREATE OR REPLACE FUNCTION estado_orden(p_nro orden.nro_orden%TYPE) RETURNS VARCHAR
AS $$
DECLARE
    v_inicio  orden.fecha_inicio%TYPE;
    v_cierre  orden.fecha_cierre%TYPE;
BEGIN
    SELECT fecha_inicio, fecha_cierre INTO v_inicio, v_cierre
    FROM orden
    WHERE nro_orden = p_nro;

    IF NOT FOUND THEN
        RETURN NULL;
    ELSIF v_cierre IS NOT NULL THEN
        RETURN 'cerrada';
    ELSIF v_inicio IS NOT NULL THEN
        RETURN 'en curso';
    ELSE
        RETURN 'abierta';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- el trigger function recibe en TG_ARGV[0] la operación que lo disparó
-- ('INSERT' o 'UPDATE'), porque la variable old sólo existe en los UPDATE
CREATE OR REPLACE FUNCTION valida_orden() RETURNS TRIGGER
AS $$
DECLARE
    v_legajo     asignacion.legajo%TYPE;
    v_otra       orden.nro_orden%TYPE;
    v_controlar  BOOLEAN;
BEGIN
    IF TG_ARGV[0] = 'UPDATE' THEN
        -- una orden cerrada no puede modificarse (se mira el estado ANTERIOR)
        IF old.fecha_cierre IS NOT NULL THEN
            RAISE EXCEPTION 'La orden % está cerrada y no puede modificarse',
                            old.nro_orden;
        END IF;

        -- una orden en curso no puede volver a estar abierta
        IF old.fecha_inicio IS NOT NULL AND new.fecha_inicio IS NULL THEN
            RAISE EXCEPTION 'La orden % está en curso y no puede volver a estar abierta',
                            old.nro_orden;
        END IF;
    END IF;

    -- el mecánico tiene que estar asignado al vehículo: se controla al registrar
    -- la orden, o si un UPDATE cambia la patente o el legajo. No se controla en
    -- los demás UPDATE, para que una orden siga avanzando aunque después el
    -- vehículo haya cambiado de mecánico.
    -- (en un INSERT no se puede usar old, por eso se separa en dos IF)
    IF TG_ARGV[0] = 'INSERT' THEN
        v_controlar := TRUE;
    ELSIF new.patente <> old.patente OR new.legajo <> old.legajo THEN
        v_controlar := TRUE;
    ELSE
        v_controlar := FALSE;
    END IF;

    IF v_controlar THEN
        -- cursor implícito: (patente, legajo) es clave de ASIGNACION
        SELECT legajo INTO v_legajo
        FROM asignacion
        WHERE patente = new.patente
          AND legajo = new.legajo;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'El mecánico % no está asignado al vehículo %',
                            new.legajo, new.patente;
        END IF;
    END IF;

    -- un mecánico no puede tener más de una orden en curso a la vez
    IF estado_orden(new.nro_orden) = 'en curso' THEN
        SELECT MIN(nro_orden) INTO v_otra
        FROM orden
        WHERE legajo = new.legajo
          AND nro_orden <> new.nro_orden
          AND estado_orden(nro_orden) = 'en curso';

        IF v_otra IS NOT NULL THEN
            RAISE EXCEPTION 'El mecánico % ya tiene en curso la orden %',
                            new.legajo, v_otra;
        END IF;
    END IF;

    RETURN NULL;   -- trigger AFTER: el valor retornado se ignora
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_valida_orden_insert
AFTER INSERT ON orden
FOR EACH ROW
EXECUTE PROCEDURE valida_orden('INSERT');

CREATE TRIGGER tr_valida_orden_update
AFTER UPDATE ON orden
FOR EACH ROW
EXECUTE PROCEDURE valida_orden('UPDATE');

-- =============================================================================
-- 4.d) Importación de los datos
-- =============================================================================


CREATE TEMPORARY TABLE asignacion_plana
(
    patente           VARCHAR(10),
    marca             VARCHAR(30),
    modelo            VARCHAR(30),
    legajo            INT,
    nombre_mecanico   VARCHAR(50),
    especialidad      VARCHAR(15),
    fecha_asignacion  DATE
);

COPY asignacion_plana
FROM 'C:/Users/mrese/OneDrive/Escritorio/INFORMATICA/BD/TP-Especial/copy/asignacion.csv'
WITH (FORMAT csv, HEADER, DELIMITER ',', ENCODING 'UTF8');


INSERT INTO vehiculo (patente, marca, modelo)
SELECT DISTINCT patente, marca, modelo
FROM asignacion_plana;

INSERT INTO mecanico (legajo, nombre, especialidad)
SELECT DISTINCT legajo, nombre_mecanico, especialidad
FROM asignacion_plana;


INSERT INTO asignacion (patente, legajo, fecha_asignacion)
SELECT patente, legajo, fecha_asignacion
FROM asignacion_plana;

DROP TABLE asignacion_plana;

-- orden.csv se importa directo sobre ORDEN (después de ASIGNACION, porque el
-- trigger de órdenes controla que el mecánico esté asignado al vehículo).
-- Los campos vacíos se cargan como NULL.
COPY orden (nro_orden, patente, legajo, descripcion, fecha_apertura,
            fecha_inicio, fecha_cierre, horas)
FROM 'C:/Users/mrese/OneDrive/Escritorio/INFORMATICA/BD/TP-Especial/copy/orden.csv'
WITH (FORMAT csv, HEADER, DELIMITER ',', ENCODING 'UTF8');


-- =============================================================================
-- 4.e) Función reporte_taller
-- =============================================================================

CREATE OR REPLACE FUNCTION reporte_taller(p_desde DATE, p_hasta DATE) RETURNS VOID
AS $$
DECLARE
    v_rec           RECORD;
    v_especialidad  mecanico.especialidad%TYPE;   -- especialidad que se está listando
    v_nombre        VARCHAR(50);
    v_sub_cant      INT := 0;
    v_sub_horas     DECIMAL(10,1) := 0;
    v_tot_cant      INT := 0;
    v_tot_horas     DECIMAL(10,1) := 0;

    -- un renglón por mecánico con órdenes cerradas en el período, ordenados por
    -- especialidad y, dentro de cada una, por horas (mayor a menor) y legajo
    c_reporte CURSOR FOR
        SELECT m.especialidad, m.legajo, m.nombre,
               COUNT(*) AS cant_ordenes, SUM(o.horas) AS total_horas
        FROM orden o JOIN mecanico m ON o.legajo = m.legajo
        WHERE o.fecha_cierre BETWEEN p_desde AND p_hasta
        GROUP BY m.especialidad, m.legajo, m.nombre
        ORDER BY m.especialidad, total_horas DESC, m.legajo;
BEGIN
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'Período inválido: la fecha desde (%) es posterior a la fecha hasta (%)',
                        p_desde, p_hasta;
    END IF;

    OPEN c_reporte;
    LOOP
        FETCH c_reporte INTO v_rec;
        EXIT WHEN NOT FOUND;

        -- el encabezado se muestra recién cuando aparece la primera fila,
        -- así un período sin órdenes cerradas no muestra nada
        IF v_especialidad IS NULL THEN
            RAISE NOTICE '======== REPORTE DE ÓRDENES CERRADAS ========';
            RAISE NOTICE '   Período: % a %', p_desde, p_hasta;
        END IF;

        -- cambio de especialidad: subtotal de la anterior y encabezado de la nueva
        IF v_especialidad IS NULL OR v_rec.especialidad <> v_especialidad THEN
            IF v_especialidad IS NOT NULL THEN
                RAISE NOTICE '   -- subtotal %: % órdenes, % h',
                             v_especialidad, v_sub_cant, v_sub_horas;
                v_sub_cant := 0;
                v_sub_horas := 0;
            END IF;
            RAISE NOTICE '';
            RAISE NOTICE '== Especialidad: % ==', v_rec.especialidad;
            v_especialidad := v_rec.especialidad;
        END IF;

        -- se completa el nombre con espacios para que las columnas queden alineadas
        v_nombre := v_rec.nombre;
        WHILE LENGTH(v_nombre) < 18 LOOP
            v_nombre := v_nombre || ' ';
        END LOOP;

        RAISE NOTICE '   [%] % % órdenes   % h',
                     v_rec.legajo, v_nombre, v_rec.cant_ordenes, v_rec.total_horas;

        v_sub_cant  := v_sub_cant  + v_rec.cant_ordenes;
        v_sub_horas := v_sub_horas + v_rec.total_horas;
        v_tot_cant  := v_tot_cant  + v_rec.cant_ordenes;
        v_tot_horas := v_tot_horas + v_rec.total_horas;
    END LOOP;
    CLOSE c_reporte;

    -- subtotal de la última especialidad y total general (solo si hubo filas)
    IF v_especialidad IS NOT NULL THEN
        RAISE NOTICE '   -- subtotal %: % órdenes, % h',
                     v_especialidad, v_sub_cant, v_sub_horas;
        RAISE NOTICE '';
        RAISE NOTICE '======== TOTAL: % órdenes, % h ========', v_tot_cant, v_tot_horas;
    END IF;
END;
$$ LANGUAGE plpgsql;
