# Accesos y eliminacion de cuenta

## Activacion

1. Ejecuta `account_access_setup.sql` completo en SQL Editor de Supabase con el rol postgres. Depende de las migraciones actuales de notificaciones y disponibilidad.
2. Ejecuta `account_approval_auth_fix.sql`: sincroniza la aprobacion administrativa con `auth.users.email_confirmed_at` y repara cuentas ya aprobadas. Las pendientes/rechazadas no se confirman. Si existe un `pgrst.db_pre_request` personalizado, el primer script aborta sin aplicar cambios; integra ambas comprobaciones.
3. Compila e instala esta version de la app. Antes de aplicar el SQL, el acceso se bloqueara con un error de verificacion porque faltan los RPC nuevos.
4. Entra como administrador y abre Perfil > Panel de control.

Los perfiles existentes mantienen su acceso aprobado. Los registros nuevos y los usuarios de Auth sin perfil entran pendientes. Los rechazos no eliminan la cuenta; pueden aprobarse posteriormente. No hay ascenso de rol desde esta pantalla.

La revision se anuncia como aproximadamente 24 horas; el sistema no aprueba automaticamente al cumplirse ese plazo. El estado se consulta al abrir la app y cada 15 segundos en primer plano. El panel se actualiza cada 20 segundos y admite actualizar deslizando.

SounDisco no exige confirmar correo por enlace: la aprobacion del administrador autoriza el acceso. Desactiva `Confirm email` en la configuracion de Supabase Auth para que los nuevos registros reciban sesion y puedan ver la pantalla de revision y registrar su dispositivo push. Esto no omite la aprobacion administrativa. Desactivar esa opcion no repara cuentas anteriores no confirmadas; para ellas aplica el script de sincronizacion. Si Auth no devuelve sesion al registrarse, la app informa que el registro tuvo exito y regresa al login.

## Seguridad

`account_private.access` no es accesible desde clientes. Solo los RPC del administrador cambian la aprobacion. RLS limita tablas y Realtime; `public.check_account_access` protege REST y RPC, incluidos los SECURITY DEFINER. No exponer RPC adicionales que evadan esta comprobacion mediante otros protocolos.

Los pendientes pueden consultar su estado y perfil, registrar su dispositivo para avisos de revision y eliminar su cuenta. No reciben comunicados ni avisos operativos. La seleccion de responsables solo incluye aprobados y el servidor rechaza asignaciones a pendientes.

El worker existente envia los nuevos mensajes de aprobacion/rechazo; no requiere despliegue adicional en Render. Los dispositivos necesitan permiso de notificaciones para recibirlos.

## Eliminacion real

`delete_my_account()` solo actua sobre `auth.uid()`, en una transaccion. Borra el usuario de Auth y el perfil, los dispositivos y su cola push por cascada, la participacion en equipos y lecturas de comunicados. Borra avisos que identifican al perfil por destino, nombre o email. Las asignaciones y comunicados compartidos permanecen. No se promete borrar copias en backups ni texto libre que otros usuarios hayan escrito fuera del perfil.

La cuenta del ultimo administrador tambien puede eliminarse. Para mantener la administracion de la empresa, asigna otro administrador previamente desde Supabase. El usuario ve una confirmacion explicita antes de la eliminacion.

No hay avatares ni archivos de usuario en este proyecto. Si incorporas Storage o tablas con datos personales, integra su limpieza antes de publicar esas funcionalidades. Las restricciones FK desconocidas abortaran toda la transaccion en lugar de mostrar una eliminacion exitosa incompleta.

## Prueba con dos cuentas

1. Registra un empleado de prueba: debe ver el aviso de 24 horas y no el Home.
2. Desde el administrador, busca su nombre/correo/cargo y rechaza el acceso. Comprueba que pasa a Rechazadas y el empleado sigue bloqueado.
3. Apruebalo: pasa a Aprobadas, recibe el aviso y el empleado entra al Home al refrescar su estado.
4. En Perfil del empleado no aparece Panel de control. En ambos perfiles aparece Eliminar cuenta.
5. Elimina solo una cuenta de prueba. Verifica que desaparece de Authentication > Users y de perfiles y que no permite volver a iniciar sesion.

Las pruebas locales `tests/account_access.test.mjs` cubren las transiciones, permisos, idempotencia, notificaciones, asignacion y eliminacion con el esquema de prueba. La migracion no se aplica automaticamente al servidor.
