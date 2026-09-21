-- Ejecutar despues de account_access_setup.sql.
-- Separa el rol de acceso (admin/empleado) del cargo laboral.
begin;

alter table public.perfiles add column if not exists cargo text;

create table if not exists public.cargos_empresa (
  nombre text primary key,
  orden smallint not null unique,
  activo boolean not null default true
);

insert into public.cargos_empresa(nombre, orden, activo) values
  ('Técnico de sonido', 1, true),
  ('Técnico audiovisuales', 2, true),
  ('Técnico de iluminación', 3, true),
  ('Encargado de estructura', 4, true),
  ('Encargado de almacén', 5, true),
  ('Supervisor', 6, true),
  ('Administrativo', 7, true),
  ('Contabilidad', 8, true),
  ('Recursos Humanos', 9, true),
  ('Marketing Digital', 10, true)
on conflict(nombre) do update set orden = excluded.orden, activo = true;

alter table public.cargos_empresa enable row level security;
drop policy if exists cargos_empresa_visibles on public.cargos_empresa;
create policy cargos_empresa_visibles on public.cargos_empresa
for select to anon, authenticated using (activo);
grant select on public.cargos_empresa to anon, authenticated;

create or replace function account_private.normalizar_cargo(p_cargo text)
returns text language sql immutable set search_path = '' as $$
  select case lower(btrim(coalesce(p_cargo, '')))
    when 'técnico de sonido' then 'Técnico de sonido'
    when 'tecnico de sonido' then 'Técnico de sonido'
    when 'técnico audiovisuales' then 'Técnico audiovisuales'
    when 'tecnico audiovisuales' then 'Técnico audiovisuales'
    when 'técnico audiovisual' then 'Técnico audiovisuales'
    when 'tecnico audiovisual' then 'Técnico audiovisuales'
    when 'técnico de pantallas' then 'Técnico audiovisuales'
    when 'tecnico de pantallas' then 'Técnico audiovisuales'
    when 'técnico de iluminación' then 'Técnico de iluminación'
    when 'tecnico de iluminación' then 'Técnico de iluminación'
    when 'tecnico de iluminacion' then 'Técnico de iluminación'
    when 'encargado de estructura' then 'Encargado de estructura'
    when 'técnico de estructuras' then 'Encargado de estructura'
    when 'tecnico de estructuras' then 'Encargado de estructura'
    when 'encargado de almacén' then 'Encargado de almacén'
    when 'encargado de almacen' then 'Encargado de almacén'
    when 'supervisor' then 'Supervisor'
    when 'jefe de cuadrilla' then 'Supervisor'
    when 'administrativo' then 'Administrativo'
    when 'administración' then 'Administrativo'
    when 'administracion' then 'Administrativo'
    when 'contabilidad' then 'Contabilidad'
    when 'recursos humanos' then 'Recursos Humanos'
    when 'marketing digital' then 'Marketing Digital'
    else null
  end;
$$;
revoke all on function account_private.normalizar_cargo(text) from public, anon, authenticated;

-- Recupera el cargo del perfil o de la metadata de Auth. Los valores antiguos
-- desconocidos se conservan para no borrar informacion manual.
update public.perfiles p
set cargo = coalesce(
  account_private.normalizar_cargo(p.cargo),
  account_private.normalizar_cargo(u.raw_user_meta_data->>'cargo'),
  nullif(btrim(p.cargo), '')
)
from auth.users u
where u.id = p.id;

update public.perfiles set rol = 'empleado' where rol = 'tecnico';

-- Las restricciones se aplican a escrituras nuevas. NOT VALID permite conservar
-- cualquier dato historico desconocido hasta que administracion lo corrija.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.perfiles'::regclass and conname = 'perfiles_rol_valido'
  ) then
    alter table public.perfiles add constraint perfiles_rol_valido
      check (rol is null or rol in ('admin', 'empleado')) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.perfiles'::regclass and conname = 'perfiles_cargo_empresa_fk'
  ) then
    alter table public.perfiles add constraint perfiles_cargo_empresa_fk
      foreign key(cargo) references public.cargos_empresa(nombre) not valid;
  end if;
end;
$$;

-- Un registro nuevo siempre crea un perfil de empleado y copia su cargo.
-- Si otro trigger creo el perfil primero, completa sus datos sin sustituir
-- privilegios administrativos existentes.
create or replace function account_private.new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_cargo text := account_private.normalizar_cargo(new.raw_user_meta_data->>'cargo');
begin
  insert into public.perfiles(id, nombre_completo, rol, telefono, cargo)
  values(
    new.id,
    nullif(btrim(new.raw_user_meta_data->>'nombre_completo'), ''),
    'empleado',
    nullif(btrim(new.raw_user_meta_data->>'telefono'), ''),
    v_cargo
  )
  on conflict(id) do update set
    nombre_completo = coalesce(public.perfiles.nombre_completo, excluded.nombre_completo),
    telefono = coalesce(public.perfiles.telefono, excluded.telefono),
    cargo = coalesce(public.perfiles.cargo, excluded.cargo),
    rol = case when public.perfiles.rol = 'tecnico' then 'empleado' else public.perfiles.rol end;
  return new;
end;
$$;
drop trigger if exists zz_account_profile_created on auth.users;
create trigger zz_account_profile_created after insert on auth.users
for each row execute function account_private.new_auth_user();

create or replace function public.admin_list_accounts(p_offset integer default 0)
returns table(id uuid,nombre text,email text,telefono text,cargo text,estado text,fecha timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin() then
    raise exception 'Solo administradores pueden gestionar accesos' using errcode = '42501';
  end if;
  return query
    select p.id, p.nombre_completo, u.email::text, p.telefono,
      coalesce(
        nullif(btrim(p.cargo), ''),
        account_private.normalizar_cargo(u.raw_user_meta_data->>'cargo'),
        'Sin cargo'
      ),
      a.estado, a.created_at
    from account_private.access a
    join public.perfiles p on p.id = a.user_id
    join auth.users u on u.id = p.id
    order by a.created_at desc, p.id
    limit 200 offset greatest(p_offset, 0);
end;
$$;
revoke all on function public.admin_list_accounts(integer) from public, anon;
grant execute on function public.admin_list_accounts(integer) to authenticated;

notify pgrst, 'reload schema';
commit;
