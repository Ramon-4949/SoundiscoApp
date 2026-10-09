begin;

create index if not exists notification_assignment_reminders
  on public.notificaciones_app(destino_id)
  where destino_tipo='asignacion' and tipo='recordatorio';

create or replace function notification_private.cancel_deleted_assignment_reminders()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  delete from public.notificaciones_app
  where destino_tipo='asignacion'
    and tipo='recordatorio'
    and destino_id=old.id;
  return old;
end;
$$;

revoke all on function notification_private.cancel_deleted_assignment_reminders()
  from public,anon,authenticated;

drop trigger if exists cancel_deleted_assignment_reminders on public.asignaciones;
create trigger cancel_deleted_assignment_reminders
  after delete on public.asignaciones
  for each row execute function notification_private.cancel_deleted_assignment_reminders();

delete from public.notificaciones_app n
where n.destino_tipo='asignacion'
  and n.tipo='recordatorio'
  and not exists (
    select 1 from public.asignaciones a where a.id=n.destino_id
  );

notify pgrst,'reload schema';
commit;
