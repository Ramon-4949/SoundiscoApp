# Notificaciones de SounDisco

## Estado de la implementación

La app incluye bandeja segmentada, filtros, lectura individual, actualización
Realtime con reconciliación periódica, campana con indicador de pendientes,
registro APNs y apertura del detalle tras autenticar la cuenta destinataria.

Las migraciones se prepararon y probaron localmente. No se han aplicado al
proyecto remoto. El worker autorizado está implementado en
`push-worker/worker.mjs`, con pruebas locales y guía de despliegue.
Falta configurar sus secretos y desplegarlo. No se ha enviado ningún push real.
El registro del dispositivo por sí solo no entrega notificaciones.

## Aplicación en Supabase

Ejecutar en SQL Editor, después de las migraciones existentes:

1. `notifications_setup.sql`.
2. `notification_reminders.sql`.

La primera migración instala triggers que agrupan los cambios de cada transacción.
Esto contempla las RPC existentes que reemplazan el equipo completo al editar.
También contempla operaciones realizadas directamente en las tablas.
No volver a aplicar migraciones antiguas que sustituyan las políticas nuevas.

El worker continuo invoca la segunda función automáticamente. Alternativamente
se puede programar cada minuto mediante Supabase Cron:
`select public.generate_notification_reminders();`.
Se debe habilitar Cron en el Dashboard. La migración no habilita extensiones
ni crea tareas programadas automáticamente.

Los recordatorios se generan 15 minutos antes y al vencer el horario, hasta
24 horas después. Solo se recuerda el siguiente hito pendiente de campo.
Las tareas administrativas usan fecha límite. Los recordatorios vencidos
incluyen administradores. Se deduplican por destinatario, fecha e hito.

## Destinatarios

- Creación: empleados asignados y otros administradores.
- Edición: equipo actual y otros administradores.
- Reasignación: aviso de retirada al anterior y de nueva asignación al nuevo.
- Eliminación: equipo anterior y otros administradores; el historial permanece.
- Checklist/estado/incidencias: equipo actual y administradores.
- Comunicados nuevos, editados o eliminados: toda la plantilla.
- No se notifica al autor de su propia acción.

RLS limita la lectura a `perfil_id = auth.uid()`, incluso para administradores:
cada administrador tiene su propia copia de los eventos que le corresponden.
La app no puede insertar avisos, modificar destinatarios ni acceder a tokens.
Una RPC únicamente permite marcar como leídos los avisos propios.

## Pendiente para push con la app cerrada

- El envío a APNs ya está autorizado. El contenido visible es genérico,
  sin nombres de empleados, ubicaciones ni instrucciones en la pantalla bloqueada.
- Habilitar Push Notifications para `hola.SoundiscoApp` en Apple Developer,
  y regenerar/actualizar el perfil de firma.
- Clave APNs .p8, Key ID y Team ID, solo en secretos del servidor.
- Clave service_role de Supabase, solo en secretos del servidor.
- Desplegar el worker HTTP/2 implementado en `push-worker/`.

El entitlement usa development en Debug y production en Release. La cuenta
Apple debe permitir Push Notifications. Verificar los entitlements del archivo
firmado para TestFlight/distribución.

La cola tiene leases, contador de intentos, espera exponencial y RPC reservadas
a service_role. Los destinatarios se vuelven a comprobar al reclamar trabajos.
La entrega será al menos una vez; APNs puede demorar/suprimir avisos según los
ajustes del dispositivo. La bandeja persistente es la fuente del historial.

Cerrar la app o bloquear con Face ID mantiene los avisos. Un cierre real de
sesión desregistra la instalación antes de revocar la sesión de Supabase.
Cambiar de cuenta registra la instalación para el nuevo usuario.

## Verificación

`tests/notifications.test.mjs` usa PostgreSQL embebido PGlite con datos ficticios:
`PGLITE_PATH=/ruta/al/modulo/dist/index.js node Supabase/tests/notifications.test.mjs`.
No requiere credenciales ni toca la base remota.

Tras desplegar: probar con dos empleados y dos administradores en dispositivos,
rechazo de permisos, cambio de cuenta, edición de equipo, borrado, app cerrada
y acceso a un recurso ya retirado. No se ha validado entrega real APNs.
