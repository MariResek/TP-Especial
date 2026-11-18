# ACA ESTA TODO LO DEL WORD, CON ALGUNOS DETALLES CAMBIADOS QUE ADJUNTE EN dificultades.md
# Les dejo el link del informe real a presentar que estoy escribiendo a mano con mucho amor

https://docs.google.com/document/d/1bU09rAHNVG929kJGhFLkLhJZLpwCds_dgv5I3mfij9o/edit?usp=sharing


# 3.a. Análisis de preservación de dependencias funcionales

Se parte de la relación original:

```
ASIGNACION_PLANA(patente, marca, modelo, legajo, nombre_mecanico, especialidad, fecha_asignacion)
```

Con el siguiente conjunto de dependencias funcionales:

```
F = {
    patente → marca, modelo
    legajo → nombre_mecanico, especialidad
    patente, especialidad → legajo, fecha_asignacion
}
```

La descomposición en BCNF propuesta por la cátedra es:

- VEHICULO(patente, marca, modelo)
- MECANICO(legajo, nombre_mecanico, especialidad)
- ASIGNACION(patente, legajo, fecha_asignacion)

Para determinar si la descomposición preserva las dependencias funcionales, analizamos cuáles pueden garantizarse a partir de las relaciones resultantes.

### 1. Primera dependencia funcional

`patente → marca, modelo`

Esta dependencia se preserva, ya que todos los atributos involucrados pertenecen a la relación VEHICULO, donde patente es clave primaria.

### 2. Segunda dependencia funcional

`legajo → nombre_mecanico, especialidad`

Esta dependencia se preserva, ya que todos los atributos involucrados pertenecen a la relación MECANICO, donde legajo es clave primaria.

### 3. Tercera dependencia funcional

`patente, especialidad → legajo, fecha_asignacion`

Para verificar si esta dependencia se preserva, consideramos el conjunto G de dependencias funcionales garantizadas por las relaciones descompuestas:

```
G = {
    patente → marca, modelo
    legajo → nombre_mecanico, especialidad
    patente, legajo → fecha_asignacion
}
```

Calculamos la clausura de {patente, especialidad} respecto de G.

Inicialmente:

X⁺ = {patente, especialidad}

Aplicando `patente → marca, modelo`:

X⁺ = {patente, especialidad, marca, modelo}

No pueden aplicarse otras dependencias de G, ya que no disponemos del atributo legajo.

Por lo tanto:

X⁺ = {patente, especialidad, marca, modelo}

Como la clausura no contiene los atributos legajo ni fecha_asignacion, la dependencia funcional original no puede deducirse a partir de G.

En consecuencia, la tercera dependencia funcional **no se preserva**.

Esto significa que, aunque se respeten las claves primarias y foráneas de las relaciones descompuestas, podría asignarse más de un mecánico de la misma especialidad a un mismo vehículo.

### Conclusión

La descomposición en BCNF propuesta por la cátedra no preserva todas las dependencias funcionales de F.

Se preservan las siguientes dependencias:

- `patente → marca, modelo`
- `legajo → nombre_mecanico, especialidad`

En cambio, se pierde:

- `patente, especialidad → legajo, fecha_asignacion`

Dado que el taller desea mantener la descomposición en BCNF, será necesario implementar triggers que garanticen el cumplimiento de la dependencia funcional perdida.

---

## Creación de tablas

```sql
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
```

## Trigger de validación de asignaciones

```sql
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
```

## Trigger de validación de cambio de especialidad

```sql
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
```

## 4.c. Trigger de validación de órdenes

```sql
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
```

## 4.d. Importación de los datos

```sql
-- asignacion.csv tiene la forma de ASIGNACION_PLANA (sin normalizar):
-- se carga primero en una tabla temporal con sus mismas columnas
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

-- un vehículo aparece una vez por cada mecánico asignado, y un mecánico una vez
-- por cada vehículo que atiende: se eliminan los repetidos con DISTINCT.
-- Por patente → marca, modelo y legajo → nombre_mecanico, especialidad, cada
-- patente (y cada legajo) aparece siempre con los mismos datos.
INSERT INTO vehiculo (patente, marca, modelo)
SELECT DISTINCT patente, marca, modelo
FROM asignacion_plana;

INSERT INTO mecanico (legajo, nombre, especialidad)
SELECT DISTINCT legajo, nombre_mecanico, especialidad
FROM asignacion_plana;

-- (patente, legajo) es clave en la planilla, así que no hay repetidos
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
```

## 4.e. Función reporte_taller

```sql
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
```

---

## Dificultades encontradas y cómo se resolvieron

**1. La dependencia perdida también se podía violar desde MECANICO.**
Al principio solo habíamos hecho el trigger sobre ASIGNACION (INSERT y UPDATE de patente o legajo), porque pensamos que la única forma de que un vehículo quedara con dos mecánicos de la misma especialidad era asignándole uno nuevo. Pero la especialidad no está en ASIGNACION sino en MECANICO, así que si un mecánico cambia de especialidad, todos los vehículos que atiende pueden quedar en conflicto sin que se toque ASIGNACION (es el caso de `UPDATE mecanico SET especialidad = 'Frenos' WHERE legajo = 108`, que la consigna pide rechazar). Lo resolvimos con un segundo trigger, `AFTER UPDATE OF especialidad ON mecanico`, que solo se ejecuta si la especialidad realmente cambia (`WHEN (old.especialidad <> new.especialidad)`) y que cuenta cuántos vehículos quedarían con dos mecánicos de esa especialidad.

Las demás operaciones no pueden violar la dependencia: un INSERT en MECANICO no tiene vehículos asignados todavía, un DELETE no puede generar duplicados, cambiar el legajo de un mecánico asignado (o la patente de un vehículo asignado) ya lo rechaza la clave foránea, y cambiar la fecha_asignacion no cambia qué mecánicos están asignados.

**2. Distinguir entre INSERT y UPDATE en el trigger de órdenes.**
Algunas reglas del punto 4.c solo tienen sentido en un UPDATE (una orden cerrada no se puede modificar, una orden en curso no puede volver a abierta) y necesitan la variable old, que en un INSERT no está inicializada y su uso da error. Como en clase vimos que el trigger function puede recibir parámetros en TG_ARGV, creamos dos triggers (uno AFTER INSERT y otro AFTER UPDATE) que llaman a la misma función pasándole 'INSERT' o 'UPDATE', y la función consulta TG_ARGV[0] para saber qué controlar. También separamos en dos IF la condición que decide si hay que controlar la asignación, para no leer old cuando la operación es un INSERT.

**3. Saber si un SELECT INTO encontró o no una tupla.**
Para verificar que el mecánico esté asignado al vehículo, primero pensamos en chequear si la variable quedaba en NULL, pero como vimos en la clase 14, un cursor implícito que no encuentra tuplas no lanza excepción y deja las variables en NULL, igual que si la tupla existiera con valores NULL. Por eso usamos `IF NOT FOUND`. En cambio, cuando usamos funciones de agregación (MIN, COUNT) sí chequeamos NULL o 0, porque una función de agregación siempre devuelve una tupla.

**4. Controlar que un mecánico tenga una sola orden en curso.**
Si el trigger fuera BEFORE, en un UPDATE que pone varias órdenes del mismo mecánico en curso en una sola sentencia, cada fila no vería los cambios de las otras. Usando AFTER, cada control se hace sobre el estado final de la tabla. Lo mismo aplica a los triggers de ASIGNACION y MECANICO.

**5. Conservar el historial de órdenes.**
ORDEN no tiene clave foránea a ASIGNACION para que las órdenes viejas se conserven aunque el vehículo cambie de mecánico. Si el trigger controlara la asignación en cualquier UPDATE, una orden registrada antes de un cambio de mecánico no se podría cerrar. Por eso el control solo se hace al registrar la orden o si un UPDATE cambia la patente o el legajo.

**6. Importar un archivo sin normalizar.**
asignacion.csv tiene la forma de ASIGNACION_PLANA, así que no se puede cargar directo en las tablas. Lo cargamos en una tabla temporal y desde ahí repartimos los datos. Como un vehículo aparece una vez por cada mecánico asignado (y un mecánico una vez por cada vehículo), insertar directo violaba las claves primarias; lo resolvimos con SELECT DISTINCT, que alcanza porque por las dependencias patente → marca, modelo y legajo → nombre_mecanico, especialidad cada patente y cada legajo aparecen siempre con los mismos datos. Además, el orden de carga importa: primero VEHICULO y MECANICO, después ASIGNACION y por último ORDEN, por las claves foráneas y porque el trigger de órdenes consulta ASIGNACION.
