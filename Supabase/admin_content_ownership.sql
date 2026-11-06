begin;
set local soundisco.legacy_owner_email='yankee_admin@gmail.com';
set local lock_timeout='5s';
select pg_advisory_xact_lock(81420982);

-- The user confirmed that this admin created all legacy assignments and bulletins.
do $$
declare legacy_email text:=nullif(btrim(current_setting('soundisco.legacy_owner_email',true)),''); legacy_id uuid; item text;
begin
  if legacy_email is not null then
    select u.id into legacy_id from auth.users u join public.perfiles p on p.id=u.id
      where lower(u.email)=lower(legacy_email) and p.rol='admin';
    if legacy_id is null then raise exception 'El creador historico debe ser una cuenta administradora existente'; end if;
  end if;
  foreach item in array array['asignaciones','comunicados'] loop
    if not exists(select 1 from information_schema.columns where table_schema='public' and table_name=item and column_name='created_by') then
      execute format('alter table public.%I add column created_by uuid%s',item,
        case when legacy_id is null then '' else format(' default %L::uuid',legacy_id) end);
    end if;
  end loop;
  if exists(select 1 from public.asignaciones where created_by is null)
    or exists(select 1 from public.comunicados where created_by is null) then
    raise exception 'Falta identificar al creador de registros antiguos. No se ha activado el cambio.';
  end if;
end $$;

alter table public.asignaciones alter column created_by set not null,alter column created_by set default auth.uid();
alter table public.comunicados alter column created_by set not null,alter column created_by set default auth.uid();
create index if not exists assignments_creator_date on public.asignaciones(created_by,fecha_creacion desc,id);
create index if not exists bulletins_creator_date on public.comunicados(created_by,fecha_publicacion desc,id);

create schema if not exists ownership_private;
revoke all on schema ownership_private from public,anon,authenticated;

-- Keep the creator after deletion so delayed cancellation notices cannot reach another admin.
create table if not exists ownership_private.resource_creators(
  kind text not null check(kind in ('asignacion','comunicado')),
  resource_id uuid not null,
  created_by uuid not null,
  primary key(kind,resource_id)
);
alter table ownership_private.resource_creators enable row level security;
revoke all on ownership_private.resource_creators from public,anon,authenticated;
insert into ownership_private.resource_creators select 'asignacion',id,created_by from public.asignaciones on conflict do nothing;
insert into ownership_private.resource_creators select 'comunicado',id,created_by from public.comunicados on conflict do nothing;

create or replace function ownership_private.creator(p_kind text,p_id uuid)
returns uuid language sql stable security definer set search_path='' as $$
  select created_by from ownership_private.resource_creators where kind=p_kind and resource_id=p_id;
$$;

create or replace function ownership_private.bind_creator()
returns trigger language plpgsql security definer set search_path='' as $$
declare resource_kind text:=case tg_table_name when 'asignaciones' then 'asignacion' else 'comunicado' end;
begin
  if tg_op='UPDATE' then
    if (new.id,new.created_by) is distinct from (old.id,old.created_by) then
      raise exception 'No puedes cambiar el creador de un registro' using errcode='42501';
    end if;
    return new;
  end if;
  if auth.uid() is not null then
    if not public.es_admin() or not public.account_is_approved() then
      raise exception 'Solo administradores aprobados pueden crear contenido' using errcode='42501';
    end if;
    if new.created_by is not null and new.created_by<>auth.uid() then
      raise exception 'No puedes crear contenido a nombre de otro administrador' using errcode='42501';
    end if;
    new.created_by:=auth.uid();
  end if;
  if new.created_by is null then raise exception 'Falta el creador del registro'; end if;
  insert into ownership_private.resource_creators(kind,resource_id,created_by)
    values(resource_kind,new.id,new.created_by) on conflict do nothing;
  if ownership_private.creator(resource_kind,new.id) is distinct from new.created_by then
    raise exception 'Ese identificador ya pertenece a otro creador' using errcode='42501';
  end if;
  return new;
end;
$$;
drop trigger if exists aaa_bind_creator on public.asignaciones;
create trigger aaa_bind_creator before insert or update on public.asignaciones
  for each row execute function ownership_private.bind_creator();
drop trigger if exists aaa_bind_creator on public.comunicados;
create trigger aaa_bind_creator before insert or update on public.comunicados
  for each row execute function ownership_private.bind_creator();

create or replace function public.admin_owns_assignment(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(auth.uid() is not null and public.account_is_approved() and public.es_admin()
    and ownership_private.creator('asignacion',p_id)=auth.uid(),false);
$$;
create or replace function public.admin_owns_bulletin(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(auth.uid() is not null and public.account_is_approved() and public.es_admin()
    and ownership_private.creator('comunicado',p_id)=auth.uid(),false);
$$;

create or replace function public.puede_ver_asignacion(p_asignacion_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and public.account_is_approved() and exists(
    select 1 from public.asignaciones a where a.id=p_asignacion_id and
      case when public.es_admin() then a.created_by=auth.uid() else exists(
        select 1 from public.asignacion_equipo e where e.asignacion_id=a.id and e.perfil_id=auth.uid()) end);
$$;
create or replace function public.can_supervise_assignment(p_assignment uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and public.account_is_approved() and exists(
    select 1 from public.asignaciones a where a.id=p_assignment and
      case when public.es_admin() then a.created_by=auth.uid() else exists(
        select 1 from public.asignacion_supervisores s where s.asignacion_id=a.id and s.usuario_id=auth.uid()) end);
$$;
create or replace function public.can_read_milestone(p_hito uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and public.account_is_approved() and exists(
    select 1 from public.hitos_itinerario h where h.id=p_hito and
      case when public.es_admin() then public.admin_owns_assignment(h.asignacion_id) else
        public.can_supervise_assignment(h.asignacion_id) or exists(select 1
          from public.hitos_colaboradores c where c.hito_id=h.id and c.usuario_id=auth.uid()) end);
$$;

do $$
declare item record; predicate text;
begin
  for item in select * from (values
    ('asignaciones','created_by=auth.uid()'),
    ('comunicados','created_by=auth.uid()'),
    ('asignacion_equipo','public.admin_owns_assignment(asignacion_id)'),
    ('asignacion_supervisores','public.admin_owns_assignment(asignacion_id)'),
    ('hitos_itinerario','public.admin_owns_assignment(asignacion_id)'),
    ('checklist_equipos','public.admin_owns_assignment(asignacion_id)'),
    ('confirmaciones_hitos','public.admin_owns_assignment(asignacion_id)'),
    ('notas_asignacion','public.admin_owns_assignment(asignacion_id)'),
    ('hitos_colaboradores','exists(select 1 from public.hitos_itinerario h where h.id=hito_id and public.admin_owns_assignment(h.asignacion_id))')
  ) as content(table_name,ownership_check) loop
    predicate:=format('not public.es_admin() or (%s)',item.ownership_check);
    execute format('alter table public.%I enable row level security',item.table_name);
    execute format('revoke truncate,references,trigger on public.%I from public,anon,authenticated',item.table_name);
    execute format('drop policy if exists admin_creator_guard on public.%I',item.table_name);
    execute format('create policy admin_creator_guard on public.%I as restrictive for all to authenticated
      using (%s) with check (%s)',item.table_name,predicate,predicate);
  end loop;
end $$;
alter view public.asignaciones_estado_efectivo set(security_invoker=true);
revoke all on public.asignaciones_estado_efectivo from anon;
revoke insert,update,delete,truncate,references,trigger on public.asignaciones_estado_efectivo from authenticated;

alter function public.admin_dashboard_summary() security invoker;
alter function public.admin_assignments_page(integer,integer,text,text) security invoker;
alter function public.assignment_deadline(uuid) security invoker;

create or replace function public.admin_update_assignment(p_asignacion_id uuid,p_asignacion jsonb,p_empleados uuid[],p_hitos jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare team uuid[]; supervisors jsonb:=coalesce(p_asignacion->'supervisores','[]'::jsonb);
begin
  if not public.admin_owns_assignment(p_asignacion_id) then
    raise exception 'Solo puedes editar tus asignaciones' using errcode='42501';
  end if;
  team:=milestone_private.validate_members(p_hitos,supervisors);
  perform 1 from public.asignaciones where id=p_asignacion_id for update;
  perform milestone_private.update_legacy(p_asignacion_id,p_asignacion,team,p_hitos);
  perform milestone_private.save_members(p_asignacion_id,p_hitos,supervisors);
  perform sla_private.advance(p_asignacion_id);
end;
$$;
create or replace function public.admin_delete_assignment(p_asignacion_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.admin_owns_assignment(p_asignacion_id) then
    raise exception 'Solo puedes eliminar tus asignaciones' using errcode='42501';
  end if;
  perform 1 from public.asignaciones where id=p_asignacion_id for update;
  if not found then raise exception 'La asignacion ya no existe'; end if;
  perform set_config('soundisco.deleting_assignment',p_asignacion_id::text,true);
  delete from public.checklist_equipos where asignacion_id=p_asignacion_id;
  update public.notificaciones_app set asignacion_relacionada_id=null where asignacion_relacionada_id=p_asignacion_id;
  delete from public.hitos_itinerario where asignacion_id=p_asignacion_id;
  delete from public.asignacion_equipo where asignacion_id=p_asignacion_id;
  delete from public.asignaciones where id=p_asignacion_id;
end;
$$;

create or replace function public.admin_note_reports(p_offset integer default 0)
returns table(id uuid,note_id uuid,reason text,created_at timestamptz,contenido text,asignacion text)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not public.account_is_approved() or not public.es_admin() then
    raise exception 'Solo administradores pueden revisar reportes' using errcode='42501'; end if;
  return query select r.id,r.note_id,r.reason,r.created_at,n.contenido,a.titulo
    from moderation_private.note_reports r join public.notas_asignacion n on n.id=r.note_id
    join public.asignaciones a on a.id=n.asignacion_id
    where r.resolved_at is null and a.created_by=auth.uid()
    order by r.created_at,r.id limit 50 offset greatest(coalesce(p_offset,0),0);
end;
$$;
create or replace function public.admin_resolve_note_report(p_report_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from moderation_private.note_reports r join public.notas_asignacion n on n.id=r.note_id
    where r.id=p_report_id and public.admin_owns_assignment(n.asignacion_id)) then
    raise exception 'No tienes acceso a este reporte' using errcode='42501'; end if;
  update moderation_private.note_reports set resolved_at=now() where id=p_report_id and resolved_at is null;
end;
$$;
create or replace function public.admin_remove_assignment_note(p_note_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not exists(select 1 from public.notas_asignacion n where n.id=p_note_id
    and public.admin_owns_assignment(n.asignacion_id)) then
    raise exception 'No tienes acceso a esta nota' using errcode='42501'; end if;
  delete from public.notas_asignacion where id=p_note_id;
end;
$$;

-- Preserve the current timing, SLA and confirmation logic behind the access check.
do $$
begin
  if to_regprocedure('ownership_private.check_in_legacy(uuid)') is null then
    alter function public.check_in_milestone(uuid) set schema ownership_private;
    alter function ownership_private.check_in_milestone(uuid) rename to check_in_legacy;
  end if;
  if to_regprocedure('ownership_private.undo_confirmation_legacy(uuid)') is null then
    alter function public.undo_milestone_confirmation(uuid) set schema ownership_private;
    alter function ownership_private.undo_milestone_confirmation(uuid) rename to undo_confirmation_legacy;
  end if;
end $$;
create or replace function public.check_in_milestone(p_hito_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.can_read_milestone(p_hito_id) then
    raise exception 'No tienes acceso a este hito' using errcode='42501'; end if;
  perform ownership_private.check_in_legacy(p_hito_id);
end;
$$;
create or replace function public.undo_milestone_confirmation(p_hito_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if not public.can_read_milestone(p_hito_id) then
    raise exception 'No tienes acceso a este hito' using errcode='42501'; end if;
  perform ownership_private.undo_confirmation_legacy(p_hito_id);
end;
$$;

create or replace function ownership_private.notification_allowed(p_recipient uuid,p_type text,p_target uuid,p_assignment uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select case when not exists(select 1 from public.perfiles where id=p_recipient and rol='admin') then true
    when p_type in ('asignacion','comunicado') then ownership_private.creator(p_type,p_target)=p_recipient
    when p_assignment is not null then ownership_private.creator('asignacion',p_assignment)=p_recipient
    else true end;
$$;
create or replace function ownership_private.filter_notification()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not coalesce(ownership_private.notification_allowed(new.perfil_id,new.destino_tipo,new.destino_id,new.asignacion_relacionada_id),false)
    then return null; end if;
  return new;
end;
$$;
drop trigger if exists admin_creator_notification_guard on public.notificaciones_app;
create trigger admin_creator_notification_guard before insert or update on public.notificaciones_app
  for each row execute function ownership_private.filter_notification();
delete from public.notificaciones_app n where not coalesce(
  ownership_private.notification_allowed(n.perfil_id,n.destino_tipo,n.destino_id,n.asignacion_relacionada_id),false);

create or replace function public.admin_notification_visible(p_type text,p_target uuid,p_assignment uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and coalesce(ownership_private.notification_allowed(auth.uid(),p_type,p_target,p_assignment),false);
$$;
drop policy if exists admin_creator_notification_read on public.notificaciones_app;
create policy admin_creator_notification_read on public.notificaciones_app as restrictive for select to authenticated
  using(public.admin_notification_visible(destino_tipo,destino_id,asignacion_relacionada_id));

create or replace function notification_private.flush_assignment()
returns trigger language plpgsql security definer set search_path='' as $$
declare e notification_private.assignment_events%rowtype; a public.asignaciones%rowtype;
  team uuid[]; recipient uuid; kind text; title text; body text; event_key text; assignment_title text;
begin
  delete from notification_private.assignment_events
    where transaction_id=new.transaction_id and assignment_id=new.assignment_id returning * into e;
  if not found then return null; end if;
  if current_setting('soundisco.individual_checkin',true)='true' then return null; end if;
  select * into a from public.asignaciones where id=e.assignment_id;
  select coalesce(array_agg(distinct perfil_id),'{}') into team
    from public.asignacion_equipo where asignacion_id=e.assignment_id;
  assignment_title:=coalesce(nullif(a.titulo,''),nullif(e.old_title,''),'la actividad');
  event_key:=e.transaction_id::text||':'||e.assignment_id::text;
  for recipient in select distinct unnest(e.old_team||team||
    array[ownership_private.creator('asignacion',e.assignment_id)]) loop
    if recipient is null or not exists(select 1 from public.perfiles where id=recipient) then continue; end if;
    kind:=null;
    if a.id is null then
      kind:='asignacion_eliminada'; title:='Asignacion cancelada';
      body:='La asignacion '||assignment_title||' ha sido eliminada';
    elsif recipient=any(e.old_team) and not recipient=any(team)
      and recipient is distinct from ownership_private.creator('asignacion',e.assignment_id) then
      kind:='asignacion_retirada'; title:='Asignacion cancelada';
      body:='Has sido removido de la asignacion '||assignment_title;
    elsif recipient=any(team) and not recipient=any(e.old_team) then
      kind:='asignacion_nueva'; title:='Nueva asignacion';
      body:=case when a.tipo_flujo='campo' then 'Se te ha asignado al montaje: ' else 'Se te ha asignado la tarea: ' end||assignment_title;
    elsif e.content_changed or
      (select array_agg(x order by x) from unnest(e.old_team) x) is distinct from
      (select array_agg(x order by x) from unnest(team) x) then
      kind:='asignacion_actualizada'; title:='Cambios en tu evento';
      body:='La asignacion '||assignment_title||' ha sido modificada';
    end if;
    if kind is not null then
      perform notification_private.emit(recipient,kind,title,body,'asignacion',e.assignment_id,a.estado,event_key);
    end if;
    if a.id is not null and (recipient=any(team) or recipient=ownership_private.creator('asignacion',e.assignment_id))
      and lower(a.nivel_prioridad)='alta' and lower(coalesce(e.old_priority,''))<>'alta' then
      perform notification_private.emit(recipient,'asignacion_urgente','URGENTE',
        'La asignacion '||assignment_title||' ha sido marcada como urgente.',
        'asignacion',e.assignment_id,a.estado,event_key||':urgente');
    end if;
  end loop;
  return null;
end;
$$;

create or replace function public.admin_employee_performance(p_month date,p_offset integer default 0,p_employee uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare start_at timestamptz; end_at timestamptz;
begin
  if auth.uid() is null or not public.account_is_approved() or not public.es_admin() then
    raise exception 'Solo administradores pueden consultar rendimiento' using errcode='42501'; end if;
  if p_month is null then raise exception 'Selecciona un mes'; end if;
  start_at:=date_trunc('month',p_month::timestamp) at time zone 'America/Santo_Domingo';
  end_at:=(date_trunc('month',p_month::timestamp)+interval '1 month') at time zone 'America/Santo_Domingo';
  return query
  with owned as materialized (select a.* from public.asignaciones a where a.created_by=auth.uid()),
  employees as (
    select p.id,coalesce(nullif(btrim(p.nombre_completo),''),'Sin nombre') nombre,
      coalesce(nullif(btrim(p.cargo),''),'Sin cargo') cargo
    from public.perfiles p join account_private.access access on access.user_id=p.id
    where access.estado='aprobada' and coalesce(p.rol,'tecnico')<>'admin'
      and (p_employee is null or p.id=p_employee) and p.id in (
        select e.perfil_id from public.asignacion_equipo e join owned a on a.id=e.asignacion_id
        union select c.usuario_id from public.confirmaciones_hitos c join owned a on a.id=c.asignacion_id
        union select sp.usuario_id from sla_private.participants sp join public.hitos_itinerario h on h.id=sp.hito_id
          join owned a on a.id=h.asignacion_id)
    order by lower(coalesce(p.nombre_completo,'')),p.id limit 100 offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object('id',e.id,'nombre',e.nombre,'cargo',e.cargo,
    'temprano',punctual.early,'a_tiempo',punctual.ontime,'tardio',punctual.late,
    'sin_confirmar',punctual.missing,'retraso_medio_minutos',punctual.delay,
    'notas_semanales',notes.weeks,'asignaciones',work.total,'completadas',work.completed,'activas',work.active,'vencidas',work.overdue)
  from employees e cross join lateral (
    select count(*) filter(where c.evaluacion='temprano') early,count(*) filter(where c.evaluacion='a_tiempo') ontime,
      count(*) filter(where c.evaluacion='tardio') late,count(*) filter(where c.id is null) missing,
      round(avg(greatest(0,extract(epoch from(c.created_at-c.hora_programada))/60)) filter(where c.evaluacion='tardio'),1) delay
    from (
      select w.hito_id,w.hora_programada from sla_private.participants sp join sla_private.windows w using(hito_id)
        join public.hitos_itinerario h on h.id=w.hito_id join owned a on a.id=h.asignacion_id where sp.usuario_id=e.id
      union select c.hito_id,c.hora_programada from public.confirmaciones_hitos c
        join owned a on a.id=c.asignacion_id where c.usuario_id=e.id
    ) scheduled left join public.confirmaciones_hitos c on c.hito_id=scheduled.hito_id and c.usuario_id=e.id
    where scheduled.hora_programada>=start_at and scheduled.hora_programada<end_at
      and(c.id is not null or scheduled.hora_programada<now())
  ) punctual cross join lateral (
    select jsonb_agg(jsonb_build_object('semana',week,'cantidad',amount) order by week) weeks from (
      select week,count(n.id) amount
      from generate_series(1,ceil(extract(day from(end_at at time zone 'America/Santo_Domingo')-interval '1 day')/7)::int) week
      left join public.notas_asignacion n on n.usuario_id=e.id and n.created_at>=start_at and n.created_at<end_at
        and n.asignacion_id in(select id from owned)
        and((extract(day from n.created_at at time zone 'America/Santo_Domingo')::int-1)/7)+1=week group by week
    ) weekly
  ) notes cross join lateral (
    select count(*) total,count(*) filter(where a.estado='completada') completed,
      count(*) filter(where coalesce(a.estado,'pendiente')<>'completada'
        and(a.estado='vencida' or coalesce(d.last_at,a.fecha_limite)<now())) overdue,
      count(*) filter(where coalesce(a.estado,'pendiente') not in('completada','vencida')
        and(coalesce(d.last_at,a.fecha_limite)>=now() or coalesce(d.last_at,a.fecha_limite) is null)) active
    from owned a left join lateral(select min(fecha_programada) first_at,max(fecha_programada) last_at
      from public.hitos_itinerario where asignacion_id=a.id) d on true
    where a.id in(select asignacion_id from public.asignacion_equipo where perfil_id=e.id
      union select asignacion_id from public.confirmaciones_hitos where usuario_id=e.id
      union select h.asignacion_id from sla_private.participants sp join public.hitos_itinerario h on h.id=sp.hito_id where sp.usuario_id=e.id)
      and coalesce(case when a.tipo_flujo='administrativa' then a.fecha_creacion else d.first_at end,a.fecha_creacion)<end_at
      and coalesce(d.last_at,a.fecha_limite,a.fecha_creacion)>=start_at
  ) work;
end;
$$;

create or replace function public.admin_employee_availability(
  p_inicio timestamptz,p_fin timestamptz,p_excluir uuid default null,p_offset integer default 0
) returns table(id uuid,nombre text,cargo text,rol text,disponible boolean,ocupado_desde timestamptz,ocupado_hasta timestamptz)
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not public.account_is_approved() or not public.es_admin() then
    raise exception 'Solo administradores pueden consultar disponibilidad' using errcode='42501'; end if;
  if p_inicio is null or p_fin is null or p_fin<p_inicio then raise exception 'Periodo invalido'; end if;
  if p_excluir is not null and not public.admin_owns_assignment(p_excluir) then
    raise exception 'Solo puedes excluir una asignacion propia' using errcode='42501'; end if;
  return query select p.id,p.nombre_completo,
    coalesce(nullif(btrim(p.cargo),''),nullif(btrim(u.raw_user_meta_data->>'cargo'),'')),p.rol,
    conflict.perfil_id is null,
    case when public.admin_owns_assignment(conflict.asignacion_id) then lower(conflict.periodo) end,
    case when public.admin_owns_assignment(conflict.asignacion_id) then upper(conflict.periodo) end
    from public.perfiles p join account_private.access a on a.user_id=p.id and a.estado='aprobada'
    left join auth.users u on u.id=p.id left join lateral(
      select b.perfil_id,b.asignacion_id,b.periodo from scheduling_private.bookings b
      where b.perfil_id=p.id and b.asignacion_id is distinct from p_excluir
        and b.periodo && tstzrange(p_inicio,p_fin,'[]')
      order by upper(b.periodo) desc limit 1
    ) conflict on true
    order by p.nombre_completo nulls last,p.id limit 200 offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on all functions in schema ownership_private from public,anon,authenticated;
revoke all on function public.check_in_milestone(uuid),public.undo_milestone_confirmation(uuid) from public,anon,authenticated;
grant execute on function public.check_in_milestone(uuid),public.undo_milestone_confirmation(uuid) to authenticated;
revoke all on function public.admin_owns_assignment(uuid),public.admin_owns_bulletin(uuid),
  public.admin_notification_visible(text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.admin_owns_assignment(uuid),public.admin_owns_bulletin(uuid),
  public.admin_notification_visible(text,uuid,uuid) to authenticated;
revoke all on function public.puede_ver_asignacion(uuid),public.can_supervise_assignment(uuid),
  public.can_read_milestone(uuid) from public,anon;
grant execute on function public.puede_ver_asignacion(uuid),public.can_supervise_assignment(uuid),
  public.can_read_milestone(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
