# Alarmas de hitos en iOS

1. Ejecutar `ios_alarm_notifications.sql` en Supabase, despues de `notification_reminders.sql` y `milestone_notification_ux.sql`.
2. En Xcode, verificar la capability Time Sensitive Notifications del target y actualizar el perfil de firma si Xcode lo solicita.
3. Compilar e instalar/publicar la app con `milestone_alarm.wav` incluido en el bundle.
4. Desplegar el worker actualizado en Render. `/health` debe mostrar `iosMilestoneAlarm: true` y `apnsQueueRPC: claim_notification_pushes_v4`.

La RPC anterior permanece disponible para despliegues graduales. No se modifica Android.
El worker incluye `is_alarm: true`, sonido `milestone_alarm.wav` y `interruption-level: time-sensitive` solo para alarmas.
Los avisos normales conservan el sonido predeterminado. El contador de no leidos se conserva.
El sonido PCM mono de seis segundos se genera con `Supabase/tests/generate_alarm_sound.mjs` y se incluye en la app.

En Ajustes de iOS, permitir sonidos, globos y notificaciones sensibles al tiempo para SounDisco.
No se fuerza el volumen ni se evita el modo silencio. Las alertas criticas requieren autorizacion especial de Apple y no se solicitan aqui.
No se usa audio en bucle ni se generan notificaciones locales adicionales al recibir un push.
APNs presenta el sonido sin necesitar ejecutar Swift en segundo plano.

Probar desde otra cuenta un hito pendiente, primero con la app abierta y despues bloqueando el telefono.
Comprobar avisos normales a 20/15/10 minutos, alarma a 5 minutos y alarmas al vencer y cada 10 minutos.
Confirmar el hito y verificar que no se generan recordatorios nuevos. Un push ya encolado o aceptado por Apple puede aun llegar.
Los ciclos del worker y la entrega APNs no garantizan un segundo exacto.
