-- Ejecutar una vez después de admin_creation_setup.sql.
-- Permite consultar equipos completos y confirmar hitos en orden.

create or replace function public.puede_ver_asignacion(p_asignacion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.es_admin() or exists (
    select 1
    from public.asignacion_equipo
    where asignacion_id = p_asignacion_id
      and perfil_id = (select auth.uid())
  );
$$;

revoke all on function public.puede_ver_asignacion(uuid) from public;
grant execute on function public.puede_ver_asignacion(uuid) to authenticated;

drop policy if exists "Empleados leen sus asignaciones" on public.asignaciones;
create policy "Empleados leen sus asignaciones"
on public.asignaciones
for select to authenticated
using (public.puede_ver_asignacion(id));

drop policy if exists "Equipo visible por participante o admin" on public.asignacion_equipo;
create policy "Equipo visible por participante o admin"
on public.asignacion_equipo
for select to authenticated
using (public.puede_ver_asignacion(asignacion_id));

drop policy if exists "Hitos visibles por participante o admin" on public.hitos_itinerario;
create policy "Hitos visibles por participante o admin"
on public.hitos_itinerario
for select to authenticated
using (public.puede_ver_asignacion(asignacion_id));

create or replace function public.employee_complete_milestone(
  p_hito_id uuid,
  p_notas text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asignacion_id uuid;
  v_orden integer;
  v_siguiente_id uuid;
begin
  select asignacion_id, orden
    into v_asignacion_id, v_orden
  from public.hitos_itinerario
  where id = p_hito_id;

  if v_asignacion_id is null then
    raise exception 'El hito no existe' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.asignacion_equipo
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

  select id into v_siguiente_id
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

revoke all on function public.employee_complete_milestone(uuid, text) from public;
grant execute on function public.employee_complete_milestone(uuid, text) to authenticated;
