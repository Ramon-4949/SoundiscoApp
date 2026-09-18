-- Run after administrative_assignment_location_fix.sql and the CRUD migrations.
begin;
create extension if not exists btree_gist;
create schema if not exists scheduling_private;
revoke all on schema scheduling_private from public, anon, authenticated;

alter table public.perfiles add column if not exists cargo text;
update public.perfiles p set cargo = nullif(btrim(u.raw_user_meta_data->>'cargo'), '')
from auth.users u where u.id = p.id and nullif(btrim(p.cargo), '') is null
  and nullif(btrim(u.raw_user_meta_data->>'cargo'), '') is not null;

-- Repair the earlier creation RPC's date-only cast without replacing its
-- authorization or business validations. A milestone must retain its instant.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.admin_create_assignment(jsonb,uuid[],jsonb)'::regprocedure);
  definition := replace(definition,
    '(hito ->> ''fecha_programada'')::date',
    '(hito ->> ''fecha_programada'')::timestamptz');
  execute definition;
end;
$$;

create table if not exists scheduling_private.bookings (
  asignacion_id uuid not null references public.asignaciones(id) on delete cascade,
  perfil_id uuid not null references public.perfiles(id) on delete cascade,
  periodo tstzrange not null,
  primary key (asignacion_id, perfil_id),
  constraint employee_no_overlap exclude using gist (perfil_id with =, periodo with &&)
);
revoke all on scheduling_private.bookings from public, anon, authenticated;

create or replace function scheduling_private.sync_assignment(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  a public.asignaciones%rowtype;
  v_start timestamptz;
  v_end timestamptz;
begin
  select * into a from public.asignaciones where id = p_id for update;
  delete from scheduling_private.bookings where asignacion_id = p_id;
  if a.id is null or a.estado = 'completada' then return; end if;
  if a.tipo_flujo = 'administrativa' then
    v_start := a.fecha_creacion;
    v_end := a.fecha_limite;
    if v_start is null or v_end is null or v_end <= v_start then
      raise exception 'La fecha limite debe ser posterior a la creacion de la tarea administrativa.' using errcode = '23514';
    end if;
  elsif a.tipo_flujo = 'campo' then
    select min(fecha_programada), max(fecha_programada) into v_start, v_end
    from public.hitos_itinerario where asignacion_id = p_id;
    if v_start is null or exists (
      select 1 from public.hitos_itinerario where asignacion_id = p_id and fecha_programada is null
    ) then
      raise exception 'Completa las fechas de todos los hitos para reservar responsables.' using errcode = '23514';
    end if;
    if exists (
      select 1 from (
        select fecha_programada, lag(fecha_programada) over (order by orden) anterior
        from public.hitos_itinerario where asignacion_id = p_id
      ) h where h.fecha_programada < h.anterior
    ) then
      raise exception 'Las fechas de los hitos deben seguir el orden del itinerario.' using errcode = '23514';
    end if;
  else
    raise exception 'Tipo de asignacion no valido.' using errcode = '23514';
  end if;

  -- Closed intervals also protect single-milestone assignments and exact
  -- boundary collisions. The exclusion index arbitrates concurrent requests.
  insert into scheduling_private.bookings(asignacion_id, perfil_id, periodo)
  select distinct p_id, perfil_id, tstzrange(v_start, v_end, '[]')
  from public.asignacion_equipo where asignacion_id = p_id
  order by perfil_id;
exception when exclusion_violation then
  raise exception 'Uno de los responsables no esta disponible en este periodo. Revisa la seleccion.' using errcode = '23P01';
end;
$$;
revoke all on function scheduling_private.sync_assignment(uuid) from public, anon, authenticated;

create or replace function scheduling_private.assignment_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
declare old_id uuid; new_id uuid;
begin
  if tg_table_name = 'asignaciones' then
    if tg_op <> 'INSERT' then old_id := old.id; end if;
    if tg_op <> 'DELETE' then new_id := new.id; end if;
  else
    if tg_op <> 'INSERT' then old_id := old.asignacion_id; end if;
    if tg_op <> 'DELETE' then new_id := new.asignacion_id; end if;
  end if;
  if old_id is not null and old_id is distinct from new_id then
    perform scheduling_private.sync_assignment(old_id);
  end if;
  if new_id is not null then perform scheduling_private.sync_assignment(new_id); end if;
  return null;
end;
$$;
revoke all on function scheduling_private.assignment_changed() from public, anon, authenticated;

-- Defer until the RPC has finished replacing the team and itinerary.
drop trigger if exists availability_assignment on public.asignaciones;
create constraint trigger availability_assignment after insert or update or delete on public.asignaciones
deferrable initially deferred for each row execute function scheduling_private.assignment_changed();
drop trigger if exists availability_team on public.asignacion_equipo;
create constraint trigger availability_team after insert or update or delete on public.asignacion_equipo
deferrable initially deferred for each row execute function scheduling_private.assignment_changed();
drop trigger if exists availability_milestones on public.hitos_itinerario;
create constraint trigger availability_milestones after insert or update or delete on public.hitos_itinerario
deferrable initially deferred for each row execute function scheduling_private.assignment_changed();

-- Existing assignments must also reserve their employees. If historical data
-- overlaps or lacks dates, the migration rolls back instead of ignoring it.
do $$
declare assignment record;
begin
  for assignment in select id from public.asignaciones order by id loop
    begin
      perform scheduling_private.sync_assignment(assignment.id);
    exception when others then
      raise exception 'Revisa la asignacion % antes de activar disponibilidad: %', assignment.id, sqlerrm;
    end;
  end loop;
end;
$$;

create or replace function public.admin_employee_availability(
  p_inicio timestamptz, p_fin timestamptz, p_excluir uuid default null, p_offset integer default 0
)
returns table(id uuid, nombre text, cargo text, rol text, disponible boolean,
  ocupado_desde timestamptz, ocupado_hasta timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not coalesce(public.es_admin(), false) then
    raise exception 'Solo administradores pueden consultar disponibilidad.' using errcode = '42501';
  end if;
  if p_inicio is null or p_fin is null or p_fin < p_inicio then
    raise exception 'El periodo de la asignacion no es valido.' using errcode = '23514';
  end if;
  return query
    select p.id, p.nombre_completo,
      coalesce(nullif(btrim(p.cargo), ''), nullif(btrim(u.raw_user_meta_data->>'cargo'), '')), p.rol,
      conflict.perfil_id is null,
      lower(conflict.periodo), upper(conflict.periodo)
    from public.perfiles p
    left join auth.users u on u.id = p.id
    left join lateral (
      select b.perfil_id, b.periodo from scheduling_private.bookings b
      where b.perfil_id = p.id
        and b.asignacion_id is distinct from p_excluir
        and b.periodo && tstzrange(p_inicio, p_fin, '[]')
      order by upper(b.periodo) desc limit 1
    ) conflict on true
    order by p.nombre_completo nulls last, p.id
    limit 200 offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
revoke all on function public.admin_employee_availability(timestamptz,timestamptz,uuid,integer) from public, anon;
grant execute on function public.admin_employee_availability(timestamptz,timestamptz,uuid,integer) to authenticated;
commit;
