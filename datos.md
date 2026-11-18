Para la importacion de datos las funciones mencionadas anteriormente se pasaron a un mismo archivo llamado funciones.sql en el mismo orden que lo indica en el informe.
Se copiaron los archivos provistos por la catedra a una carpeta simple C:\mi\carpeta\copy
Como .csv tiene la forma de asignacion plana es decir sin normalizar debimos crear una tabla temporal que almacene los datos cargados.

Luego, mediante la instrucción COPY, se importaron todos los registros del archivo CSV a dicha tabla. Se especificaron las siguientes opciones:
- FORMAT csv: ya que el archivo provisto por la catedra tiene formato CSV.
- HEADER: indica que la primera fila contiene los nombres de las columnas y no debe interpretarse como un registro.
- DELIMITER ',': se establecio que los campos están separados por comas.
- ENCODING 'UTF8': especificacion la codificación de caracteres.

Una vez importados los datos, se realizó la separación de la información en las tres tablas normalizadas: vehiculo, mecanico y asgnacion.

- VEHICULO: se insertaron las patentes, marcas y modelos mediante un SELECT DISTINCT, para evitar insertar varias veces el mismo vehículo. Esto es necesario porque un vehículo puede estar asignado a varios mecánicos y, por lo tanto, aparecer repetido en el archivo original.
- MECANICO: se insertaron los legajos, nombres y especialidades de los mecánicos, también utilizando SELECT DISTINCT. De esta manera, cada mecánico se registra una sola vez, independientemente de la cantidad de vehículos que atienda.
- ASIGNACION: se insertaron las relaciones entre vehículos y mecánicos, junto con la fecha de asignación. En este caso no fue necesario utilizar DISTINCT, ya que se considera que la combinación de patente y legajo es única en el archivo original.
El uso de DISTINCT en las dos primeras inserciones permite eliminar la redundancia generada por la estructura plana del archivo.
Finalmente, se eliminó la tabla temporal asignacion_plana ya que su objetivo era servir como estructura intermedia para la transferencia de datos.

Para el archivo orden.csv, se realizó una importación directa mediante COPY sobre la tabla ORDEN, ya que la estructura del archivo coincide con la de la tabla de destino.
Se importaron los siguientes atributos: número de orden, patente, legajo, descripción, fechas de apertura, inicio y cierre, y cantidad de horas.
Se mantuvieron las mismas opciones de configuración utilizadas para el archivo anterior (FORMAT csv, HEADER, DELIMITER ',' y ENCODING 'UTF8').

En este caso, los campos vacíos del archivo se interpretan como valores NULL, ya que podria ocurrir que haya fechas no definidas como las fechas de inicio o cierre de una orden que aún no fue completada.