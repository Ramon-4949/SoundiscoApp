-- Apply AFTER the existing SLA, account access, notifications and performance migrations.
-- Deploy the matching iOS build after this transaction succeeds.
begin;
create schema if not exists milestone_private;
revoke all on schema milestone_private from public, anon, authenticated;
create table if not exists milestone_private.migrations (name text primary key);

create table if not exists public.hitos_colaboradores (
  hito_id uuid not null references public.hitos_itinerario(id) on delete cascade,
  usuario_id uuid not null references public.perfiles(id) on delete cascade,
  estado text not null default 'sin_confirmar'
    check (estado in ('sin_confirmar','temprano','a_tiempo','tardio')),
  confirmado_at timestamptz,
  hora_programada timestamptz,
  primary key(hito_id,usuario_id),
  check ((confirmado_at is null and estado='sin_confirmar') or
    (confirmado_at is not null and hora_programada is not null and estado<>'sin_confirmar'))
);
create index if not exists hitos_colaboradores_usuario on public.hitos_colaboradores(usuario_id,hito_id);
create table if not exists public.asignacion_supervisores (
  asignacion_id uuid not null references public.asignaciones(id) on delete cascade,
  usuario_id uuid not null references public.perfiles(id) on delete cascade,
  primary key(asignacion_id,usuario_id)
);
create index if not exists supervisors_user on public.asignacion_supervisores(usuario_id,asignacion_id);

-- Migrate existing memberships once; never infer a confirmation for an employee.
do $$ begin
  if not exists(select 1 from milestone_private.migrations where name='memberships') then
    insert into public.hitos_colaboradores(hito_id,usuario_id,estado,confirmado_at,hora_programada)
    select h.id,e.perfil_id,coalesce(c.evaluacion,'sin_confirmar'),c.created_at,
      coalesce(c.hora_programada,h.fecha_programada)
    from public.hitos_itinerario h join public.asignacion_equipo e on e.asignacion_id=h.asignacion_id
    left join public.confirmaciones_hitos c on c.hito_id=h.id and c.usuario_id=e.perfil_id
    on conflict do nothing;
    insert into public.hitos_colaboradores(hito_id,usuario_id,estado,confirmado_at,hora_programada)
    select hito_id,usuario_id,evaluacion,created_at,hora_programada from public.confirmaciones_hitos
    on conflict do nothing;
    insert into milestone_private.migrations values('memberships');
  end if;
end $$;

create or replace function public.can_supervise_assignment(p_assignment uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and public.account_is_approved() and
    (public.es_admin() or exists(select 1 from public.asignacion_supervisores
      where asignacion_id=p_assignment and usuario_id=auth.uid()));
$$;
create or replace function public.can_read_milestone(p_hito uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and public.account_is_approved() and exists(
    select 1 from public.hitos_itinerario h where h.id=p_hito and
      (public.can_supervise_assignment(h.asignacion_id) or exists(select 1
        from public.hitos_colaboradores c where c.hito_id=h.id and c.usuario_id=auth.uid())));
$$;
revoke all on function public.can_supervise_assignment(uuid),public.can_read_milestone(uuid) from public,anon;
grant execute on function public.can_supervise_assignment(uuid),public.can_read_milestone(uuid) to authenticated;
create or replace function public.can_supervise_profile(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select public.account_is_approved() and exists(select 1 from public.hitos_colaboradores c
    join public.hitos_itinerario h on h.id=c.hito_id
    where c.usuario_id=p_user and public.can_supervise_assignment(h.asignacion_id));
$$;
revoke all on function public.can_supervise_profile(uuid) from public,anon;
grant execute on function public.can_supervise_profile(uuid) to authenticated;
drop policy if exists supervisor_member_names on public.perfiles;
create policy supervisor_member_names on public.perfiles for select to authenticated
using (public.can_supervise_profile(id));
alter table public.hitos_colaboradores enable row level security;
alter table public.asignacion_supervisores enable row level security;
revoke all on public.hitos_colaboradores,public.asignacion_supervisores from public,anon,authenticated;
grant select on public.hitos_colaboradores,public.asignacion_supervisores to authenticated;
drop policy if exists milestone_members_read on public.hitos_colaboradores;
create policy milestone_members_read on public.hitos_colaboradores for select to authenticated
using (public.account_is_approved() and (usuario_id=auth.uid() or exists(
  select 1 from public.hitos_itinerario h where h.id=hito_id and public.can_supervise_assignment(h.asignacion_id))));
drop policy if exists supervisors_read on public.asignacion_supervisores;
create policy supervisors_read on public.asignacion_supervisores for select to authenticated
using (public.can_supervise_assignment(asignacion_id));
-- Restrictive policy prevents pre-existing event-wide policies from leaking other milestones.
drop policy if exists granular_milestones on public.hitos_itinerario;
create policy granular_milestones on public.hitos_itinerario as restrictive for select to authenticated
using (public.can_read_milestone(id));
drop policy if exists granular_milestones_read on public.hitos_itinerario;
create policy granular_milestones_read on public.hitos_itinerario for select to authenticated
using (public.can_read_milestone(id));

-- Preserve existing CRUD validation and execute it only through the new wrappers.
do $$ begin
  if to_regprocedure('milestone_private.create_legacy(jsonb,uuid[],jsonb)') is null then
    alter function public.admin_create_assignment(jsonb,uuid[],jsonb) rename to create_legacy;
    alter function public.create_legacy(jsonb,uuid[],jsonb) set schema milestone_private;
    alter function public.admin_update_assignment(uuid,jsonb,uuid[],jsonb) rename to update_legacy;
    alter function public.update_legacy(uuid,jsonb,uuid[],jsonb) set schema milestone_private;
  end if;
end $$;

create or replace function milestone_private.validate_members(p_hitos jsonb,p_supervisores jsonb)
returns uuid[] language plpgsql security definer set search_path='' as $$
declare j jsonb; members uuid[]; supervisors uuid[];
begin
  if auth.uid() is null or not public.account_is_approved() or not public.es_admin() then
    raise exception 'Solo administradores pueden gestionar hitos' using errcode='42501'; end if;
  if jsonb_typeof(p_hitos) is distinct from 'array' or jsonb_array_length(p_hitos)=0 then
    raise exception 'Agrega al menos un hito'; end if;
  for j in select value from jsonb_array_elements(p_hitos) loop
    if jsonb_typeof(j->'colaboradores') is distinct from 'array' then
      raise exception 'Actualiza la app: selecciona colaboradores en cada hito'; end if;
    if jsonb_array_length(j->'colaboradores')=0 then raise exception 'Cada hito necesita colaboradores'; end if;
  end loop;
  if jsonb_typeof(p_supervisores) is distinct from 'array' then raise exception 'Supervisores invalidos'; end if;
  select coalesce(array_agg(distinct u.value::uuid),'{}') into members
    from jsonb_array_elements(p_hitos) h cross join lateral jsonb_array_elements_text(h->'colaboradores') u;
  select coalesce(array_agg(distinct value::uuid),'{}') into supervisors from jsonb_array_elements_text(p_supervisores);
  if exists(select 1 from unnest(members||supervisors) u where not exists(
    select 1 from public.perfiles p join account_private.access a on a.user_id=p.id
    where p.id=u and a.estado='aprobada')) then
    raise exception 'Selecciona usuarios con acceso aprobado'; end if;
  return array(select distinct unnest(members||supervisors));
end $$;

create or replace function milestone_private.save_members(p_assignment uuid,p_hitos jsonb,p_supervisores jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_hito jsonb;
begin
  -- Confirmed records cannot be silently removed or have their schedule rewritten.
  if exists(select 1 from public.hitos_colaboradores c join public.hitos_itinerario h on h.id=c.hito_id
    where h.asignacion_id=p_assignment and c.confirmado_at is not null and not exists(
      select 1 from jsonb_array_elements(p_hitos) j
      cross join lateral jsonb_array_elements_text(j->'colaboradores') u
      where (j->>'id')::uuid=h.id and u.value::uuid=c.usuario_id)) then
    raise exception 'No puedes retirar colaboradores que ya confirmaron'; end if;
  delete from public.hitos_colaboradores c using public.hitos_itinerario h
    where h.id=c.hito_id and h.asignacion_id=p_assignment and not exists(
      select 1 from jsonb_array_elements(p_hitos) j
      cross join lateral jsonb_array_elements_text(j->'colaboradores') u
      where (j->>'id')::uuid=h.id and u.value::uuid=c.usuario_id);
  for v_hito in select value from jsonb_array_elements(p_hitos) loop
    insert into public.hitos_colaboradores(hito_id,usuario_id,hora_programada)
      select (v_hito->>'id')::uuid,value::uuid,(v_hito->>'fecha_programada')::timestamptz
      from jsonb_array_elements_text(v_hito->'colaboradores') on conflict do nothing;
  end loop;
  update public.hitos_colaboradores c set hora_programada=h.fecha_programada
    from public.hitos_itinerario h where h.id=c.hito_id and h.asignacion_id=p_assignment and c.confirmado_at is null;
  delete from public.asignacion_supervisores where asignacion_id=p_assignment;
  insert into public.asignacion_supervisores select distinct p_assignment,value::uuid
    from jsonb_array_elements_text(p_supervisores);
  -- Keep the existing aggregated metrics contract, with only actual milestone members.
  insert into sla_private.windows(hito_id,hora_programada)
    select id,fecha_programada from public.hitos_itinerario where asignacion_id=p_assignment
    on conflict(hito_id) do update set hora_programada=excluded.hora_programada;
  delete from sla_private.participants where hito_id in(select id from public.hitos_itinerario where asignacion_id=p_assignment);
  insert into sla_private.participants select c.hito_id,c.usuario_id from public.hitos_colaboradores c
    join public.hitos_itinerario h on h.id=c.hito_id where h.asignacion_id=p_assignment;
end $$;

create or replace function sla_private.protect_history()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from public.confirmaciones_hitos where hito_id=old.id) then
    if tg_op='DELETE' then
      if exists(select 1 from public.asignaciones where id=old.asignacion_id)
        and not (coalesce(current_setting('soundisco.deleting_assignment',true),'')=old.asignacion_id::text
          and public.es_admin()) then
        raise exception 'No puedes eliminar un hito con confirmaciones'; end if;
      return old;
    end if;
    if (new.asignacion_id,new.orden,new.fecha_programada) is distinct from (old.asignacion_id,old.orden,old.fecha_programada) then
      raise exception 'No puedes cambiar el horario ni orden de un hito confirmado'; end if;
  end if;
  return new;
end $$;

create or replace function public.admin_delete_assignment(p_asignacion_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not public.account_is_approved() or not public.es_admin() then
    raise exception 'Solo administradores pueden eliminar asignaciones' using errcode='42501'; end if;
  perform 1 from public.asignaciones where id=p_asignacion_id for update;
  if not found then raise exception 'La asignacion ya no existe'; end if;
  perform set_config('soundisco.deleting_assignment',p_asignacion_id::text,true);
  delete from public.checklist_equipos where asignacion_id=p_asignacion_id;
  update public.notificaciones_app set asignacion_relacionada_id=null where asignacion_relacionada_id=p_asignacion_id;
  delete from public.hitos_itinerario where asignacion_id=p_asignacion_id;
  delete from public.asignacion_equipo where asignacion_id=p_asignacion_id;
  delete from public.asignaciones where id=p_asignacion_id;
end $$;
drop trigger if exists granular_protect_delete on public.hitos_itinerario;
create trigger granular_protect_delete before delete on public.hitos_itinerario
for each row execute function sla_private.protect_history();

-- The cron may expire an assignment, but never completes it on behalf of absent people.
create or replace function sla_private.advance(p_assignment uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.asignaciones where id=p_assignment for update;
  with progress as (
    select h.id,count(c.usuario_id)>0 and bool_and(c.confirmado_at is not null) done,
      max(c.confirmado_at) confirmed_at
    from public.hitos_itinerario h left join public.hitos_colaboradores c on c.hito_id=h.id
    where h.asignacion_id=p_assignment group by h.id
  )
  update public.hitos_itinerario h set completado=p.done,
    estado_hito=case when p.done then 'completado' else 'en_curso' end,
    hora_real_completado=case when p.done then p.confirmed_at else null end
  from progress p where h.id=p.id and (h.completado,h.estado_hito,h.hora_real_completado)
    is distinct from (p.done,case when p.done then 'completado' else 'en_curso' end,
      case when p.done then p.confirmed_at else null end);
  update public.asignaciones a set estado=case
    when exists(select 1 from public.hitos_itinerario where asignacion_id=a.id) and not exists(
      select 1 from public.hitos_itinerario where asignacion_id=a.id and not coalesce(completado,false)) then 'completada'
    when public.assignment_deadline(a.id)<clock_timestamp() then 'vencida'
    when exists(select 1 from public.confirmaciones_hitos where asignacion_id=a.id) then 'en_curso'
    else 'pendiente' end where a.id=p_assignment;
end $$;

create or replace function public.admin_create_assignment(p_asignacion jsonb,p_empleados uuid[],p_hitos jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare aid uuid; team uuid[]; supervisors jsonb:=coalesce(p_asignacion->'supervisores','[]'::jsonb);
begin
  team:=milestone_private.validate_members(p_hitos,supervisors);
  aid:=milestone_private.create_legacy(p_asignacion,team,p_hitos);
  perform milestone_private.save_members(aid,p_hitos,supervisors);
  perform sla_private.advance(aid);
  return aid;
end $$;
create or replace function public.admin_update_assignment(p_asignacion_id uuid,p_asignacion jsonb,p_empleados uuid[],p_hitos jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare team uuid[]; supervisors jsonb:=coalesce(p_asignacion->'supervisores','[]'::jsonb);
begin
  team:=milestone_private.validate_members(p_hitos,supervisors);
  perform 1 from public.asignaciones where id=p_asignacion_id for update;
  perform milestone_private.update_legacy(p_asignacion_id,p_asignacion,team,p_hitos);
  perform milestone_private.save_members(p_asignacion_id,p_hitos,supervisors);
  perform sla_private.advance(p_asignacion_id);
end $$;

create or replace function public.check_in_milestone(p_hito_id uuid)
returns void language plpgsql security definer set search_path='' as $$
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
    raise exception 'No estas asignado a este hito' using errcode='42501'; end if;
  if exists(select 1 from public.hitos_colaboradores where hito_id=h.id and usuario_id=auth.uid() and confirmado_at is not null) then return; end if;
  select m.fecha_programada into deadline from public.hitos_itinerario m
    join public.hitos_colaboradores c on c.hito_id=m.id
    where m.asignacion_id=aid and c.usuario_id=auth.uid() order by m.orden desc limit 1;
  checked:=clock_timestamp();
  if deadline is null or h.fecha_programada is null then raise exception 'Falta la fecha limite del hito'; end if;
  if checked>deadline then raise exception 'Tu plazo final vencio. No puedes confirmar hitos pendientes.' using errcode='23514'; end if;
  if exists(select 1 from public.hitos_itinerario m join public.hitos_colaboradores c on c.hito_id=m.id
    where m.asignacion_id=aid and m.orden<h.orden and c.usuario_id=auth.uid() and c.confirmado_at is null) then
    raise exception 'Confirma primero tu hito anterior' using errcode='23514'; end if;
  evaluation:=case when checked<h.fecha_programada then 'temprano'
    when checked=h.fecha_programada then 'a_tiempo' else 'tardio' end;
  update public.hitos_colaboradores set confirmado_at=checked,hora_programada=h.fecha_programada,estado=evaluation
    where hito_id=h.id and usuario_id=auth.uid();
  insert into public.confirmaciones_hitos(asignacion_id,hito_id,usuario_id,created_at,hora_programada,evaluacion)
    values(aid,h.id,auth.uid(),checked,h.fecha_programada,evaluation);
  -- Individual notifications go only to admins, including partial group check-ins.
  select coalesce(nombre_completo,'Un colaborador') into actor_name from public.perfiles where id=auth.uid();
  for recipient in select id from public.perfiles where rol='admin' loop
    perform notification_private.emit(recipient,'hito_completado','Confirmacion de Hito',
      actor_name||' confirmo '||h.descripcion,'asignacion',aid,null,
      'individual:'||h.id::text||':'||auth.uid()::text);
  end loop;
  perform set_config('soundisco.individual_checkin','true',true);
  perform sla_private.advance(aid);
  if exists(select 1 from public.asignaciones where id=aid and estado='completada') then
    for recipient in select id from public.perfiles where rol='admin' loop
      perform notification_private.emit(recipient,'asignacion_completada','Asignacion completada',
        'Todos los colaboradores completaron sus hitos','asignacion',aid,'completada',
        'individual-complete:'||aid::text||':'||txid_current()::text);
    end loop;
  end if;
end $$;

-- Exclusion constraints still arbitrate concurrent admin saves. Reservations now
-- cover each employee's own first-to-last milestone, not the whole event.
create or replace function scheduling_private.sync_assignment(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare a public.asignaciones%rowtype;
begin
  select * into a from public.asignaciones where id=p_id for update;
  delete from scheduling_private.bookings where asignacion_id=p_id;
  if a.id is null or a.estado='completada' then return; end if;
  insert into scheduling_private.bookings(asignacion_id,perfil_id,periodo)
  select p_id,usuario_id,tstzrange(case when a.tipo_flujo='administrativa' then a.fecha_creacion
    else min(fecha_programada) end,max(fecha_programada),'[]')
  from (
    select c.usuario_id,h.fecha_programada from public.hitos_colaboradores c
      join public.hitos_itinerario h on h.id=c.hito_id where h.asignacion_id=p_id
    union all
    select s.usuario_id,h.fecha_programada from public.asignacion_supervisores s
      join public.hitos_itinerario h on h.asignacion_id=s.asignacion_id where s.asignacion_id=p_id
  ) members group by usuario_id order by usuario_id;
exception when exclusion_violation then
  raise exception 'Un colaborador no esta disponible entre sus hitos asignados. Revisa la seleccion.' using errcode='23P01';
end $$;

-- Do not broadcast a colleague's progress through the older event-wide trigger.
do $$ declare definition text; begin
  definition:=pg_get_functiondef('notification_private.flush_assignment()'::regprocedure);
  if position('soundisco.individual_checkin' in definition)=0 then
    definition:=replace(definition,'if not found then return null; end if;',
      'if not found then return null; end if;
       if current_setting(''soundisco.individual_checkin'',true) = ''true'' then return null; end if;');
    execute definition;
  end if;
end $$;

create or replace function public.generate_notification_reminders()
returns void language plpgsql security definer set search_path='' as $$
declare r record;
begin
  if not pg_try_advisory_xact_lock(81420931) then return; end if;
  for r in select h.*,c.usuario_id from public.hitos_itinerario h
    join public.hitos_colaboradores c on c.hito_id=h.id
    where c.confirmado_at is null and h.fecha_programada between now() and now()+interval '15 minutes'
  loop
    perform notification_private.emit(r.usuario_id,'recordatorio','Alerta de Hito',
      'El hito '||r.descripcion||' esta por vencer pronto','asignacion',r.asignacion_id,null,
      'personal-reminder:'||r.id::text||':'||extract(epoch from r.fecha_programada)::text);
  end loop;
  for r in select a.id,a.titulo,c.usuario_id,max(h.fecha_programada) deadline
    from public.hitos_colaboradores c join public.hitos_itinerario h on h.id=c.hito_id
    join public.asignaciones a on a.id=h.asignacion_id
    group by a.id,a.titulo,c.usuario_id
    having bool_or(c.confirmado_at is null) and max(h.fecha_programada) between now() and now()+interval '15 minutes'
  loop
    perform notification_private.emit(r.usuario_id,'recordatorio','Cierre de Asignacion',
      'Tu plazo en la asignacion '||r.titulo||' esta proximo a vencer','asignacion',r.id,null,
      'personal-close:'||r.id::text||':'||extract(epoch from r.deadline)::text);
  end loop;
end $$;

-- Refresh metric participants without rewriting historical confirmations or their SLA labels.
insert into sla_private.windows(hito_id,hora_programada)
select id,fecha_programada from public.hitos_itinerario where fecha_programada is not null on conflict do nothing;
delete from sla_private.participants;
insert into sla_private.participants select c.hito_id,c.usuario_id from public.hitos_colaboradores c
join sla_private.windows w on w.hito_id=c.hito_id;
do $$ declare definition text; begin
  if to_regprocedure('public.admin_employee_performance(date,integer,uuid)') is not null then
    definition:=pg_get_functiondef('public.admin_employee_performance(date,integer,uuid)'::regprocedure);
    definition:=replace(definition,'c.created_at-c.hora_programada-interval ''15 minutes''','c.created_at-c.hora_programada');
    definition:=replace(definition,'scheduled.hora_programada+interval ''15 minutes''','scheduled.hora_programada');
    execute definition;
  end if;
end $$;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='hitos_colaboradores') then
      alter publication supabase_realtime add table public.hitos_colaboradores;
    end if;
  end if;
end $$;
revoke all on all functions in schema milestone_private from public,anon,authenticated;
revoke all on all tables in schema milestone_private from public,anon,authenticated;
revoke all on function public.admin_create_assignment(jsonb,uuid[],jsonb),
  public.admin_update_assignment(uuid,jsonb,uuid[],jsonb) from public,anon;
grant execute on function public.admin_create_assignment(jsonb,uuid[],jsonb),
  public.admin_update_assignment(uuid,jsonb,uuid[],jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
