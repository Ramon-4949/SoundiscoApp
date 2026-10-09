begin;

create index if not exists notification_assignment_reminders
  on public.notificaciones_app(destino_id)
  where destino_tipo='asignacion' and tipo='recordatorio';

create or replace function notification_private.reminder_is_actionable(
  assignment_id uuid, recipient_id uuid, reminder_payload jsonb
)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1
    from public.asignaciones a
    join public.hitos_itinerario h on h.asignacion_id=a.id
    join public.hitos_colaboradores c on c.hito_id=h.id
    where a.id=assignment_id
      and c.usuario_id=recipient_id
      and c.confirmado_at is null
      and h.id::text=reminder_payload->>'hito_id'
      and h.fecha_programada is not null
      and (reminder_payload->>'due_at')::timestamptz=h.fecha_programada
  );
$$;

create or replace function notification_private.guard_reminder_insert()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.tipo='recordatorio' and new.destino_tipo='asignacion'
    and not notification_private.reminder_is_actionable(new.destino_id,new.perfil_id,new.payload) then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_reminder_insert on public.notificaciones_app;
create trigger guard_reminder_insert before insert on public.notificaciones_app
  for each row execute function notification_private.guard_reminder_insert();

create or replace function notification_private.cancel_stale_milestone_reminders()
returns trigger language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
  if tg_table_name='asignaciones' then
    aid:=old.id;
  elsif tg_table_name='hitos_itinerario' then
    aid:=old.asignacion_id;
  else
    select asignacion_id into aid from public.hitos_itinerario where id=old.hito_id;
  end if;
  delete from public.notificaciones_app n
    where n.tipo='recordatorio' and n.destino_tipo='asignacion'
      and n.destino_id=aid
      and not notification_private.reminder_is_actionable(n.destino_id,n.perfil_id,n.payload);
  return null;
end;
$$;

drop trigger if exists cancel_stale_assignment_reminders on public.asignaciones;
create trigger cancel_stale_assignment_reminders after delete on public.asignaciones
  for each row execute function notification_private.cancel_stale_milestone_reminders();
drop trigger if exists cancel_stale_milestone_reminders on public.hitos_itinerario;
create trigger cancel_stale_milestone_reminders after delete or update on public.hitos_itinerario
  for each row execute function notification_private.cancel_stale_milestone_reminders();
drop trigger if exists cancel_stale_member_reminders on public.hitos_colaboradores;
create trigger cancel_stale_member_reminders after delete or update on public.hitos_colaboradores
  for each row execute function notification_private.cancel_stale_milestone_reminders();

delete from public.notificaciones_app n
where n.tipo='recordatorio' and n.destino_tipo='asignacion'
  and not notification_private.reminder_is_actionable(n.destino_id,n.perfil_id,n.payload);

create or replace function public.claim_notification_pushes_v4()
returns table(job_id uuid, lease uuid, notification_id uuid, recipient uuid, token text,
  environment text, title text, body text, badge integer, is_alarm boolean)
language sql security definer set search_path='' as $$
  select j.*,coalesce(n.payload->'is_alarm'='true'::jsonb,false)
  from public.claim_notification_pushes_v3() j
  join public.notificaciones_app n on n.id=j.notification_id and n.perfil_id=j.recipient
  where n.tipo is distinct from 'recordatorio'
    or n.destino_tipo is distinct from 'asignacion'
    or notification_private.reminder_is_actionable(n.destino_id,n.perfil_id,n.payload);
$$;

revoke all on function notification_private.reminder_is_actionable(uuid,uuid,jsonb),
  notification_private.guard_reminder_insert(),
  notification_private.cancel_stale_milestone_reminders(),
  public.claim_notification_pushes_v4() from public,anon,authenticated;
grant execute on function public.claim_notification_pushes_v4() to service_role;

notify pgrst,'reload schema';
commit;
