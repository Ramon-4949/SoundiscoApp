-- New RPCs: existing clients and admin_employee_performance remain compatible.
begin;
create or replace function public.admin_dashboard_summary()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null or not coalesce(public.es_admin(), false) then
    raise exception 'Solo administradores' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'total', count(*),
    'unidades_asignadas', count(*) filter (where exists (
      select 1 from public.asignacion_equipo e where e.asignacion_id = a.id)),
    'unidades_activas', count(*) filter (where a.estado = 'en_curso'
      and (a.fecha_limite is null or a.fecha_limite > now())),
    'completadas', count(*) filter (where a.estado = 'completada'),
    'vencidas', count(*) filter (where a.estado <> 'completada'
      and (a.estado = 'vencida' or a.fecha_limite <= now())),
    'tasa_entrega', coalesce(round(100.0 * count(*) filter (where a.estado = 'completada')
      / nullif(count(*), 0), 2), 0),
    'creadas_ultimos_7_dias', (
      select jsonb_agg(coalesce(d.cantidad, 0) order by dias.dia)
      from generate_series(
        (now() at time zone 'America/Santo_Domingo')::date - 6,
        (now() at time zone 'America/Santo_Domingo')::date,
        interval '1 day'
      ) dias(dia)
      left join (
        select (daily.fecha_creacion at time zone 'America/Santo_Domingo')::date dia,
          count(*) cantidad
        from public.asignaciones daily
        where daily.fecha_creacion >= (
          ((now() at time zone 'America/Santo_Domingo')::date - 6)::timestamp
          at time zone 'America/Santo_Domingo'
        )
        group by 1
      ) d on d.dia = dias.dia::date
    )
  ) into result from public.asignaciones a;
  return result;
end;
$$;

drop function if exists public.admin_assignments_page(integer, integer, text);

-- Only the requested page is enriched with milestones and responsible people.
create or replace function public.admin_assignments_page(
  p_offset integer default 0, p_limit integer default 50,
  p_estado text default 'pendientes', p_busqueda text default ''
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  page_size integer := least(100, greatest(1, coalesce(p_limit, 50)));
  page_offset integer := greatest(0, coalesce(p_offset, 0));
  search_text text := lower(trim(coalesce(p_busqueda, '')));
  result jsonb;
begin
  if auth.uid() is null or not coalesce(public.es_admin(), false) then
    raise exception 'Solo administradores' using errcode = '42501';
  end if;
  if p_estado is null or p_estado not in ('todas', 'pendientes', 'vencidas', 'completadas') then
    raise exception 'Filtro de estado no valido' using errcode = '22023';
  end if;
  if length(search_text) > 100 then
    raise exception 'La busqueda excede 100 caracteres' using errcode = '22023';
  end if;
  with candidates as materialized (
    select a.* from public.asignaciones a
    where (
      p_estado = 'todas'
        or (p_estado = 'completadas' and a.estado = 'completada')
        or (p_estado = 'vencidas' and a.estado <> 'completada'
          and (a.estado = 'vencida' or a.fecha_limite <= now()))
        or (p_estado = 'pendientes' and a.estado in ('pendiente', 'en_curso')
          and (a.fecha_limite is null or a.fecha_limite > now()))
    ) and (
      search_text = ''
      or strpos(lower(a.titulo), search_text) > 0
      or strpos(lower(coalesce(a.ubicacion, '')), search_text) > 0
      or exists (
        select 1 from public.asignacion_equipo search_team
        join public.perfiles search_profile on search_profile.id = search_team.perfil_id
        where search_team.asignacion_id = a.id
          and strpos(lower(coalesce(search_profile.nombre_completo, '')), search_text) > 0
      )
    )
    order by a.fecha_creacion desc, a.id desc
    limit page_size + 1 offset page_offset
  ), page as (
    select * from candidates order by fecha_creacion desc, id desc limit page_size
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(
      to_jsonb(p) || jsonb_build_object(
        'hitos_itinerario', coalesce((
          select jsonb_agg(to_jsonb(h) order by h.orden)
          from public.hitos_itinerario h where h.asignacion_id = p.id
        ), '[]'::jsonb),
        'asignacion_equipo', coalesce((
          select jsonb_agg(jsonb_build_object('perfiles', to_jsonb(profile)))
          from public.asignacion_equipo team
          join public.perfiles profile on profile.id = team.perfil_id
          where team.asignacion_id = p.id
        ), '[]'::jsonb)
      ) order by p.fecha_creacion desc, p.id desc)
      from page p), '[]'::jsonb),
    'has_more', (select count(*) > page_size from candidates),
    'next_offset', case when (select count(*) > page_size from candidates)
      then page_offset + page_size else null end
  ) into result;
  return result;
end;
$$;
revoke all on function public.admin_dashboard_summary() from public, anon;
revoke all on function public.admin_assignments_page(integer, integer, text, text) from public, anon;
grant execute on function public.admin_dashboard_summary() to authenticated;
grant execute on function public.admin_assignments_page(integer, integer, text, text) to authenticated;
notify pgrst, 'reload schema';
commit;
