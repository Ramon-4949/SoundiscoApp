-- Run after milestone_collaborators.sql. This migration is repeatable.
begin;

do $$ begin
  if current_setting('server_encoding') <> 'UTF8' then
    raise exception 'La base de datos debe usar UTF-8 para conservar las tildes';
  end if;
end $$;

-- A deadline is a display-time condition, not a stored workflow transition.
create or replace view public.asignaciones_estado_efectivo
with (security_invoker = true) as
select a.id,
  case
    when a.estado = 'completada' then 'completada'
    when a.fecha_limite <= now() then 'vencida'
    else a.estado
  end as estado
from public.asignaciones a;
grant select on public.asignaciones_estado_efectivo to authenticated;

create or replace function sla_private.advance(p_assignment uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.asignaciones where id = p_assignment for update;
  if not found then return; end if;

  with progress as (
    select h.id, count(c.usuario_id) > 0 and bool_and(c.confirmado_at is not null) as done,
      max(c.confirmado_at) as confirmed_at
    from public.hitos_itinerario h
    left join public.hitos_colaboradores c on c.hito_id = h.id
    where h.asignacion_id = p_assignment
    group by h.id
  )
  update public.hitos_itinerario h
  set completado = p.done,
      estado_hito = case when p.done then 'completado' else 'en_curso' end,
      hora_real_completado = case when p.done then p.confirmed_at else null end
  from progress p
  where h.id = p.id
    and (h.completado,h.estado_hito,h.hora_real_completado) is distinct from
      (p.done,case when p.done then 'completado' else 'en_curso' end,
       case when p.done then p.confirmed_at else null end);

  update public.asignaciones a
  set estado = case
    when exists (
      select 1 from public.hitos_colaboradores c
      join public.hitos_itinerario h on h.id = c.hito_id
      where h.asignacion_id = a.id
    ) and not exists (
      select 1 from public.hitos_colaboradores c
      join public.hitos_itinerario h on h.id = c.hito_id
      where h.asignacion_id = a.id and c.confirmado_at is null
    ) then 'completada'
    when exists (
      select 1 from public.hitos_colaboradores c
      join public.hitos_itinerario h on h.id = c.hito_id
      where h.asignacion_id = a.id and c.confirmado_at is not null
    ) then 'en_curso'
    else 'pendiente'
  end
  where a.id = p_assignment;
end $$;

create or replace function sla_private.advance_from_check_in()
returns trigger language plpgsql security definer set search_path = '' as $$
declare assignment_id uuid;
begin
  select h.asignacion_id into assignment_id
  from public.hitos_itinerario h where h.id = new.hito_id;
  if assignment_id is not null then perform sla_private.advance(assignment_id); end if;
  return new;
end $$;
drop trigger if exists advance_assignment_from_check_in on public.hitos_colaboradores;
create trigger advance_assignment_from_check_in
after update of estado,confirmado_at on public.hitos_colaboradores
for each row
when (old.confirmado_at is distinct from new.confirmado_at
   or old.estado is distinct from new.estado)
execute function sla_private.advance_from_check_in();

-- Retire the old cron that stored 'vencida' and reconcile previously stored rows.
do $$ declare job_id bigint; begin
  if to_regclass('cron.job') is not null then
    for job_id in select jobid from cron.job
      where jobname = 'expire-assignments-every-minute' loop
      perform cron.unschedule(job_id);
    end loop;
    for job_id in select jobid from cron.job
      where jobname = 'assignment-sla-every-minute' loop
      perform cron.unschedule(job_id);
    end loop;
  end if;
end $$;
drop function if exists public.refresh_expired_assignments(uuid);

do $$ declare assignment_id uuid; begin
  for assignment_id in select id from public.asignaciones order by id loop
    perform sla_private.advance(assignment_id);
  end loop;
end $$;

-- Only the individual check-in RPC writes confirmation rows. Older app builds
-- still reach that RPC through employee_complete_milestone.
revoke all on function sla_private.advance_from_check_in() from public,anon,authenticated;

-- State-only changes no longer produce generic or expiry notices. Employee
-- assignment creation, edits, removal and urgency continue to be delivered.
create or replace function notification_private.flush_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  e notification_private.assignment_events%rowtype;
  a public.asignaciones%rowtype;
  team uuid[]; recipient uuid; kind text; title text; body text;
  event_key text; assignment_title text; is_admin boolean;
begin
  delete from notification_private.assignment_events
  where transaction_id = new.transaction_id and assignment_id = new.assignment_id
  returning * into e;
  if not found then return null; end if;
  if current_setting('soundisco.individual_checkin',true) = 'true' then return null; end if;
  select * into a from public.asignaciones where id = e.assignment_id;
  select coalesce(array_agg(distinct perfil_id),'{}') into team
  from public.asignacion_equipo where asignacion_id = e.assignment_id;
  assignment_title := coalesce(nullif(a.titulo,''),nullif(e.old_title,''),'la actividad');
  event_key := e.transaction_id::text || ':' || e.assignment_id::text;

  for recipient in select distinct unnest(e.old_team || team) loop
    select exists(select 1 from public.perfiles where id = recipient and rol = 'admin') into is_admin;
    kind := null;
    if not is_admin then
      if a.id is null then
        kind := 'asignacion_eliminada'; title := 'Asignación cancelada';
        body := 'La asignación ' || assignment_title || ' ha sido eliminada';
      elsif recipient = any(e.old_team) and not recipient = any(team) then
        kind := 'asignacion_retirada'; title := 'Asignación cancelada';
        body := 'Has sido removido de la asignación ' || assignment_title;
      elsif recipient = any(team) and not recipient = any(e.old_team) then
        kind := 'asignacion_nueva'; title := 'Nueva asignación';
        body := case when a.tipo_flujo = 'campo' then 'Se te ha asignado al montaje: '
          else 'Se te ha asignado la tarea: ' end || assignment_title;
      elsif e.content_changed or
        (select array_agg(x order by x) from unnest(e.old_team) x) is distinct from
        (select array_agg(x order by x) from unnest(team) x) then
        kind := 'asignacion_actualizada'; title := 'Cambios en tu evento';
        body := 'La asignación ' || assignment_title || ' ha sido modificada';
      end if;
    end if;
    if kind is not null then
      perform notification_private.emit(recipient,kind,title,body,'asignacion',e.assignment_id,a.estado,event_key);
    end if;
    if a.id is not null and recipient = any(team)
      and lower(a.nivel_prioridad) = 'alta'
      and lower(coalesce(e.old_priority,'')) <> 'alta' then
      perform notification_private.emit(recipient,'asignacion_urgente','¡URGENTE!',
        'La asignación ' || assignment_title || ' ha sido marcada como urgente. Se requiere atención inmediata en el evento.',
        'asignacion',e.assignment_id,a.estado,event_key || ':urgente');
    end if;
  end loop;
  return null;
end $$;

create or replace function public.generate_notification_reminders()
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  if not pg_try_advisory_xact_lock(81420931) then return; end if;
  for r in select h.*,c.usuario_id from public.hitos_itinerario h
    join public.hitos_colaboradores c on c.hito_id = h.id
    where c.confirmado_at is null
      and h.fecha_programada between now() and now() + interval '15 minutes'
  loop
    perform notification_private.emit(r.usuario_id,'recordatorio','Alerta de Hito',
      'El hito ' || r.descripcion || ' está por vencer pronto',
      'asignacion',r.asignacion_id,null,
      'personal-reminder:' || r.id::text || ':' || extract(epoch from r.fecha_programada)::text);
  end loop;
  for r in select a.id,a.titulo,c.usuario_id,max(h.fecha_programada) deadline
    from public.hitos_colaboradores c
    join public.hitos_itinerario h on h.id = c.hito_id
    join public.asignaciones a on a.id = h.asignacion_id
    group by a.id,a.titulo,c.usuario_id
    having bool_or(c.confirmado_at is null)
      and max(h.fecha_programada) between now() and now() + interval '15 minutes'
  loop
    perform notification_private.emit(r.usuario_id,'recordatorio','Cierre de Asignación',
      'Tu plazo en la asignación ' || r.titulo || ' está próximo a vencer',
      'asignacion',r.id,null,
      'personal-close:' || r.id::text || ':' || extract(epoch from r.deadline)::text);
  end loop;
end $$;

-- Replace the individual RPC to ensure new rows contain accented Spanish.
create or replace function public.check_in_milestone(p_hito_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare h public.hitos_itinerario%rowtype; aid uuid; deadline timestamptz; checked timestamptz;
  evaluation text; recipient uuid; actor_name text;
begin
  if auth.uid() is null or not public.account_is_approved() then
    raise exception 'Acceso no aprobado' using errcode='42501'; end if;
  select asignacion_id into aid from public.hitos_itinerario where id=p_hito_id;
  perform 1 from public.asignaciones where id=aid for update;
  select * into h from public.hitos_itinerario where id=p_hito_id;
  if not found then raise exception 'El hito ya no existe'; end if;
  if not exists(select 1 from public.hitos_colaboradores where hito_id=h.id and usuario_id=auth.uid()) then
    raise exception 'No estás asignado a este hito' using errcode='42501'; end if;
  if exists(select 1 from public.hitos_colaboradores where hito_id=h.id and usuario_id=auth.uid() and confirmado_at is not null) then return; end if;
  select m.fecha_programada into deadline from public.hitos_itinerario m
    join public.hitos_colaboradores c on c.hito_id=m.id
    where m.asignacion_id=aid and c.usuario_id=auth.uid() order by m.orden desc limit 1;
  checked:=clock_timestamp();
  if deadline is null or h.fecha_programada is null then raise exception 'Falta la fecha límite del hito'; end if;
  if checked>deadline then raise exception 'Tu plazo final venció. No puedes confirmar hitos pendientes.' using errcode='23514'; end if;
  if exists(select 1 from public.hitos_itinerario m join public.hitos_colaboradores c on c.hito_id=m.id
    where m.asignacion_id=aid and m.orden<h.orden and c.usuario_id=auth.uid() and c.confirmado_at is null) then
    raise exception 'Confirma primero tu hito anterior' using errcode='23514'; end if;
  evaluation:=case when checked<h.fecha_programada then 'temprano'
    when checked=h.fecha_programada then 'a_tiempo' else 'tardio' end;
  update public.hitos_colaboradores set confirmado_at=checked,hora_programada=h.fecha_programada,estado=evaluation
    where hito_id=h.id and usuario_id=auth.uid();
  insert into public.confirmaciones_hitos(asignacion_id,hito_id,usuario_id,created_at,hora_programada,evaluacion)
    values(aid,h.id,auth.uid(),checked,h.fecha_programada,evaluation);
  select coalesce(nombre_completo,'Un colaborador') into actor_name from public.perfiles where id=auth.uid();
  for recipient in select id from public.perfiles where rol='admin' loop
    perform notification_private.emit(recipient,'hito_completado','Confirmación de Hito',
      actor_name||' confirmó '||h.descripcion,'asignacion',aid,null,
      'individual:'||h.id::text||':'||auth.uid()::text);
  end loop;
  perform set_config('soundisco.individual_checkin','true',true);
  perform sla_private.advance(aid);
  if exists(select 1 from public.asignaciones where id=aid and estado='completada') then
    for recipient in select id from public.perfiles where rol='admin' loop
      perform notification_private.emit(recipient,'asignacion_completada','Asignación completada',
        'El evento ha sido completado al 100%', 'asignacion',aid,'completada',
        'individual-complete:'||aid::text);
    end loop;
  end if;
end $$;

-- Repair queued and in-app rows generated before this migration.
delete from public.notificaciones_app
where tipo = 'estado_actualizado'
  and (estado = 'vencida' or mensaje ilike '%estado%vencida%');
update public.notificaciones_app
set titulo = 'Confirmación de Hito',
    mensaje = replace(mensaje,' confirmo ',' confirmó ')
where tipo = 'hito_completado'
  and (titulo = 'Confirmacion de Hito' or mensaje like '% confirmo %');
update public.notificaciones_app
set titulo = 'Cierre de Asignación',
    mensaje = replace(replace(mensaje,' asignacion ',' asignación '),
      ' esta proximo a vencer',' está próximo a vencer')
where tipo = 'recordatorio' and titulo = 'Cierre de Asignacion';
update public.notificaciones_app
set mensaje = replace(mensaje,' esta por vencer pronto',' está por vencer pronto')
where tipo = 'recordatorio' and titulo = 'Alerta de Hito'
  and mensaje like '% esta por vencer pronto';

revoke all on function notification_private.flush_assignment(),
  sla_private.advance(uuid),sla_private.advance_from_check_in() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
