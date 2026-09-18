-- Administrative assignments do not have a physical event location. In that
-- flow, NULL means "not applicable / SounDisco offices".
begin;

alter table public.asignaciones
  alter column ubicacion drop not null;

create or replace function public.admin_create_assignment(
  p_asignacion jsonb,
  p_empleados uuid[],
  p_hitos jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment_id uuid := coalesce(
    nullif(p_asignacion ->> 'id', '')::uuid,
    gen_random_uuid()
  );
  v_tipo text := nullif(btrim(p_asignacion ->> 'tipo_flujo'), '');
  v_titulo text := nullif(btrim(p_asignacion ->> 'titulo'), '');
  v_ubicacion text := nullif(btrim(p_asignacion ->> 'ubicacion'), '');
  v_prioridad text := nullif(btrim(p_asignacion ->> 'nivel_prioridad'), '');
  v_fecha_creacion timestamptz := coalesce(
    nullif(p_asignacion ->> 'fecha_creacion', '')::timestamptz,
    now()
  );
  v_fecha_limite timestamptz;
  v_hito_count integer;
  v_hito jsonb;
begin
  if auth.uid() is null or not coalesce(public.es_admin(), false) then
    raise exception 'Solo los administradores pueden crear asignaciones.';
  end if;

  if v_titulo is null then
    raise exception 'El titulo de la asignacion es obligatorio.';
  end if;

  if v_tipo not in ('campo', 'administrativa') then
    raise exception 'El tipo de flujo no es valido.';
  end if;

  if v_prioridad not in ('baja', 'media', 'alta') then
    raise exception 'El nivel de prioridad no es valido.';
  end if;

  if coalesce(cardinality(p_empleados), 0) = 0 then
    raise exception 'Selecciona al menos un responsable.';
  end if;

  if jsonb_typeof(coalesce(p_hitos, '[]'::jsonb)) <> 'array' then
    raise exception 'Los hitos deben enviarse como un arreglo.';
  end if;

  v_hito_count := jsonb_array_length(coalesce(p_hitos, '[]'::jsonb));

  if v_tipo = 'campo' then
    if v_ubicacion is null then
      raise exception 'Las operaciones de campo requieren ubicacion.';
    end if;

    if v_hito_count = 0 then
      raise exception 'Las operaciones de campo requieren al menos un hito.';
    end if;
  else
    if v_ubicacion is not null then
      raise exception 'Las tareas administrativas no deben incluir ubicacion.';
    end if;

  end if;

  if v_hito_count = 0 then
    raise exception 'La asignacion requiere al menos un hito.';
  end if;

    for v_hito in select value from jsonb_array_elements(p_hitos)
    loop
      if nullif(v_hito ->> 'id', '') is null
        or nullif(btrim(v_hito ->> 'descripcion'), '') is null
        or nullif(v_hito ->> 'orden', '') is null
        or nullif(v_hito ->> 'fecha_programada', '') is null
        or nullif(v_hito ->> 'hora_estimada', '') is null then
        raise exception 'Cada hito requiere id, titulo, orden, fecha y hora.';
      end if;
    end loop;

    if (
      select count(distinct value ->> 'id')
      from jsonb_array_elements(p_hitos)
    ) <> v_hito_count then
      raise exception 'Los identificadores de los hitos no pueden repetirse.';
    end if;

    if (
      select count(distinct (value ->> 'orden')::integer)
      from jsonb_array_elements(p_hitos)
    ) <> v_hito_count then
      raise exception 'El orden de los hitos no puede repetirse.';
    end if;

  if exists (
    select 1 from (
      select (h ->> 'fecha_programada')::timestamptz as fecha,
        lag((h ->> 'fecha_programada')::timestamptz)
          over (order by (h ->> 'orden')::integer) as anterior
      from jsonb_array_elements(p_hitos) h
    ) ordered_hitos
    where fecha < anterior
  ) then
    raise exception 'Las fechas de los hitos deben seguir el orden del itinerario.';
  end if;

  if v_tipo = 'administrativa' and exists (
    select 1 from jsonb_array_elements(p_hitos) h
    where (h ->> 'fecha_programada')::timestamptz
      < v_fecha_creacion
  ) then
    raise exception 'Los hitos administrativos no pueden ser anteriores a la creacion.';
  end if;

  if v_tipo = 'administrativa' then
    select (h ->> 'fecha_programada')::timestamptz
      into v_fecha_limite
    from jsonb_array_elements(p_hitos) h
    order by (h ->> 'orden')::integer desc
    limit 1;
  end if;

  insert into public.asignaciones (
    id,
    titulo,
    tipo_flujo,
    ubicacion,
    nivel_prioridad,
    instrucciones,
    estado,
    fecha_creacion,
    fecha_limite
  ) values (
    v_assignment_id,
    v_titulo,
    v_tipo,
    case when v_tipo = 'campo' then v_ubicacion else null end,
    v_prioridad,
    nullif(btrim(p_asignacion ->> 'instrucciones'), ''),
    coalesce(nullif(p_asignacion ->> 'estado', ''), 'pendiente'),
    v_fecha_creacion,
    case when v_tipo = 'administrativa' then v_fecha_limite else null end
  );

  insert into public.asignacion_equipo (asignacion_id, perfil_id)
  select v_assignment_id, perfil_id
  from unnest(p_empleados) as perfil_id
  group by perfil_id;

    insert into public.hitos_itinerario (
      id,
      asignacion_id,
      orden,
      descripcion,
      hora_estimada,
      completado,
      estado_hito,
      fecha_programada
    )
    select
      (hito ->> 'id')::uuid,
      v_assignment_id,
      (hito ->> 'orden')::integer,
      btrim(hito ->> 'descripcion'),
      (hito ->> 'hora_estimada')::time,
      false,
      case
        when (hito ->> 'orden')::integer = 1 then 'en_curso'
        else 'bloqueado'
      end,
      (hito ->> 'fecha_programada')::timestamptz
    from jsonb_array_elements(p_hitos) as hito;

  return v_assignment_id;
end;
$$;

revoke all on function public.admin_create_assignment(jsonb, uuid[], jsonb) from public;
grant execute on function public.admin_create_assignment(jsonb, uuid[], jsonb) to authenticated;

commit;
