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
