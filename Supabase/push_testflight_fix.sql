-- Apply once in Supabase SQL Editor. This fixes APNs registration after an app
-- reinstall/update reuses a token with a new local installation identifier.
begin;

create or replace function public.register_push_device(
  p_installation uuid,
  p_token text,
  p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null
    or not exists(select 1 from public.perfiles where id = auth.uid()) then
    raise exception 'Perfil requerido' using errcode = '42501';
  end if;

  if p_token !~ '^[0-9a-f]{64,200}$'
    or p_environment not in ('sandbox', 'production') then
    raise exception 'Dispositivo invalido' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_environment || ':' || p_token, 0)
  );

  delete from notification_private.devices
  where token = p_token
    and environment = p_environment
    and installation <> p_installation;

  insert into notification_private.devices(
    installation,
    perfil_id,
    token,
    environment,
    updated_at
  )
  values(
    p_installation,
    auth.uid(),
    p_token,
    p_environment,
    now()
  )
  on conflict(installation) do update set
    perfil_id = excluded.perfil_id,
    token = excluded.token,
    environment = excluded.environment,
    updated_at = now();
end;
$$;

revoke all on function public.register_push_device(uuid,text,text)
from public, anon;
grant execute on function public.register_push_device(uuid,text,text)
to authenticated;

notify pgrst, 'reload schema';
commit;

-- Safe diagnostics: no device token or installation identifier is returned.
select
  u.email,
  coalesce(d.environment, 'sin_registrar') as apns_environment,
  d.updated_at as dispositivo_actualizado,
  count(o.id) filter (where o.sent_at is not null) as pushes_aceptados,
  count(o.id) filter (where o.sent_at is null) as pushes_pendientes,
  max(o.last_error) filter (where o.sent_at is null) as ultimo_error_apns
from auth.users u
left join notification_private.devices d on d.perfil_id = u.id
left join notification_private.outbox o on o.installation = d.installation
group by u.id, u.email, d.environment, d.updated_at
order by u.email, d.updated_at desc nulls last;
