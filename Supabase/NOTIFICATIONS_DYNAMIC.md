# Notificaciones dinámicas

## Despliegue en la instalación existente

1. Ejecutar TODO `notifications_dynamic.sql` en Supabase SQL Editor. Es una
   migración transaccional y repetible sobre las migraciones ya instaladas.
   No volver a ejecutar `notifications_setup.sql` ni `notification_reminders.sql`
   después: contienen las definiciones anteriores.
2. Subir `Supabase/push-worker/worker.mjs` y desplegar ese commit en Render.
   `package.json`, secretos, puerto y `/health` no cambian.
3. Confirmar en Render que no aparece `Push cycle failed`. La nueva RPC
   `claim_notification_pushes_v2` debe existir antes de arrancar este worker.
4. Probar un evento NUEVO con dos cuentas distintas: autor administrador y
   empleado destinatario. El autor sigue excluido de sus propios avisos.
5. Comprobar título y texto en la bandeja y en el banner del teléfono.

Los triggers construyen el texto en `notificaciones_app` y el trigger existente
crea las filas de outbox por dispositivo. La nueva RPC adjunta ese texto al
reclamar la cola; no reconstruye títulos a partir de entidades eliminadas.
La RPC anterior permanece disponible durante el cambio de worker.
No se reenvía el historial ni se reescriben notificaciones antiguas.

## Reglas

- Se notifica solo al equipo involucrado y administradores, excluyendo al autor.
- Confirmar un hito incluye el nombre del actor y del hito. Completar el último
  genera también el aviso de asignación completada, cada uno con su propia clave.
- Crear o subir una asignación a prioridad `alta` genera `¡URGENTE!`. Editar otros
  campos cuando ya es Alta no repite ese aviso. Bajar y volver a subir sí lo genera.
  No se añade una marca de urgencia ni se cambia el selector Alta/Media/Baja.
- Alta prioridad genera el aviso urgente además del de creación/modificación.
- Comunicados nuevos, modificados o eliminados se notifican a toda la plantilla,
  excluyendo al autor. Marcar como leído no produce avisos.
- Registro: al insertar `perfiles`, los demás administradores reciben
  `Nuevo registro` / `Un nuevo usuario ha creado sus credenciales`.
  No se recuperan registros históricos. Si un usuario solo existe en auth.users,
  falta crear su perfil para que este evento se genere.

## Tiempo

El worker ya llama `generate_notification_reminders` en cada ciclo, aproximadamente
cada 10 segundos más la duración del lote. No hace falta otro cron para avisos.
El ping externo a `/health` no ejecuta recordatorios por sí mismo.

Se avisa durante los 15 minutos anteriores al vencimiento del siguiente hito
pendiente, tanto de campo como administrativo. El cierre usa `fecha_limite`;
si es NULL, usa la fecha del último hito. Se conserva un aviso de vencimiento
durante las 24 horas siguientes y se excluyen asignaciones completadas.
La clave por destinatario, hito/asignación, fecha y fase evita repetir avisos.
Si el último hito y el cierre coinciden, se generan ambos mensajes.

## Aprobación pendiente de implementar

La base actual no contiene un flujo de aprobación y el registro sigue libre.
Por eso no se afirma que un registro espere aprobación ni se envía `Cuenta
verificada`. Ese evento necesita un cambio real y protegido de estado por un
administrador; no debe confundirse con confirmar el correo o cambiar el rol.
No se modificó la autorización de acceso de los empleados en esta actualización.

## Swift

El transporte push no requiere cambios en Swift: ya presenta los títulos y
cuerpos enviados por APNs. Un ajuste de detalle evita mostrar un aviso de
contenido eliminado al abrir la notificación informativa de un registro nuevo.
Recompilar el iPhone solo es necesario para ese ajuste visual.

## Verificación

Ejecutar `node --test worker.test.mjs` en `Supabase/push-worker`.
Las pruebas SQL se ejecutan con Node y `PGLITE_PATH` apuntando al módulo instalado
`@electric-sql/pglite/dist/index.js`: `node Supabase/tests/notifications.test.mjs`.
No requieren secretos ni modifican la base remota.
