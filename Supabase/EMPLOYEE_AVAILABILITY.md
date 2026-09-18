# Disponibilidad de responsables

Ejecutar `employee_availability.sql` completo en el SQL Editor de Supabase,
despues de las migraciones de CRUD y `administrative_assignment_location_fix.sql`.
Esta migracion es necesaria antes de usar el selector nuevo en la app.

- Campo: desde la fecha/hora del primer hito hasta la del ultimo. Las fechas
  deben seguir el orden del itinerario. Un unico hito reserva ese instante.
- Administrativa: desde `fecha_creacion` hasta `fecha_limite`, sin ubicacion ni hitos.
- Los extremos del intervalo se consideran ocupados. Dos asignaciones que
  coinciden exactamente al terminar/empezar tambien entran en conflicto.
- Completadas y eliminadas liberan al empleado. Las vencidas mantienen su
  intervalo historico, sin ampliarlo indefinidamente.
- Los administradores consultan disponibilidad por RPC. Los empleados no
  pueden consultar reservas de otros usuarios.
- Crear, editar, reasignar y cambiar hitos actualiza reservas al final de la
  transaccion. La restriccion de exclusion de PostgreSQL impide cruces tambien
  entre escrituras concurrentes. Un conflicto cancela la transaccion completa.
- El selector excluye la asignacion editada. Consultar o confirmar no reserva:
  el guardado realiza la comprobacion definitiva.

Los filtros muestran los cargos reales de los perfiles. Si `perfiles.cargo`
esta vacio, se usa el cargo de los metadatos de registro; sin ninguno de ellos,
se muestra el rol general. No se inventan especialidades ni fotos de perfil.

La migracion incorpora asignaciones existentes. Si alguna carece de fechas
validas o tiene responsables con cruces, se revierte e indica su UUID para
corregirla antes de volver a ejecutar el archivo. No elimina asignaciones ni
quita responsables automaticamente. Los hitos antiguos cuya hora se hubiera
perdido deben corregirse desde el editor; no se puede reconstruir esa hora.

Verificacion local:

```sh
PGLITE_PATH=/ruta/a/pglite/dist/index.js node Supabase/tests/employee_availability.test.mjs
```

La prueba usa las migraciones reales de CRUD y notificaciones, comprueba
intervalos de ambos tipos, cruces, edicion, liberacion de reservas,
atomicidad, permisos y reaplicacion de la migracion. PGlite no simula dos
sesiones concurrentes; la exclusion es la garantia de concurrencia del motor.

Referencia: https://www.postgresql.org/docs/current/rangetypes.html#RANGETYPES-CONSTRAINT
