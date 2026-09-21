-- Ejecutar despues de profile_roles_and_jobs.sql y assignment_sla_setup.sql.
-- Mantiene la validacion incluso si alguien intenta omitir la app iOS.
begin;

create or replace function account_private.new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_username text := btrim(coalesce(new.raw_user_meta_data->>'nombre_usuario', ''));
  v_name text := btrim(coalesce(new.raw_user_meta_data->>'nombre_completo', ''));
  v_phone text := btrim(coalesce(new.raw_user_meta_data->>'telefono', ''));
  v_digits text := regexp_replace(v_phone, '[^0-9]', '', 'g');
  v_cargo text := account_private.normalizar_cargo(new.raw_user_meta_data->>'cargo');
begin
  if char_length(v_username) not between 3 and 30
     or v_username !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' then
    raise exception 'El nombre de usuario no es valido' using errcode = '22023';
  end if;
  if char_length(v_name) not between 2 and 80
     or v_name ~ '[0-9]' or v_name ~ '[[:cntrl:]]' then
    raise exception 'El nombre completo no es valido' using errcode = '22023';
  end if;
  if char_length(v_digits) not between 10 and 15
     or v_phone !~ '^[0-9+() -]+$' then
    raise exception 'El telefono no es valido' using errcode = '22023';
  end if;
  if v_cargo is null then
    raise exception 'El cargo no pertenece al catalogo de la empresa' using errcode = '22023';
  end if;

  insert into public.perfiles(id, nombre_completo, rol, telefono, cargo)
  values(new.id, v_name, 'empleado', v_phone, v_cargo)
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

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid='public.perfiles'::regclass and conname='perfiles_nombre_formato') then
    alter table public.perfiles add constraint perfiles_nombre_formato check (
      nombre_completo is null or (
        char_length(btrim(nombre_completo)) between 2 and 80
        and nombre_completo !~ '[0-9]'
        and nombre_completo !~ '[[:cntrl:]]'
      )
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.perfiles'::regclass and conname='perfiles_telefono_formato') then
    alter table public.perfiles add constraint perfiles_telefono_formato check (
      telefono is null or (
        char_length(regexp_replace(telefono, '[^0-9]', '', 'g')) between 10 and 15
        and telefono ~ '^[0-9+() -]+$'
      )
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.asignaciones'::regclass and conname='asignaciones_texto_valido') then
    alter table public.asignaciones add constraint asignaciones_texto_valido check (
      titulo is not null
      and char_length(btrim(titulo)) between 3 and 120
      and titulo !~ '[[:cntrl:]]'
      and (
        (tipo_flujo = 'campo' and ubicacion is not null and char_length(btrim(ubicacion)) between 3 and 180)
        or (tipo_flujo = 'administrativa' and ubicacion is null)
      )
      and (instrucciones is null or char_length(btrim(instrucciones)) between 1 and 2000)
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.hitos_itinerario'::regclass and conname='hitos_texto_valido') then
    alter table public.hitos_itinerario add constraint hitos_texto_valido check (
      descripcion is not null
      and char_length(btrim(descripcion)) between 2 and 100
      and descripcion !~ '[[:cntrl:]]'
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.comunicados'::regclass and conname='comunicados_texto_valido') then
    alter table public.comunicados add constraint comunicados_texto_valido check (
      asunto is not null
      and mensaje is not null
      and char_length(btrim(asunto)) between 3 and 140
      and asunto !~ '[[:cntrl:]]'
      and char_length(btrim(mensaje)) between 10 and 4000
    ) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.notas_asignacion'::regclass and conname='notas_texto_valido') then
    alter table public.notas_asignacion add constraint notas_texto_valido check (
      contenido is not null and char_length(btrim(contenido)) between 3 and 4000
    ) not valid;
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
