# Contenido vinculado a su administrador creador

Estado: implementado y probado localmente; no aplicado en produccion.

## Regla

Cada asignacion y comunicado guarda `created_by`, obtenido de la sesion por el servidor. Un admin solo consulta y gestiona sus propios registros, aunque este asignado como colaborador en un evento creado por otro admin. No puede indicar otro creador ni cambiarlo despues. Las relaciones con hitos, notas, reportes y metricas siguen esa misma asignacion.

Los empleados siguen viendo sus asignaciones y los comunicados generales. La lista de cuentas, la seleccion de empleados y los avisos de registro conservan su alcance compartido. La disponibilidad sigue evitando solapamientos entre todos los administradores, pero oculta los horarios concretos de reservas ajenas. **No es un aislamiento completo de datos personales ni un entorno demo separado.** No entregar un admin a un tercero suponiendo que tampoco podra ver la lista de empleados.

Las notificaciones de asignaciones y comunicados destinadas a administradores se filtran antes de entrar en las colas iOS/Android. Los empleados conservan sus avisos actuales. Las notificaciones personales de cuenta no cambian. Se conserva un registro privado del creador tras eliminar contenido para comprobar cancelaciones o avisos retrasados.

## Activacion

1. Conservar un respaldo o punto de restauracion y probar primero en staging si esta disponible.
2. El usuario confirmo que todas las asignaciones y comunicados antiguos fueron creados por `yankee_admin@gmail.com`. El script ya incluye ese correo como creador historico; se verifico en lectura que la cuenta existe, tiene rol `admin` y acceso aprobado. No es necesario editarlo para esta instalacion.
3. Ejecutar completo `Supabase/admin_content_ownership.sql` como `postgres` desde SQL Editor. Si hay registros anteriores sin creador, el script se detiene y revierte la transaccion en lugar de ocultarlos o asignarlos a una persona incorrecta.
4. Cerrar sesion y volver a entrar con dos administradores. Crear un evento y un comunicado con cada uno. Confirmar que ninguno ve, edita o borra los del otro; probar tambien con un empleado asignado.
5. Comprobar confirmaciones/notas y entrega push en telefonos reales. La prueba local comprueba las colas, no APNs/FCM ni PostgREST en el proyecto desplegado.

El script ya incluye esta configuracion local a la transaccion:

```sql
set local soundisco.legacy_owner_email='yankee_admin@gmail.com';
```

Ese ajuste se usa una sola vez para rellenar la nueva columna mediante su valor inicial, sin disparar cambios de negocio ni avisos por cada registro antiguo. No determina el autor de las creaciones futuras: cada nuevo registro utiliza la cuenta que inicia sesion. No reutilizar este correo en otro proyecto sin confirmar su creador historico. Si hubiera varios creadores historicos, se necesitaria un mapeo por ID antes de activar las restricciones.

El cambio es compatible con los RPC y payloads actuales: no requiere volver a compilar iOS/Android ni desplegar el worker de Render. No se crea ningun usuario ni se cambia su rol, aprobacion o contrasena. No ejecutarlo junto con borradores anteriores de espacios demo, que fueron descartados.

## Detalles y limites

- El script es transaccional, repetible y tiene un limite de espera de bloqueo de cinco segundos. No elimina asignaciones ni comunicados existentes.
- Anade politicas RLS restrictivas a las tablas de contenido, utiliza la vista con `security_invoker` y acota los RPC administrativos que antes consultaban o modificaban datos globales.
- Conserva el flujo actual de SLA, evaluacion de confirmaciones, validaciones y reservas. Las funciones originales de confirmar/deshacer se guardan como auxiliares privados; las funciones publicas comprueban acceso antes de delegar.
- Retira notificaciones administrativas anteriores que no corresponden al creador y sus trabajos push pendientes por cascada. Los avisos ya entregados al telefono no pueden retirarse.
- El UUID del creador no lleva una FK con borrado en cascada: borrar su cuenta no elimina el trabajo compartido ni transfiere su contenido automaticamente a otro admin. Los colaboradores conservan su acceso. La reasignacion de responsabilidad por cierre de una cuenta requiere una operacion administrativa explicita fuera de la app.
- No hay migracion remota ejecutada por este cambio. Una ejecucion local exitosa no confirma la configuracion del servicio desplegado.
- Una migracion futura que reemplace estos RPC, cambie RLS o modifique las confirmaciones debe integrar esta regla. No volver a ejecutar scripts antiguos de permisos o confirmacion sin revisar sus efectos sobre el aislamiento por creador y los auxiliares privados.

## Pruebas

La suite `Supabase/tests/admin_content_ownership.test.mjs` usa PostgreSQL/PGlite y una instantanea de definiciones del esquema auditado en `fixtures/admin_ownership_schema.json`. No contiene filas de produccion ni contrasenas. Auth esta reducido a las columnas utilizadas por estos RPC.

Con `@electric-sql/pglite@0.3.14` instalado fuera del proyecto:

```sh
PGLITE_PATH=file:///ruta/node_modules/@electric-sql/pglite/dist/index.js node Supabase/tests/admin_content_ownership.test.mjs
```

Resultado local: 67 comprobaciones correctas. Cubren instalacion repetida, validacion del creador historico confirmado, consultas directas y RPC, estadisticas, autores falsificados, edicion/borrado ajeno, empleados compartidos, reportes, confirmaciones, colas push, identificadores reutilizados y borrado de cuenta. La cuenta de Auth del test tiene UUID y datos sinteticos; utiliza el correo configurado para verificar el script sin modificarlo.

Tambien pasaron las suites existentes `app_store_safety.test.mjs` y `assigned_admin_notifications.test.mjs` con sus esquemas propios. La suite antigua `milestone_collaborators.test.mjs` se detiene al instalar `notification_reminders.sql` porque su esquema aun no contiene `public.hitos_colaboradores`; ocurre antes de cargar esta funcionalidad. No se cambio esa suite ni sus migraciones en este trabajo.

Referencia: [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security).
