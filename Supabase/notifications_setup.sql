-- Apply AFTER admin_crud_completion.sql. Transactional, repeatable migration.
begin;
create schema if not exists notification_private;
revoke all on schema notification_private from public, anon, authenticated;

alter table public.notificaciones_app
  add column if not exists tipo text,
  add column if not exists destino_tipo text,
  add column if not exists destino_id uuid,
  add column if not exists estado text,
  add column if not exists evento_key text;
create unique index if not exists notification_event_recipient
  on public.notificaciones_app(perfil_id, evento_key);
create index if not exists notification_recipient_date
  on public.notificaciones_app(perfil_id, fecha_creacion desc);
alter table public.notificaciones_app enable row level security;
-- Restrictive policies also constrain any pre-existing permissive policies.
drop policy if exists notification_owner on public.notificaciones_app;
create policy notification_owner on public.notificaciones_app for select to authenticated
  using (perfil_id = (select auth.uid()));
drop policy if exists notification_owner_guard on public.notificaciones_app;
create policy notification_owner_guard on public.notificaciones_app as restrictive for select to authenticated
  using (perfil_id = (select auth.uid()));
revoke all on public.notificaciones_app from anon, authenticated;
grant select on public.notificaciones_app to authenticated;

create or replace function public.notifications_mark_read(p_id uuid default null)
returns void language sql security definer set search_path = '' as $$
  update public.notificaciones_app set leida = true
  where perfil_id = auth.uid() and (p_id is null or id = p_id);
$$;
revoke all on function public.notifications_mark_read(uuid) from public, anon;
grant execute on function public.notifications_mark_read(uuid) to authenticated;

create table if not exists notification_private.devices (
  installation uuid primary key,
  perfil_id uuid not null references public.perfiles(id) on delete cascade,
  token text not null,
  environment text not null check (environment in ('sandbox','production')),
  updated_at timestamptz not null default now()
);
create unique index if not exists push_unique_device on notification_private.devices(token, environment);
create or replace function public.register_push_device(p_installation uuid, p_token text, p_environment text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.perfiles where id = auth.uid()) then
    raise exception 'Perfil requerido' using errcode = '42501';
  end if;
  if p_token !~ '^[0-9a-f]{64,200}$' or p_environment not in ('sandbox','production') then
    raise exception 'Dispositivo invalido' using errcode = '22023';
  end if;
  -- APNs can return the same token after a reinstall while the app has a new
  -- installation UUID. Remove that stale registration before the upsert.
  perform pg_advisory_xact_lock(hashtextextended(p_environment || ':' || p_token, 0));
  delete from notification_private.devices
  where token = p_token and environment = p_environment
    and installation <> p_installation;
  -- An installation ID is a randomly generated local secret, never exposed in API reads.
  insert into notification_private.devices(installation,perfil_id,token,environment)
  values(p_installation,auth.uid(),p_token,p_environment)
  on conflict(installation) do update set perfil_id = excluded.perfil_id, token = excluded.token,
    environment = excluded.environment, updated_at = now();
end;
$$;
create or replace function public.unregister_push_device(p_installation uuid)
returns void language sql security definer set search_path = '' as $$
  delete from notification_private.devices where installation = p_installation and perfil_id = auth.uid();
$$;
revoke all on function public.register_push_device(uuid,text,text), public.unregister_push_device(uuid) from public, anon;
grant execute on function public.register_push_device(uuid,text,text), public.unregister_push_device(uuid) to authenticated;

create table if not exists notification_private.outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notificaciones_app(id) on delete cascade,
  installation uuid not null references notification_private.devices(installation) on delete cascade,
  recipient uuid not null,
  attempts integer not null default 0,
  next_attempt timestamptz not null default now(),
  leased_until timestamptz,
  lease_id uuid,
  sent_at timestamptz,
  last_error text,
  unique(notification_id,installation)
);
create or replace function notification_private.enqueue_push()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into notification_private.outbox(notification_id,installation,recipient)
    select new.id, installation, new.perfil_id from notification_private.devices where perfil_id = new.perfil_id;
  return new;
end;
$$;
drop trigger if exists notification_push on public.notificaciones_app;
create trigger notification_push after insert on public.notificaciones_app
for each row execute function notification_private.enqueue_push();

create or replace function notification_private.emit(
  recipient uuid, kind text, title text, body text, target_type text, target_id uuid, state text, event_key text
) returns void language sql security definer set search_path = '' as $$
  insert into public.notificaciones_app(id,perfil_id,titulo,mensaje,leida,fecha_creacion,
    tipo,destino_tipo,destino_id,estado,evento_key)
  select gen_random_uuid(),recipient,title,body,false,now(),kind,target_type,target_id,state,event_key
  where recipient is distinct from auth.uid()
  on conflict(perfil_id,evento_key) do nothing;
$$;

-- Accumulate before/after changes per transaction, then notify the final team.
create table if not exists notification_private.assignment_events (
  transaction_id bigint not null,
  assignment_id uuid not null,
  old_team uuid[] not null,
  old_title text,
  old_state text,
  actor uuid,
  content_changed boolean not null default false,
  progress_changed boolean not null default false,
  primary key(transaction_id,assignment_id)
);
create or replace function notification_private.capture_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  aid uuid;
  title text;
  state text;
  team uuid[];
  content boolean := false;
  progress boolean := false;
begin
  if tg_op = 'UPDATE' and to_jsonb(old) = to_jsonb(new) then return new; end if;
  if tg_table_name = 'asignaciones' then
    aid := case when tg_op = 'DELETE' then old.id else new.id end;
    title := case when tg_op = 'INSERT' then new.titulo else old.titulo end;
    state := case when tg_op = 'INSERT' then null else old.estado end;
    content := tg_op <> 'UPDATE' or
      (to_jsonb(old) - 'estado') is distinct from (to_jsonb(new) - 'estado');
    progress := tg_op = 'UPDATE' and old.estado is distinct from new.estado;
  else
    aid := case when tg_op = 'DELETE' then old.asignacion_id else new.asignacion_id end;
    select titulo,estado into title,state from public.asignaciones where id = aid;
    if tg_table_name = 'hitos_itinerario' then
      progress := tg_op = 'UPDATE' and (
        coalesce(old.completado,false) is distinct from coalesce(new.completado,false)
        or old.notas_incidencias is distinct from new.notas_incidencias);
      content := tg_op <> 'UPDATE' or
        (old.descripcion,old.fecha_programada,old.orden) is distinct from
        (new.descripcion,new.fecha_programada,new.orden);
    end if;
  end if;
  select coalesce(array_agg(distinct perfil_id),'{}') into team
    from public.asignacion_equipo where asignacion_id = aid;
  insert into notification_private.assignment_events(
    transaction_id,assignment_id,old_team,old_title,old_state,actor,content_changed,progress_changed)
  values(txid_current(),aid,team,title,state,auth.uid(),content,progress)
  on conflict(transaction_id,assignment_id) do update set
    content_changed = assignment_events.content_changed or excluded.content_changed,
    progress_changed = assignment_events.progress_changed or excluded.progress_changed;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create or replace function notification_private.flush_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  e notification_private.assignment_events%rowtype;
  a public.asignaciones%rowtype;
  team uuid[];
  recipient uuid;
  kind text;
  body text;
  actor_name text;
  event_key text;
begin
  delete from notification_private.assignment_events
    where transaction_id = new.transaction_id and assignment_id = new.assignment_id returning * into e;
  if not found then return null; end if;
  select * into a from public.asignaciones where id = e.assignment_id;
  select coalesce(array_agg(distinct perfil_id),'{}') into team
    from public.asignacion_equipo where asignacion_id = e.assignment_id;
  select coalesce(nombre_completo,'Un miembro del equipo') into actor_name from public.perfiles where id = e.actor;
  actor_name := coalesce(actor_name,'El sistema');
  event_key := e.transaction_id::text || ':' || e.assignment_id::text;
  for recipient in select distinct unnest(e.old_team || team ||
    coalesce((select array_agg(id) from public.perfiles where rol = 'admin'),'{}')) loop
    if a.id is null then
      kind := 'asignacion_eliminada'; body := actor_name || ' eliminó la asignación.';
    elsif recipient = any(e.old_team) and not recipient = any(team)
      and not exists(select 1 from public.perfiles where id = recipient and rol = 'admin') then
      kind := 'asignacion_retirada'; body := 'Ya no estás asignado a esta actividad.';
    elsif recipient = any(team) and not recipient = any(e.old_team) then
      kind := 'asignacion_nueva'; body := 'Tienes una nueva asignación. Consulta sus instrucciones e itinerario.';
    elsif e.old_state is distinct from a.estado then
      kind := 'estado_actualizado'; body := actor_name || ' cambió el estado a ' || coalesce(a.estado,'pendiente') || '.';
    elsif e.progress_changed then
      kind := 'hito_completado'; body := actor_name || ' actualizó el checklist y sus incidencias.';
    elsif e.content_changed or
      (select array_agg(x order by x) from unnest(e.old_team) x) is distinct from
      (select array_agg(x order by x) from unnest(team) x) then
      kind := 'asignacion_actualizada'; body := actor_name || ' actualizó la asignación. Revisa los cambios.';
    else continue;
    end if;
    perform notification_private.emit(recipient,kind,coalesce(a.titulo,e.old_title,'Asignación'),
      body,'asignacion',e.assignment_id,a.estado,event_key);
  end loop;
  return null;
end;
$$;
drop trigger if exists flush_assignment on notification_private.assignment_events;
create constraint trigger flush_assignment after insert on notification_private.assignment_events
deferrable initially deferred for each row execute function notification_private.flush_assignment();
do $$
declare t text;
begin
  foreach t in array array['asignaciones','asignacion_equipo','hitos_itinerario'] loop
    execute format('drop trigger if exists notification_capture on public.%I',t);
    execute format('create trigger notification_capture before insert or update or delete on public.%I for each row execute function notification_private.capture_assignment()',t);
  end loop;
end $$;

create or replace function notification_private.bulletin_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.comunicados%rowtype; recipient uuid; kind text; body text;
begin
  if tg_op = 'UPDATE' and (old.asunto,old.mensaje) is not distinct from (new.asunto,new.mensaje) then return new; end if;
  if tg_op = 'DELETE' then c := old; else c := new; end if;
  kind := case tg_op when 'INSERT' then 'comunicado_nuevo' when 'UPDATE' then 'comunicado_actualizado' else 'comunicado_eliminado' end;
  body := case tg_op when 'INSERT' then 'Hay un nuevo comunicado para toda la plantilla.'
    when 'UPDATE' then 'Se actualizó este comunicado. Revisa su contenido.' else 'Administración retiró este comunicado.' end;
  for recipient in select id from public.perfiles loop
    perform notification_private.emit(recipient,kind,c.asunto,body,'comunicado',c.id,null,
      txid_current()::text || ':comunicado:' || c.id::text || ':' || tg_op);
  end loop;
  if tg_op = 'DELETE' then return old; end if; return new;
end;
$$;
drop trigger if exists notification_bulletin on public.comunicados;
create trigger notification_bulletin after insert or update or delete on public.comunicados
for each row execute function notification_private.bulletin_event();

-- The worker authenticates as service_role; devices and queue cannot be read by app users.
create or replace function public.claim_notification_pushes()
returns table(job_id uuid, lease uuid, notification_id uuid, recipient uuid, token text, environment text)
language sql security definer set search_path = '' as $$
  with picked as (
    select o.id from notification_private.outbox o
    where o.sent_at is null and o.attempts < 8 and o.next_attempt <= now()
      and (o.leased_until is null or o.leased_until < now())
    order by o.next_attempt limit 50 for update skip locked
  ), leased as (
    update notification_private.outbox o set leased_until = now() + interval '5 minutes',
      lease_id = gen_random_uuid(), attempts = attempts + 1
    from picked where o.id = picked.id returning o.*
  )
  select l.id,l.lease_id,l.notification_id,l.recipient,d.token,d.environment
  from leased l join notification_private.devices d on d.installation = l.installation and d.perfil_id = l.recipient;
$$;
create or replace function public.finish_notification_push(p_job uuid,p_lease uuid,p_success boolean,p_error text,p_invalid boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare j notification_private.outbox%rowtype;
begin
  select * into j from notification_private.outbox where id = p_job and lease_id = p_lease for update;
  if not found then return; end if;
  if p_invalid then
    delete from notification_private.devices where installation = j.installation and perfil_id = j.recipient;
  else
    update notification_private.outbox set sent_at = case when p_success then now() else null end,
      last_error = left(p_error,300),leased_until = null,
      next_attempt = now() + make_interval(secs => least(3600,30 * power(2,attempts)::integer))
    where id = p_job;
  end if;
end;
$$;
revoke all on function public.claim_notification_pushes(),public.finish_notification_push(uuid,uuid,boolean,text,boolean) from public,anon,authenticated;
grant execute on function public.claim_notification_pushes(),public.finish_notification_push(uuid,uuid,boolean,text,boolean) to service_role;
revoke all on all functions in schema notification_private from public,anon,authenticated;
revoke all on all tables in schema notification_private from public,anon,authenticated;

do $$ begin
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'notificaciones_app') then
    alter publication supabase_realtime add table public.notificaciones_app;
  end if;
end $$;
commit;
