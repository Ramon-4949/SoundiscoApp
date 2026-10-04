-- Apply after the iOS notification and account access migrations.
begin;
create schema if not exists android_push_private;
revoke all on schema android_push_private from public, anon, authenticated;

create table if not exists android_push_private.devices (
  installation uuid primary key,
  perfil_id uuid not null references public.perfiles(id) on delete cascade,
  token text not null unique,
  updated_at timestamptz not null default now()
);
create index if not exists android_devices_recipient on android_push_private.devices(perfil_id);
create table if not exists android_push_private.outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notificaciones_app(id) on delete cascade,
  installation uuid not null references android_push_private.devices(installation) on delete cascade,
  recipient uuid not null references public.perfiles(id) on delete cascade,
  attempts integer not null default 0,
  next_attempt timestamptz not null default now(),
  leased_until timestamptz,
  lease_id uuid,
  sent_at timestamptz,
  last_error text,
  unique(notification_id, installation)
);
create index if not exists android_outbox_pending on android_push_private.outbox(next_attempt)
  where sent_at is null and attempts < 8;
create index if not exists android_outbox_installation on android_push_private.outbox(installation);
create index if not exists android_outbox_recipient on android_push_private.outbox(recipient);
create index if not exists android_outbox_sent on android_push_private.outbox(sent_at) where sent_at is not null;
alter table android_push_private.devices enable row level security;
alter table android_push_private.outbox enable row level security;

create or replace function public.register_android_push_device(p_installation uuid, p_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.perfiles where id=auth.uid()) then
    raise exception 'Perfil requerido' using errcode='42501';
  end if;
  if p_installation is null or p_token is null or length(p_token) not between 20 and 4096
    or p_token ~ '[[:space:][:cntrl:]]' then
    raise exception 'Dispositivo invalido' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('android-installation:' || p_installation::text,0));
  perform pg_advisory_xact_lock(hashtextextended('android-token:' || p_token,0));
  -- Changing account/token drops old jobs, so they cannot reach the new owner.
  delete from android_push_private.devices
    where (token=p_token and installation<>p_installation)
       or (installation=p_installation and (perfil_id<>auth.uid() or token<>p_token));
  insert into android_push_private.devices(installation,perfil_id,token)
    values(p_installation,auth.uid(),p_token)
    on conflict(installation) do update set updated_at=now();
end;
$$;
create or replace function public.unregister_android_push_device(p_installation uuid)
returns void language sql security definer set search_path = '' as $$
  delete from android_push_private.devices where installation=p_installation and perfil_id=auth.uid();
$$;
revoke all on function public.register_android_push_device(uuid,text),
  public.unregister_android_push_device(uuid) from public,anon,authenticated;
grant execute on function public.register_android_push_device(uuid,text),
  public.unregister_android_push_device(uuid) to authenticated;

create or replace function android_push_private.enqueue_push()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into android_push_private.outbox(notification_id,installation,recipient)
    select new.id,d.installation,new.perfil_id from android_push_private.devices d
    where d.perfil_id=new.perfil_id on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists android_notification_push on public.notificaciones_app;
create trigger android_notification_push after insert on public.notificaciones_app
  for each row execute function android_push_private.enqueue_push();

create or replace function public.claim_android_pushes()
returns table(job_id uuid, lease uuid, notification_id uuid, recipient uuid, token text, title text, body text)
language sql security definer set search_path = '' as $$
  with picked as (
    select o.id from android_push_private.outbox o
    join android_push_private.devices d on d.installation=o.installation and d.perfil_id=o.recipient
    join public.notificaciones_app n on n.id=o.notification_id and n.perfil_id=o.recipient
    where o.sent_at is null and o.attempts<8 and o.next_attempt<=now()
      and (o.leased_until is null or o.leased_until<now())
    order by o.next_attempt,o.id limit 20 for update of o skip locked
  ), leased as (
    update android_push_private.outbox o set leased_until=now()+interval '5 minutes',
      lease_id=gen_random_uuid(), attempts=o.attempts+1
    from picked where o.id=picked.id returning o.*
  )
  select l.id,l.lease_id,l.notification_id,l.recipient,d.token,n.titulo,n.mensaje
    from leased l join android_push_private.devices d
      on d.installation=l.installation and d.perfil_id=l.recipient
    join public.notificaciones_app n on n.id=l.notification_id and n.perfil_id=l.recipient;
$$;
create or replace function public.finish_android_push(
  p_job uuid,p_lease uuid,p_success boolean,p_error text,p_invalid boolean default false
)
returns void language plpgsql security definer set search_path = '' as $$
declare j android_push_private.outbox%rowtype;
begin
  select * into j from android_push_private.outbox
    where id=p_job and lease_id=p_lease and sent_at is null for update;
  if not found then return; end if;
  if p_invalid then
    delete from android_push_private.devices where installation=j.installation and perfil_id=j.recipient;
  else
    update android_push_private.outbox set sent_at=case when p_success then now() else null end,
      last_error=case when p_success then null else left(p_error,300) end,
      leased_until=null,lease_id=null,
      next_attempt=now()+make_interval(secs=>least(3600,30*power(2,attempts)::integer))
    where id=p_job;
  end if;
end;
$$;
revoke all on function public.claim_android_pushes(),
  public.finish_android_push(uuid,uuid,boolean,text,boolean) from public,anon,authenticated;
grant execute on function public.claim_android_pushes(),
  public.finish_android_push(uuid,uuid,boolean,text,boolean) to service_role;
revoke all on all functions in schema android_push_private from public,anon,authenticated;
revoke all on all tables in schema android_push_private from public,anon,authenticated;

-- Preserve the project's access hook; extend only its existing push allowlist.
do $$
declare definition text;
begin
  if to_regprocedure('public.check_account_access()') is not null then
    select pg_get_functiondef('public.check_account_access()'::regprocedure) into definition;
    if position('rpc/register_android_push_device' in definition)=0 then
      if position('''rpc/register_push_device''' in definition)=0 then
        raise exception 'Integrar las RPC Android en check_account_access antes de aplicar esta migracion';
      end if;
      execute replace(definition,'''rpc/register_push_device''',
        '''rpc/register_push_device'',''rpc/register_android_push_device'',''rpc/unregister_android_push_device''');
    end if;
  end if;
end;
$$;
notify pgrst, 'reload schema';
commit;
