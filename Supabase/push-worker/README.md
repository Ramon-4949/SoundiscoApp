# Worker APNs y FCM

Node.js 22. Ejecutar en un servidor con salida HTTPS a Supabase, Google y HTTP/2 a APNs.
No se ejecuta dentro de la app iOS. En Render se despliega como Web Service;
Express escucha en `0.0.0.0:$PORT` y expone `/health`.

Aplicar primero notifications_setup.sql y notification_reminders.sql, y después
notifications_dynamic.sql ANTES de desplegar esta versión del worker.
Para Android, ejecutar también `android_push.sql` de este directorio en el SQL
Editor de Supabase. Es transaccional e idempotente. Añade su propio trigger sin
reemplazar el de iOS ni los textos de las notificaciones. No reenvía el historial.
Configurar secretos del servicio:

- SUPABASE_URL: https://gsrwfgpyflwozxzizmnv.supabase.co
- SUPABASE_SERVICE_ROLE_KEY: clave secreta `sb_secret_...` o `service_role` heredada;
  nunca la publishable.
- APNS_TEAM_ID: identificador del equipo Apple Developer.
- APNS_BUNDLE_ID: hola.SoundiscoApp.
- APNS_SANDBOX_KEY_ID: identificador de una clave APNs restringida a Sandbox.
- APPLE_SANDBOX_P8_KEY: contenido completo y multilinea de esa clave Sandbox.
- APNS_PRODUCTION_KEY_ID: identificador de una clave APNs restringida a Production.
- APPLE_PRODUCTION_P8_KEY: contenido completo y multilinea de esa clave Production.
- PORT: lo asigna Render automáticamente; no es necesario configurarlo.
- GOOGLE_APPLICATION_CREDENTIALS: ruta absoluta al JSON de una cuenta de servicio
  del proyecto Firebase de la app Android. En Render, crear un Secret File llamado
  `firebase-service-account.json` y establecer esta variable a
  `/etc/secrets/firebase-service-account.json`. Esta variable es una ruta, no el
  contenido JSON. Nunca añadir el archivo al repositorio.

Habilitar Firebase Cloud Messaging API (HTTP v1) en ese proyecto y dar a la cuenta
de servicio permiso de envío, por ejemplo el rol Firebase Cloud Messaging API Admin
(`roles/firebasecloudmessaging.admin`). Se inicializa una sola instancia de Firebase
Admin con Application Default Credentials. Referencias:
[Firebase Admin](https://firebase.google.com/docs/admin/setup) y
[errores FCM](https://firebase.google.com/docs/cloud-messaging/error-codes).

`APNS_KEY_ID` y `APPLE_P8_KEY` siguen aceptándose como alias de las dos variables
Sandbox para no interrumpir el entorno de desarrollo existente. Production siempre
requiere sus propias variables; una llave restringida a Sandbox produce
`BadEnvironmentKeyInToken` al enviar a un dispositivo instalado desde TestFlight.

Instalación reproducible: `pnpm install --frozen-lockfile` (pnpm 11).
También se admite `npm install`; el lockfile versionado es el de pnpm.
Arranque continuo: `npm start`.
Ejecución de un lote: `node worker.mjs --once`.
Pruebas sin servicios externos: `pnpm test` y `pnpm test:sql`.
Las pruebas SQL usan PGlite como dependencia de desarrollo, sin tocar Supabase.

El servicio debe mantenerse activo mediante el supervisor de la plataforma con
reinicio automático. Dos bucles independientes comparten el mismo cliente RPC de
Supabase: APNs reclama hasta 50 envíos y FCM hasta 20, con un máximo de 5 envíos
simultáneos por plataforma. Solo el bucle APNs genera los recordatorios comunes;
los triggers los distribuyen a ambas colas. Un fallo en un lote no detiene el otro
bucle. Cada envío FCM tiene un límite de espera de 20 segundos. No es necesario Cron adicional mientras
el worker continuo esté activo. Un planificador externo puede usar --once cada
minuto; debe admitir la duración completa del lote y acceso a los secretos.

Supabase controla exclusión mediante leases de 5 minutos y reintentos con espera
exponencial hasta 8 intentos. Un HTTP 200 de APNs marca aceptación por Apple,
no garantiza que el usuario vea el aviso. Un 410 Unregistered retira el dispositivo.
Los errores de red o configuración no borran tokens. Tras 8 intentos, revisar
last_error de la cola privada desde SQL Editor y corregir antes de reintentar.
FCM elimina únicamente tokens rechazados con `messaging/registration-token-not-registered`
o `messaging/invalid-registration-token`. Errores de credenciales, proyecto, payload
o transporte conservan el registro. Los logs incluyen códigos de error, nunca
mensajes completos del SDK, claves o tokens.

`/health` devuelve HTTP 200 solo después de un ciclo correcto de ambos bucles,
si siguen activos y han avanzado en los últimos cinco minutos. Devuelve HTTP 503
durante el arranque, ante fallos de ciclo o si alguno se detiene. Configurar
`/health` como Health Check Path en Render. Una cola vacía es saludable; el estado
no certifica entrega, permisos del teléfono ni credenciales FCM si no hubo envíos.
Un rechazo de un dispositivo se registra por envío sin detener el bucle.

La entrega es al menos una vez: si Apple acepta y falla el registro en Supabase,
puede repetirse un envío. apns-collapse-id agrupa reintentos del mismo aviso.
La bandeja conserva el historial aunque el dispositivo rechace notificaciones.

El payload usa `title` y `body` generados por los triggers y devueltos por
`claim_notification_pushes_v2`. Incluye los nombres de empleados, hitos,
asignaciones y asuntos de comunicados que correspondan al evento autorizado.
No incluye ubicaciones ni instrucciones. Conserva notification_id y recipient_id
como metadatos de navegación; no se registran textos, tokens ni secretos en logs.
Título y cuerpo se limitan a 120 y 500 caracteres Unicode respectivamente.
La guía de actualización está en `../NOTIFICATIONS_DYNAMIC.md`.

Las pruebas locales usan datos ficticios y no envían avisos reales.

## Integración Android

La app Android debe obtener el token mediante Firebase Messaging y llamar con la
sesión Supabase del usuario (nunca service_role):

```text
POST /rest/v1/rpc/register_android_push_device
{"p_installation":"UUID persistente de la instalación","p_token":"TOKEN_FCM"}

POST /rest/v1/rpc/unregister_android_push_device
{"p_installation":"UUID persistente de la instalación"}
```

Registrar al iniciar/restaurar sesión y cuando Firebase rote el token; desregistrar
antes de cerrar sesión. El UUID de instalación se genera una vez en el dispositivo
y se conserva de forma privada. La identidad del destinatario se toma de `auth.uid()`.
Los usuarios no pueden leer ninguna tabla de `android_push_private` ni reclamar
trabajos. El SQL amplía la lista permitida del hook de acceso existente para que
una cuenta pendiente pueda registrar el dispositivo y recibir su aprobación.

Crear el canal Android `soundisco_notifications` con sonido y vibración y solicitar
el permiso de notificaciones cuando corresponda. El payload lleva `notification`,
`data.notification_id`, `data.recipient_id` y un `tag` estable por aviso. En primer
plano, la app debe presentar el aviso desde `onMessageReceived`. Al abrirlo, validar
que `recipient_id` corresponde a la sesión actual. El worker no implementa esa UI.

Cambiar de cuenta o token cancela los trabajos antiguos de esa instalación. Un
envío ya reclamado/aceptado por el proveedor no se puede retirar. Como en APNs,
la entrega es al menos una vez: el cliente debe tolerar avisos repetidos. La cola
Android no tiene limpieza automática hasta configurar una política de retención.

## Despliegue y comprobación

1. Ejecutar `android_push.sql` completo antes de desplegar el worker.
2. Añadir el Secret File de Firebase y `GOOGLE_APPLICATION_CREDENTIALS` en Render.
3. Desplegar este directorio manteniendo todas las variables APNs existentes.
4. Verificar `/health`: `processes.apns` y `processes.fcm` deben estar activos y saludables.
5. Registrar un dispositivo Android y generar una notificación para ese usuario.
6. Revisar logs `service: fcm` y consultar estos contadores, sin exponer tokens:

```sql
select count(*) as dispositivos_android from android_push_private.devices;
select count(*) filter (where sent_at is not null) as aceptados,
       count(*) filter (where sent_at is null and attempts < 8) as pendientes,
       count(*) filter (where sent_at is null and attempts >= 8) as agotados
from android_push_private.outbox;
select id, attempts, last_error, next_attempt
from android_push_private.outbox
where sent_at is null and last_error is not null
order by next_attempt desc limit 20;
```
