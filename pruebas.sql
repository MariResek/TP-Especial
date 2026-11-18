-- =============================================================================
-- Pruebas con los ejemplos de la consigna
-- Correr DESPUÉS de funciones.sql, una sentencia a la vez y EN ORDEN
-- (cada ejemplo depende de los anteriores).
-- Para volver a probar desde cero, volver a ejecutar funciones.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0) Verificar la importación
-- -----------------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM vehiculo)   AS vehiculos,
       (SELECT COUNT(*) FROM mecanico)   AS mecanicos,
       (SELECT COUNT(*) FROM asignacion) AS asignaciones,
       (SELECT COUNT(*) FROM orden)      AS ordenes;
-- esperado: 40 | 12 | 113 | 221


-- -----------------------------------------------------------------------------
-- 4.b) Asignaciones
-- -----------------------------------------------------------------------------
-- consulta para ver cómo está el vehículo AE512KD en cada paso
SELECT a.patente, a.legajo, a.fecha_asignacion, m.nombre, m.especialidad
FROM asignacion a JOIN mecanico m ON a.legajo = m.legajo
WHERE a.patente = 'AE512KD'
ORDER BY a.legajo;
-- esperado: 102 Juan Pérez (Motor) y 104 Lucía Fernández (Frenos)

-- ACEPTA: no tenía mecánico de Electricidad
INSERT INTO asignacion VALUES ('AE512KD', 108, '2026-11-02');

-- RECHAZA: ya tiene mecánico de Frenos (104)
INSERT INTO asignacion VALUES ('AE512KD', 105, '2026-11-02');

-- ACEPTA: reemplaza al de Frenos por otro de Frenos
UPDATE asignacion SET legajo = 105, fecha_asignacion = '2026-11-02'
WHERE patente = 'AE512KD' AND legajo = 104;

-- RECHAZA: AE512KD quedaría con dos mecánicos de Frenos (105 y 108)
UPDATE mecanico SET especialidad = 'Frenos' WHERE legajo = 108;

-- (volver a correr la consulta de AE512KD: 102 Motor, 105 Frenos, 108 Electricidad)


-- -----------------------------------------------------------------------------
-- 4.c) Órdenes
-- -----------------------------------------------------------------------------
-- consulta para ver el estado de las órdenes del ejemplo
SELECT nro_orden, patente, legajo, fecha_apertura, fecha_inicio, fecha_cierre,
       horas, estado_orden(nro_orden) AS estado
FROM orden
WHERE nro_orden IN (215, 222, 223)
ORDER BY nro_orden;

-- ACEPTA: queda 'abierta'
INSERT INTO orden (nro_orden, patente, legajo, descripcion, fecha_apertura)
VALUES (222, 'AE512KD', 105, 'Cambio de discos y pastillas', '2026-11-03');

-- ACEPTA: pasa a 'en curso'
UPDATE orden SET fecha_inicio = '2026-11-04' WHERE nro_orden = 222;

-- ACEPTA: queda 'cerrada'
UPDATE orden SET fecha_cierre = '2026-11-05', horas = 7.5 WHERE nro_orden = 222;

-- 1) RECHAZA: el mecánico 110 no está asignado a AE512KD
INSERT INTO orden (nro_orden, patente, legajo, descripcion, fecha_apertura)
VALUES (223, 'AE512KD', 110, 'Alineación y balanceo', '2026-11-03');

-- 2) RECHAZA: la orden 222 está cerrada
UPDATE orden SET horas = 5 WHERE nro_orden = 222;

-- 3) ACEPTA: se registra la orden 223 abierta para el mecánico 102...
INSERT INTO orden (nro_orden, patente, legajo, descripcion, fecha_apertura)
VALUES (223, 'AE512KD', 102, 'Cambio de aceite y filtros', '2026-11-05');

--    ...y RECHAZA comenzarla: el mecánico 102 tiene en curso la orden 215
UPDATE orden SET fecha_inicio = '2026-11-06' WHERE nro_orden = 223;

-- 4) RECHAZA: la orden 215 está en curso y no puede volver a abierta
UPDATE orden SET fecha_inicio = NULL WHERE nro_orden = 215;


-- -----------------------------------------------------------------------------
-- 4.e) Reporte (los NOTICE se ven en la salida/log, no como resultado)
-- -----------------------------------------------------------------------------
-- reporte de la consigna: 64 órdenes, 314.0 h
SELECT reporte_taller('2026-07-01', '2026-09-30');

-- período sin órdenes cerradas: no muestra nada
SELECT reporte_taller('2027-01-01', '2027-03-31');

-- RECHAZA: período invertido
SELECT reporte_taller('2026-09-30', '2026-07-01');
