-- Ejecutar despues de admin_crud_completion.sql.
-- Permite agregar hitos y eliminar hitos pendientes sin perder el historial completado.
begin;

create or replace function public.admin_update_assignment(
  p_asignacion_id uuid, p_asignacion jsonb, p_empleados uuid[], p_hitos jsonb
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old public.asignaciones%rowtype;
  v_hito jsonb;
  v_progress boolean;
  v_count integer;
begin
  if auth.uid() is null or not coalesce(public.es_admin(), false) then
    raise exception 'Solo administradores pueden editar asignaciones' using errcode = '42501';
  end if;

  select * into v_old
  from public.asignaciones
  where id = p_asignacion_id
  for update;
  if not found then
    raise exception 'La asignacion ya no existe' using errcode = 'P0002';
  end if;

  perform 1
  from public.hitos_itinerario
  where asignacion_id = p_asignacion_id
  order by orden
  for update;

  if nullif(btrim(p_asignacion->>'titulo'), '') is null
     or coalesce(cardinality(p_empleados), 0) = 0
     or coalesce(p_asignacion->>'nivel_prioridad', '') not in ('baja', 'media', 'alta') then
    raise exception 'Revisa titulo, responsables y prioridad' using errcode = '23514';
  end if;
  if (p_asignacion->>'tipo_flujo') is distinct from v_old.tipo_flujo then
    raise exception 'No se puede cambiar el tipo de una asignacion existente' using errcode = '23514';
  end if;
  if jsonb_typeof(p_hitos) is distinct from 'array' then
    raise exception 'Itinerario invalido' using errcode = '23514';
  end if;

  v_count := jsonb_array_length(p_hitos);
  if v_count = 0 then
    raise exception 'La asignacion requiere al menos un hito' using errcode = '23514';
  end if;

  if v_old.tipo_flujo = 'campo' then
    if nullif(btrim(p_asignacion->>'ubicacion'), '') is null then
      raise exception 'Campo requiere ubicacion e itinerario' using errcode = '23514';
    end if;
  elsif nullif(p_asignacion->>'ubicacion', '') is not null then
    raise exception 'Administracion no admite ubicacion' using errcode = '23514';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_hitos) h
    where nullif(btrim(h->>'descripcion'), '') is null
      or nullif(h->>'fecha_programada', '') is null
      or nullif(h->>'id', '') is null
      or coalesce((h->>'orden')::integer, 0) < 1
  ) then
    raise exception 'Cada hito requiere titulo, fecha y orden' using errcode = '23514';
  end if;
  if (select count(distinct h->>'id') from jsonb_array_elements(p_hitos) h) <> v_count
    or (select count(distinct h->>'orden') from jsonb_array_elements(p_hitos) h) <> v_count then
    raise exception 'Los hitos deben tener IDs y ordenes unicos' using errcode = '23514';
  end if;
  if exists (
    select 1 from (
      select (h->>'fecha_programada')::timestamptz fecha,
        lag((h->>'fecha_programada')::timestamptz)
          over (order by (h->>'orden')::integer) anterior
      from jsonb_array_elements(p_hitos) h
    ) ordered_hitos
    where fecha < anterior
  ) then
    raise exception 'Las fechas de los hitos deben seguir el orden del itinerario' using errcode = '23514';
  end if;
  if v_old.tipo_flujo = 'administrativa' and exists (
    select 1 from jsonb_array_elements(p_hitos) h
    where (h->>'fecha_programada')::timestamptz < v_old.fecha_creacion
  ) then
    raise exception 'Los hitos administrativos no pueden ser anteriores a la creacion' using errcode = '23514';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_hitos) j
    join public.hitos_itinerario h on h.id = (j->>'id')::uuid
    where h.asignacion_id <> p_asignacion_id
  ) then
    raise exception 'Hito ajeno a la asignacion' using errcode = '42501';
  end if;

  select exists (
    select 1 from public.hitos_itinerario
    where asignacion_id = p_asignacion_id
      and (coalesce(completado, false) or estado_hito = 'completado')
  ) into v_progress;

  if v_progress and exists (
    select 1 from public.hitos_itinerario h
    where h.asignacion_id = p_asignacion_id
      and (coalesce(h.completado, false) or h.estado_hito = 'completado')
      and not exists (
        select 1 from jsonb_array_elements(p_hitos) j
        where (j->>'id')::uuid = h.id and (j->>'orden')::integer = h.orden
      )
  ) then
    raise exception 'Los hitos completados deben conservarse en su posicion original' using errcode = '23514';
  end if;

  update public.asignaciones
  set titulo = btrim(p_asignacion->>'titulo'),
    ubicacion = nullif(btrim(p_asignacion->>'ubicacion'), ''),
    nivel_prioridad = p_asignacion->>'nivel_prioridad',
    instrucciones = nullif(btrim(p_asignacion->>'instrucciones'), ''),
    fecha_limite = case when v_old.tipo_flujo = 'administrativa' then (
      select (h->>'fecha_programada')::timestamptz
      from jsonb_array_elements(p_hitos) h
      order by (h->>'orden')::integer desc
      limit 1
    ) else null end
  where id = p_asignacion_id;

  delete from public.asignacion_equipo
  where asignacion_id = p_asignacion_id;
  insert into public.asignacion_equipo(asignacion_id, perfil_id)
    select p_asignacion_id, e
    from (select distinct unnest(p_empleados) e) s;

  delete from public.hitos_itinerario h
  where asignacion_id = p_asignacion_id
    and not exists (
      select 1 from jsonb_array_elements(p_hitos) j
      where (j->>'id')::uuid = h.id
    );

  for v_hito in select value from jsonb_array_elements(p_hitos) loop
    insert into public.hitos_itinerario(
      id, asignacion_id, orden, descripcion, hora_estimada,
      fecha_programada, estado_hito, completado
    ) values (
      (v_hito->>'id')::uuid, p_asignacion_id, (v_hito->>'orden')::integer,
      btrim(v_hito->>'descripcion'), (v_hito->>'hora_estimada')::time,
      (v_hito->>'fecha_programada')::timestamptz, 'bloqueado', false
    )
    on conflict(id) do update
    set orden = excluded.orden,
      descripcion = excluded.descripcion,
      hora_estimada = excluded.hora_estimada,
      fecha_programada = excluded.fecha_programada;
  end loop;

  update public.hitos_itinerario
  set estado_hito = 'bloqueado'
  where asignacion_id = p_asignacion_id
    and not (coalesce(completado, false) or estado_hito = 'completado');
  update public.hitos_itinerario
  set estado_hito = 'en_curso'
  where id = (
    select id from public.hitos_itinerario
    where asignacion_id = p_asignacion_id
      and not (coalesce(completado, false) or estado_hito = 'completado')
    order by orden
    limit 1
  );

  update public.asignaciones
  set estado = case
    when not exists (
      select 1 from public.hitos_itinerario h
      where h.asignacion_id = p_asignacion_id
        and not (coalesce(h.completado, false) or h.estado_hito = 'completado')
    ) then 'completada'
    when exists (
      select 1 from public.hitos_itinerario h
      where h.asignacion_id = p_asignacion_id
        and (coalesce(h.completado, false) or h.estado_hito = 'completado')
    ) then 'en_curso'
    else 'pendiente'
  end
  where id = p_asignacion_id;
end;
$$;

revoke all on function public.admin_update_assignment(uuid, jsonb, uuid[], jsonb) from public, anon;
grant execute on function public.admin_update_assignment(uuid, jsonb, uuid[], jsonb) to authenticated;

commit;
