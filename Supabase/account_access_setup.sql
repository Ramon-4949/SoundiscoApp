-- Apply AFTER the notifications, availability and assignment migrations.
-- Existing profiles keep their access. New registrations require approval.
begin;

create schema if not exists account_private;
revoke all on schema account_private from public, anon, authenticated;
create table if not exists account_private.access (
  user_id uuid primary key references public.perfiles(id) on delete cascade,
  estado text not null default 'pendiente' check (estado in ('pendiente','aprobada','rechazada')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);
revoke all on account_private.access from public, anon, authenticated;
insert into account_private.access(user_id,estado)
select id,'aprobada' from public.perfiles on conflict do nothing;

create or replace function public.account_is_approved()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from account_private.access where user_id = auth.uid() and estado = 'aprobada');
$$;
create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.account_is_approved() and exists (
    select 1 from public.perfiles where id = auth.uid() and rol = 'admin');
$$;
revoke all on function public.account_is_approved(), public.es_admin() from public, anon;
grant execute on function public.account_is_approved(), public.es_admin() to authenticated;

create or replace function account_private.new_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into account_private.access(user_id) values(new.id) on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists account_access_created on public.perfiles;
create trigger account_access_created after insert on public.perfiles
for each row execute function account_private.new_profile();

-- Also support installations whose Auth trigger does not create a profile.
create or replace function account_private.new_auth_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles(id,nombre_completo,rol,telefono)
  values(new.id, nullif(new.raw_user_meta_data->>'nombre_completo',''), 'tecnico',
    nullif(new.raw_user_meta_data->>'telefono','')) on conflict(id) do nothing;
  return new;
end;
$$;
drop trigger if exists zz_account_profile_created on auth.users;
create trigger zz_account_profile_created after insert on auth.users
for each row execute function account_private.new_auth_user();

-- Auth accounts that previously lacked an employee profile enter review too.
insert into public.perfiles(id,nombre_completo,rol,telefono)
select u.id,nullif(u.raw_user_meta_data->>'nombre_completo',''),'tecnico',
  nullif(u.raw_user_meta_data->>'telefono','') from auth.users u
where not exists(select 1 from public.perfiles p where p.id=u.id);

create or replace function public.my_account_access()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare state text;
begin
  if auth.uid() is null then raise exception 'Sesion requerida' using errcode = '42501'; end if;
  select estado into state from account_private.access where user_id = auth.uid();
  if state is null then raise exception 'No existe el perfil de acceso. Contacta con administracion.' using errcode = '42501'; end if;
  return jsonb_build_object('estado',state);
end;
$$;

-- Guard all REST/RPC requests, including SECURITY DEFINER RPCs with old JWTs.
create or replace function public.check_account_access()
returns void language plpgsql stable security definer set search_path = '' as $$
declare path text := trim(both '/' from coalesce(current_setting('request.path',true),''));
begin
  if auth.role() = 'authenticated' and not public.account_is_approved() then
    if path in ('rpc/my_account_access','rpc/delete_my_account',
      'rpc/register_push_device','rpc/unregister_push_device') then return; end if;
    if path = 'perfiles' and current_setting('request.method',true) in ('GET','HEAD') then return; end if;
    raise exception 'Tu cuenta no tiene acceso aprobado' using errcode = '42501';
  end if;
end;
$$;
-- Do not silently replace an existing project-specific pre-request hook.
do $$
begin
  if exists (
    select 1 from pg_db_role_setting s join pg_roles r on r.oid=s.setrole,
      unnest(s.setconfig) setting
    where r.rolname='authenticator' and setting like 'pgrst.db_pre_request=%'
      and setting <> 'pgrst.db_pre_request=public.check_account_access'
  ) then raise exception 'Existe otro db_pre_request: integrar check_account_access antes de continuar.'; end if;
end $$;
alter role authenticator set pgrst.db_pre_request = 'public.check_account_access';

-- RLS also protects Realtime and direct table requests.
do $$
declare t text;
begin
  foreach t in array array['asignaciones','asignacion_equipo','hitos_itinerario','checklist_equipos','comunicados'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists approved_account_guard on public.%I',t);
    execute format('create policy approved_account_guard on public.%I as restrictive for all to authenticated using (public.account_is_approved()) with check (public.account_is_approved())',t);
  end loop;
end $$;
alter table public.perfiles enable row level security;
drop policy if exists account_profile_owner on public.perfiles;
create policy account_profile_owner on public.perfiles for select to authenticated
using (id = auth.uid() or public.es_admin());
drop policy if exists account_profile_read on public.perfiles;
create policy account_profile_read on public.perfiles as restrictive for select to authenticated
using (public.account_is_approved() or id = auth.uid());
drop policy if exists account_notification_read on public.notificaciones_app;
create policy account_notification_read on public.notificaciones_app as restrictive for select to authenticated
using (public.account_is_approved());

create or replace function public.admin_list_accounts(p_offset integer default 0)
returns table(id uuid,nombre text,email text,telefono text,cargo text,estado text,fecha timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin() then raise exception 'Solo administradores pueden gestionar accesos' using errcode = '42501'; end if;
  return query select p.id,p.nombre_completo,u.email::text,p.telefono,
    coalesce(nullif(u.raw_user_meta_data->>'cargo',''),p.rol),a.estado,a.created_at
    from account_private.access a join public.perfiles p on p.id=a.user_id
    join auth.users u on u.id=p.id order by a.created_at desc,p.id
    limit 200 offset greatest(p_offset,0);
end;
$$;

create or replace function public.admin_review_account(p_user_id uuid,p_estado text)
returns void language plpgsql security definer set search_path = '' as $$
declare previous text;
begin
  if not public.es_admin() then raise exception 'Solo administradores pueden revisar cuentas' using errcode = '42501'; end if;
  if p_estado is null or p_estado not in ('aprobada','rechazada') then raise exception 'Estado invalido'; end if;
  select estado into previous from account_private.access where user_id=p_user_id for update;
  if previous is null then raise exception 'La cuenta ya no existe'; end if;
  if previous = p_estado then return; end if;
  if previous = 'aprobada' then raise exception 'Este flujo solo revisa solicitudes pendientes o rechazadas'; end if;
  update account_private.access set estado=p_estado,reviewed_at=now(),reviewed_by=auth.uid() where user_id=p_user_id;
  perform notification_private.emit(p_user_id,
    case when p_estado='aprobada' then 'cuenta_aprobada' else 'cuenta_rechazada' end,
    case when p_estado='aprobada' then 'Cuenta verificada' else 'Solicitud revisada' end,
    case when p_estado='aprobada' then 'Tus credenciales han sido aprobadas. Ya puedes acceder al sistema'
      else 'Tu solicitud no fue aprobada. Contacta con administracion.' end,
    'perfil',p_user_id,p_estado,'acceso:'||p_user_id::text||':'||gen_random_uuid()::text);
end;
$$;

-- Pending users may register for the approval push, but must not receive business data.
create or replace function account_private.filter_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo in ('cuenta_aprobada','cuenta_rechazada') or exists (
    select 1 from account_private.access where user_id=new.perfil_id and estado='aprobada'
  ) then return new; end if;
  return null;
end;
$$;
drop trigger if exists account_notification_filter on public.notificaciones_app;
create trigger account_notification_filter before insert on public.notificaciones_app
for each row execute function account_private.filter_notification();

create or replace function notification_private.profile_registered()
returns trigger language plpgsql security definer set search_path = '' as $$
declare recipient uuid;
begin
  for recipient in select p.id from public.perfiles p join account_private.access a on a.user_id=p.id
    where p.rol='admin' and a.estado='aprobada' and p.id<>new.id loop
    perform notification_private.emit(recipient,'usuario_nuevo','Nuevo registro',
      'Un nuevo usuario ha creado sus credenciales y espera tu aprobacion',
      'perfil',new.id,null,'registro:'||new.id::text);
  end loop;
  return new;
end;
$$;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); full_name text; user_email text;
begin
  if uid is null then raise exception 'Sesion requerida' using errcode = '42501'; end if;
  select nombre_completo into full_name from public.perfiles where id=uid for update;
  select email into user_email from auth.users where id=uid;
  delete from notification_private.devices where perfil_id=uid;
  delete from public.asignacion_equipo where perfil_id=uid;
  update public.comunicados set leido_por=array_remove(leido_por,uid) where uid=any(leido_por);
  -- Remove cross-user notification text that identifies the deleted user.
  delete from public.notificaciones_app where perfil_id=uid or (destino_tipo='perfil' and destino_id=uid)
    or (nullif(full_name,'') is not null and destino_tipo='asignacion'
      and left(mensaje,length(full_name)+1)=full_name||' ')
    or (nullif(user_email,'') is not null and position(user_email in mensaje)>0);
  update notification_private.assignment_events set actor=null where actor=uid;
  delete from public.perfiles where id=uid;
  delete from auth.users where id=uid;
end;
$$;

create or replace function account_private.check_assignee()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists(select 1 from account_private.access where user_id=new.perfil_id and estado='aprobada') then
    raise exception 'Solo puedes asignar empleados con acceso aprobado' using errcode='23514';
  end if;
  return new;
end;
$$;
drop trigger if exists account_assignee_guard on public.asignacion_equipo;
create trigger account_assignee_guard before insert or update on public.asignacion_equipo
for each row execute function account_private.check_assignee();

create or replace function public.admin_employee_availability(
  p_inicio timestamptz, p_fin timestamptz, p_excluir uuid default null, p_offset integer default 0
)
returns table(id uuid,nombre text,cargo text,rol text,disponible boolean,ocupado_desde timestamptz,ocupado_hasta timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin() then raise exception 'Solo administradores pueden consultar disponibilidad' using errcode='42501'; end if;
  if p_inicio is null or p_fin is null or p_fin<p_inicio then raise exception 'Periodo invalido'; end if;
  return query select p.id,p.nombre_completo,
    coalesce(nullif(btrim(p.cargo),''),nullif(btrim(u.raw_user_meta_data->>'cargo'),'')),p.rol,
    conflict.perfil_id is null,lower(conflict.periodo),upper(conflict.periodo)
    from public.perfiles p join account_private.access a on a.user_id=p.id and a.estado='aprobada'
    left join auth.users u on u.id=p.id
    left join lateral (
      select b.perfil_id,b.periodo from scheduling_private.bookings b
      where b.perfil_id=p.id and b.asignacion_id is distinct from p_excluir
        and b.periodo && tstzrange(p_inicio,p_fin,'[]')
      order by upper(b.periodo) desc limit 1
    ) conflict on true
    order by p.nombre_completo nulls last,p.id limit 200 offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.my_account_access(),public.check_account_access(),public.admin_list_accounts(integer),
  public.admin_review_account(uuid,text),public.delete_my_account() from public,anon;
grant execute on function public.my_account_access(),public.check_account_access(),public.admin_list_accounts(integer),
  public.admin_review_account(uuid,text),public.delete_my_account() to authenticated;
-- PostgREST invokes the hook for anonymous and worker requests too.
grant execute on function public.check_account_access() to anon,service_role;
revoke all on all functions in schema account_private from public,anon,authenticated;
notify pgrst,'reload schema';
notify pgrst,'reload config';
commit;
