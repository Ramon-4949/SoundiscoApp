-- Run after the existing notification, SLA and account migrations.
-- Regular index creation blocks writes briefly: run during low traffic.
begin;
set local lock_timeout = '5s';

create index if not exists assignments_history on public.asignaciones(fecha_creacion desc, id desc);
create index if not exists assignments_state_history on public.asignaciones(estado, fecha_creacion desc, id desc);
create index if not exists assignments_pending_deadline on public.asignaciones(fecha_limite)
  where estado not in ('completada', 'vencida');
create index if not exists team_employee_assignment on public.asignacion_equipo(perfil_id, asignacion_id);
create index if not exists milestones_assignment_order on public.hitos_itinerario(asignacion_id, orden desc);
create index if not exists confirmations_assignment on public.confirmaciones_hitos(asignacion_id);
create index if not exists confirmations_user_time on public.confirmaciones_hitos(usuario_id, created_at);
create index if not exists confirmations_user_schedule on public.confirmaciones_hitos(usuario_id, hora_programada);
create index if not exists notes_assignment_time on public.notas_asignacion(asignacion_id, created_at);
create index if not exists notes_user_created on public.notas_asignacion(usuario_id, created_at);
create index if not exists notification_recipient_date on public.notificaciones_app(perfil_id, fecha_creacion desc);
create index if not exists push_device_profile on notification_private.devices(perfil_id);
create index if not exists outbox_installation on notification_private.outbox(installation);
create index if not exists outbox_ready on notification_private.outbox(next_attempt)
  where sent_at is null and attempts < 8;
create index if not exists outbox_sent_retention on notification_private.outbox(sent_at)
  where sent_at is not null;

-- Only successful deliveries have sent_at. Failed jobs are deliberately retained.
create or replace function notification_private.purge_sent_outbox()
returns bigint language plpgsql security definer set search_path = '' as $$
declare removed bigint;
begin
  delete from notification_private.outbox
  where sent_at < now() - interval '30 days'
    and (leased_until is null or leased_until < now());
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function notification_private.purge_sent_outbox() from public, anon, authenticated;
commit;
