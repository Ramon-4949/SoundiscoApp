select n.id as notificacion_id,n.fecha_creacion,n.perfil_id,n.destino_id as asignacion_id,
  n.payload->>'hito_id' as hito_id,n.mensaje,
  exists(select 1 from public.asignaciones a where a.id=n.destino_id) as asignacion_existe,
  notification_private.reminder_is_actionable(n.destino_id,n.perfil_id,n.payload) as recordatorio_vigente
from public.notificaciones_app n
where n.tipo='recordatorio' and n.destino_tipo='asignacion'
order by n.fecha_creacion desc
limit 30;
