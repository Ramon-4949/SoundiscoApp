# Worker APNs

Node.js 22. Ejecutar en un servidor con salida HTTPS a Supabase y HTTP/2 a APNs.
No se ejecuta dentro de la app iOS. En Render se despliega como Web Service;
Express escucha en `0.0.0.0:$PORT` y expone `/health`.

Aplicar primero notifications_setup.sql y notification_reminders.sql, y después
notifications_dynamic.sql ANTES de desplegar esta versión del worker.
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

`APNS_KEY_ID` y `APPLE_P8_KEY` siguen aceptándose como alias de las dos variables
Sandbox para no interrumpir el entorno de desarrollo existente. Production siempre
requiere sus propias variables; una llave restringida a Sandbox produce
`BadEnvironmentKeyInToken` al enviar a un dispositivo instalado desde TestFlight.

Instalación: `npm install`.
Arranque continuo: `npm start`.
Ejecución de un lote: `node worker.mjs --once`.
Pruebas sin servicios externos: `npm test`.

El servicio debe mantenerse activo mediante el supervisor de la plataforma con
reinicio automático. Cada ciclo genera recordatorios y reclama hasta 50 envíos,
con un máximo de 5 envíos simultáneos. No es necesario Cron adicional mientras
el worker continuo esté activo. Un planificador externo puede usar --once cada
minuto; debe admitir la duración completa del lote y acceso a los secretos.

Supabase controla exclusión mediante leases de 5 minutos y reintentos con espera
exponencial hasta 8 intentos. Un HTTP 200 de APNs marca aceptación por Apple,
no garantiza que el usuario vea el aviso. Un 410 Unregistered retira el dispositivo.
Los errores de red o configuración no borran tokens. Tras 8 intentos, revisar
last_error de la cola privada desde SQL Editor y corregir antes de reintentar.

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
