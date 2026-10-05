# Actualización de hitos y avisos

1. Ejecutar `milestone_notification_ux.sql` completo en Supabase SQL Editor, después
   de las migraciones existentes de hitos y `assignment_status_automation.sql`.
2. Desplegar `push-worker/` en Render. Esta versión requiere la RPC
   `claim_notification_pushes_v3`; mantener las variables APNs y Firebase actuales.
3. Compilar la aplicación y distribuir la nueva build en TestFlight.

## Comportamiento

- Las confirmaciones llegan a administradores y supervisores de la asignación.
  Se mantiene la exclusión del autor del aviso de su propia confirmación.
- Las notas notifican a administradores, supervisores y colaboradores de esa
  asignación, incluido el autor. No notifican a empleados de otros eventos.
  El push no contiene el nombre del autor ni el contenido privado de la nota.
- El vencimiento sigue visible, pero ya permite confirmar tarde, respetando el
  orden personal de hitos. Se conserva la evaluación actual: antes de la hora,
  temprano; después, tardío.
- Cada colaborador puede deshacer su propia confirmación desde el checklist.
  La operación elimina su registro de cumplimiento, devuelve su participación a
  sin confirmar y recalcula el estado global. Conserva las confirmaciones de otros
  colaboradores y los hitos posteriores ya confirmados. Admins y supervisores
  reciben un aviso de la reversión. Volver a confirmar genera un registro nuevo.
- Los push iOS incluyen el número total de avisos sin leer. Al abrir la app o
  marcar avisos como leídos se sincroniza el badge local. El usuario debe permitir
  Globos/Insignias en Ajustes > Notificaciones > SounDisco. Leer desde otro
  dispositivo se reflejará al sincronizar o recibir otro push.
- La búsqueda usa colores adaptativos y un borde visible en modo claro.
- Los tiempos se muestran en minutos, horas, días, semanas, meses o años con
  hasta dos unidades, según su duración.

## Comprobación

Con un admin, un supervisor asignado y dos colaboradores, confirmar un hito ya
vencido; verificar evaluación tardía y aviso a admin y supervisor. Deshacer la
confirmación, comprobar que los demás registros no cambian y volver a confirmar.
Publicar una nota y comprobar los avisos del equipo. Con la app en segundo plano,
generar varios avisos y comprobar el badge; abrirlos y verificar que disminuye.
Probar la búsqueda en modo claro y oscuro.

El SQL es repetible y conserva la política de acceso existente. Ejecutar siempre
esta migración después de scripts antiguos que redefinan `check_in_milestone`.
