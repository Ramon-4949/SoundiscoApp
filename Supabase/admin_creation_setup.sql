-- Ejecutar una vez en Supabase SQL Editor.
-- Completa el esquema necesario para asignaciones, hitos y comunicados.

alter table public.asignaciones
  alter column ubicacion drop not null,
  add column if not exists estado text not null default 'pendiente',
  add column if not exists fecha_limite timestamptz;

alter table public.hitos_itinerario
  add column if not exists fecha_programada timestamptz,
  add column if not exists notas_incidencias text;

alter table public.comunicados
  add column if not exists leido_por uuid[] not null default '{}';

create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles
    where id = (select auth.uid()) and rol = 'admin'
  );
$$;

revoke all on function public.es_admin() from public;
grant execute on function public.es_admin() to authenticated;

create or replace function public.admin_create_assignment(
  p_asignacion jsonb,
  p_empleados uuid[],
  p_hitos jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asignacion_id uuid := gen_random_uuid();
  v_empleado_id uuid;
  v_hito jsonb;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede crear asignaciones' using errcode = '42501';
  end if;

  insert into public.asignaciones (
    id, tipo_flujo, titulo, ubicacion, nivel_prioridad,
    instrucciones, estado, fecha_creacion, fecha_limite
  ) values (
    v_asignacion_id,
    p_asignacion ->> 'tipo_flujo',
    p_asignacion ->> 'titulo',
    nullif(p_asignacion ->> 'ubicacion', ''),
    p_asignacion ->> 'nivel_prioridad',
    nullif(p_asignacion ->> 'instrucciones', ''),
    coalesce(p_asignacion ->> 'estado', 'pendiente'),
    coalesce((p_asignacion ->> 'fecha_creacion')::timestamptz, now()),
    nullif(p_asignacion ->> 'fecha_limite', '')::timestamptz
  );

  foreach v_empleado_id in array coalesce(p_empleados, '{}'::uuid[]) loop
    insert into public.asignacion_equipo (asignacion_id, perfil_id)
    values (v_asignacion_id, v_empleado_id);
  end loop;

  for v_hito in select value from jsonb_array_elements(coalesce(p_hitos, '[]'::jsonb)) loop
    insert into public.hitos_itinerario (
      id, asignacion_id, orden, descripcion, hora_estimada,
      fecha_programada, estado_hito, notas_incidencias
    ) values (
      (v_hito ->> 'id')::uuid,
      v_asignacion_id,
      (v_hito ->> 'orden')::integer,
      v_hito ->> 'descripcion',
      (v_hito ->> 'hora_estimada')::time,
      (v_hito ->> 'fecha_programada')::timestamptz,
      coalesce(v_hito ->> 'estado_hito', 'bloqueado'),
      nullif(v_hito ->> 'notas_incidencias', '')
    );
  end loop;

  return v_asignacion_id;
end;
$$;

create or replace function public.admin_update_assignment(
  p_asignacion_id uuid,
  p_asignacion jsonb,
  p_empleados uuid[],
  p_hitos jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empleado_id uuid;
  v_hito jsonb;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede editar asignaciones' using errcode = '42501';
  end if;

  update public.asignaciones set
    tipo_flujo = p_asignacion ->> 'tipo_flujo',
    titulo = p_asignacion ->> 'titulo',
    ubicacion = nullif(p_asignacion ->> 'ubicacion', ''),
    nivel_prioridad = p_asignacion ->> 'nivel_prioridad',
    instrucciones = nullif(p_asignacion ->> 'instrucciones', ''),
    estado = coalesce(p_asignacion ->> 'estado', estado),
    fecha_limite = nullif(p_asignacion ->> 'fecha_limite', '')::timestamptz
  where id = p_asignacion_id;

  delete from public.asignacion_equipo where asignacion_id = p_asignacion_id;
  foreach v_empleado_id in array coalesce(p_empleados, '{}'::uuid[]) loop
    insert into public.asignacion_equipo (asignacion_id, perfil_id)
    values (p_asignacion_id, v_empleado_id);
  end loop;

  delete from public.hitos_itinerario where asignacion_id = p_asignacion_id;
  for v_hito in select value from jsonb_array_elements(coalesce(p_hitos, '[]'::jsonb)) loop
    insert into public.hitos_itinerario (
      id, asignacion_id, orden, descripcion, hora_estimada,
      fecha_programada, estado_hito, notas_incidencias
    ) values (
      (v_hito ->> 'id')::uuid, p_asignacion_id,
      (v_hito ->> 'orden')::integer, v_hito ->> 'descripcion',
      (v_hito ->> 'hora_estimada')::time,
      (v_hito ->> 'fecha_programada')::timestamptz,
      coalesce(v_hito ->> 'estado_hito', 'bloqueado'),
      nullif(v_hito ->> 'notas_incidencias', '')
    );
  end loop;
end;
$$;

create or replace function public.admin_delete_assignment(p_asignacion_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede eliminar asignaciones' using errcode = '42501';
  end if;
  delete from public.hitos_itinerario where asignacion_id = p_asignacion_id;
  delete from public.asignacion_equipo where asignacion_id = p_asignacion_id;
  delete from public.asignaciones where id = p_asignacion_id;
end;
$$;

revoke all on function public.admin_create_assignment(jsonb, uuid[], jsonb) from public;
revoke all on function public.admin_update_assignment(uuid, jsonb, uuid[], jsonb) from public;
revoke all on function public.admin_delete_assignment(uuid) from public;
grant execute on function public.admin_create_assignment(jsonb, uuid[], jsonb) to authenticated;
grant execute on function public.admin_update_assignment(uuid, jsonb, uuid[], jsonb) to authenticated;
grant execute on function public.admin_delete_assignment(uuid) to authenticated;

alter table public.asignaciones enable row level security;
alter table public.asignacion_equipo enable row level security;
alter table public.hitos_itinerario enable row level security;
alter table public.comunicados enable row level security;

drop policy if exists "Administradores gestionan asignaciones" on public.asignaciones;
create policy "Administradores gestionan asignaciones" on public.asignaciones
for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists "Empleados leen sus asignaciones" on public.asignaciones;
create policy "Empleados leen sus asignaciones" on public.asignaciones
for select to authenticated using (
  exists (
    select 1 from public.asignacion_equipo ae
    where ae.asignacion_id = asignaciones.id and ae.perfil_id = (select auth.uid())
  )
);

drop policy if exists "Equipo visible por participante o admin" on public.asignacion_equipo;
create policy "Equipo visible por participante o admin" on public.asignacion_equipo
for select to authenticated using (perfil_id = (select auth.uid()) or public.es_admin());

drop policy if exists "Hitos visibles por participante o admin" on public.hitos_itinerario;
create policy "Hitos visibles por participante o admin" on public.hitos_itinerario
for select to authenticated using (
  public.es_admin() or exists (
    select 1 from public.asignacion_equipo ae
    where ae.asignacion_id = hitos_itinerario.asignacion_id
      and ae.perfil_id = (select auth.uid())
  )
);

drop policy if exists "Plantilla lee comunicados" on public.comunicados;
create policy "Plantilla lee comunicados" on public.comunicados
for select to authenticated using (true);

drop policy if exists "Administradores gestionan comunicados" on public.comunicados;
create policy "Administradores gestionan comunicados" on public.comunicados
for all to authenticated using (public.es_admin()) with check (public.es_admin());
