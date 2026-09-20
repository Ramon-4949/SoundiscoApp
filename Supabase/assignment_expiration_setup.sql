-- Ejecutar después de assignment_milestone_editing_fix.sql.
-- El último hito define la fecha límite y una asignación vencida no puede avanzar.
begin;

create or replace function public.assignment_deadline(p_asignacion_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    a.fecha_limite,
    (
      select h.fecha_programada
      from public.hitos_itinerario h
      where h.asignacion_id = a.id
        and h.fecha_programada is not null
      order by h.orden desc
      limit 1
    )
  )
  from public.asignaciones a
  where a.id = p_asignacion_id;
$$;

revoke all on function public.assignment_deadline(uuid) from public, anon;
grant execute on function public.assignment_deadline(uuid) to authenticated, service_role;

create or replace function public.sync_assignment_deadline_from_milestones()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asignacion_id uuid := coalesce(new.asignacion_id, old.asignacion_id);
  v_deadline timestamptz;
begin
  select h.fecha_programada
    into v_deadline
  from public.hitos_itinerario h
  where h.asignacion_id = v_asignacion_id
    and h.fecha_programada is not null
  order by h.orden desc
  limit 1;

  update public.asignaciones
  set fecha_limite = v_deadline
  where id = v_asignacion_id
    and fecha_limite is distinct from v_deadline;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_assignment_deadline on public.hitos_itinerario;
create trigger sync_assignment_deadline
after insert or update or delete
on public.hitos_itinerario
for each row execute function public.sync_assignment_deadline_from_milestones();

update public.asignaciones a
set fecha_limite = (
  select h.fecha_programada
  from public.hitos_itinerario h
  where h.asignacion_id = a.id
    and h.fecha_programada is not null
  order by h.orden desc
  limit 1
)
where exists (
  select 1
  from public.hitos_itinerario h
  where h.asignacion_id = a.id
    and h.fecha_programada is not null
);

create or replace function public.refresh_expired_assignments(p_asignacion_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  update public.asignaciones a
  set estado = 'vencida'
  where (p_asignacion_id is null or a.id = p_asignacion_id)
    and coalesce(a.estado, 'pendiente') not in ('completada', 'vencida')
    and public.assignment_deadline(a.id) <= now();

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.refresh_expired_assignments(uuid) from public, anon;
grant execute on function public.refresh_expired_assignments(uuid) to authenticated, service_role;

create or replace function public.employee_complete_milestone(
  p_hito_id uuid,
  p_notas text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asignacion_id uuid;
  v_orden integer;
  v_siguiente_id uuid;
  v_deadline timestamptz;
begin
  select h.asignacion_id, h.orden
    into v_asignacion_id, v_orden
  from public.hitos_itinerario h
  where h.id = p_hito_id;

  if v_asignacion_id is null then
    raise exception 'El hito no existe' using errcode = 'P0002';
  end if;

  perform 1
  from public.asignaciones
  where id = v_asignacion_id
  for update;

  v_deadline := public.assignment_deadline(v_asignacion_id);
  if v_deadline is not null and v_deadline <= now() then
    raise exception 'La fecha limite de esta asignacion ya vencio. El checklist esta bloqueado.'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.asignacion_equipo
    where asignacion_id = v_asignacion_id
      and perfil_id = (select auth.uid())
  ) then
    raise exception 'Solo un empleado asignado puede completar este hito' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.hitos_itinerario
    where asignacion_id = v_asignacion_id
      and orden < v_orden
      and not coalesce(completado, false)
  ) then
    raise exception 'Completa primero el hito anterior' using errcode = '23514';
  end if;

  update public.hitos_itinerario
  set completado = true,
      estado_hito = 'completado',
      hora_real_completado = now(),
      notas_incidencias = coalesce(nullif(btrim(p_notas), ''), notas_incidencias)
  where id = p_hito_id
    and not coalesce(completado, false);

  select id
    into v_siguiente_id
  from public.hitos_itinerario
  where asignacion_id = v_asignacion_id
    and not coalesce(completado, false)
  order by orden
  limit 1;

  if v_siguiente_id is null then
    update public.asignaciones
    set estado = 'completada'
    where id = v_asignacion_id;
  else
    update public.hitos_itinerario
    set estado_hito = 'en_curso'
    where id = v_siguiente_id;

    update public.asignaciones
    set estado = 'en_curso'
    where id = v_asignacion_id;
  end if;
end;
$$;

revoke all on function public.employee_complete_milestone(uuid, text) from public, anon;
grant execute on function public.employee_complete_milestone(uuid, text) to authenticated;

select public.refresh_expired_assignments();

create extension if not exists pg_cron with schema pg_catalog;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'expire-assignments-every-minute'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'expire-assignments-every-minute',
    '* * * * *',
    'select public.refresh_expired_assignments();'
  );
end;
$$;

notify pgrst, 'reload schema';
commit;
