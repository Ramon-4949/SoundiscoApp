# Worker APNs

Node.js 22. Ejecutar en un servidor con salida HTTPS a Supabase y HTTP/2 a APNs.
No se ejecuta dentro de la app iOS. En Render se despliega como Web Service;
Express escucha en `0.0.0.0:$PORT` y expone `/health`.

Aplicar primero notifications_setup.sql y notification_reminders.sql.
Configurar secretos del servicio:

- SUPABASE_URL: https://gsrwfgpyflwozxzizmnv.supabase.co
- SUPABASE_SERVICE_ROLE_KEY: clave service_role, nunca la publishable.
- APNS_KEY_ID: identificador de la clave APNs.
- APNS_TEAM_ID: identificador del equipo Apple Developer.
- APPLE_P8_KEY: contenido completo y multilinea del archivo .p8.
- APNS_BUNDLE_ID: hola.SoundiscoApp.
- PORT: lo asigna Render automáticamente; no es necesario configurarlo.

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

El payload visible es siempre genérico. Solo incluye notification_id y recipient_id
como metadatos de navegación. No incluye nombre, ubicación, instrucciones ni
asunto del comunicado; no se registran tokens ni secretos en los logs.

Falta configurar los secretos, habilitar Push Notifications en Apple Developer,
desplegar el worker y probar con un dispositivo firmado. No se han enviado avisos
reales durante las pruebas locales.
