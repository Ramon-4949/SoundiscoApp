begin;

alter table public.perfiles add column if not exists nombre_usuario text;

update public.perfiles p
set nombre_usuario = nullif(btrim(u.raw_user_meta_data->>'nombre_usuario'), '')
from auth.users u
where u.id = p.id and p.nombre_usuario is null;

create or replace function account_private.sync_new_profile_username()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.perfiles
  set nombre_usuario = nullif(btrim(new.raw_user_meta_data->>'nombre_usuario'), '')
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists zzzz_profile_username_created on auth.users;
create trigger zzzz_profile_username_created after insert on auth.users
for each row execute function account_private.sync_new_profile_username();

create or replace function account_private.protect_profile_identity()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() in ('authenticated', 'anon')
     and new.nombre_completo is distinct from old.nombre_completo then
    raise exception 'El nombre completo no se puede modificar' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_identity on public.perfiles;
create trigger protect_profile_identity before update on public.perfiles
for each row execute function account_private.protect_profile_identity();

create or replace function public.update_my_profile(p_username text, p_phone text, p_job text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_username text := btrim(coalesce(p_username, ''));
  v_phone text := btrim(coalesce(p_phone, ''));
  v_job text := btrim(coalesce(p_job, ''));
begin
  if v_user is null or not coalesce(public.account_is_approved(), false) then
    raise exception 'Tu cuenta no tiene acceso' using errcode = '42501';
  end if;
  if char_length(v_username) not between 3 and 30 or v_username !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' then
    raise exception 'El nombre de usuario no es válido' using errcode = '22023';
  end if;
  if v_phone !~ '^[0-9+() -]+$'
     or char_length(regexp_replace(v_phone, '[^0-9]', '', 'g')) not between 10 and 15 then
    raise exception 'El teléfono no es válido' using errcode = '22023';
  end if;
  if not exists(select 1 from public.cargos_empresa where nombre = v_job and activo) then
    raise exception 'Selecciona un cargo válido' using errcode = '22023';
  end if;
  update public.perfiles set nombre_usuario = v_username, telefono = v_phone, cargo = v_job
  where id = v_user;
  if not found then
    raise exception 'No se encontró tu perfil' using errcode = 'P0002';
  end if;
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) ||
      jsonb_build_object('nombre_usuario', v_username, 'telefono', v_phone, 'cargo', v_job)
  where id = v_user;
end;
$$;

revoke all on function account_private.protect_profile_identity() from public, anon, authenticated;
revoke all on function account_private.sync_new_profile_username() from public, anon, authenticated;
revoke all on function public.update_my_profile(text,text,text) from public, anon;
grant execute on function public.update_my_profile(text,text,text) to authenticated;

notify pgrst, 'reload schema';
commit;
