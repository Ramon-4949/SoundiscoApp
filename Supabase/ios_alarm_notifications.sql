begin;

create or replace function public.claim_notification_pushes_v4()
returns table(job_id uuid, lease uuid, notification_id uuid, recipient uuid, token text,
  environment text, title text, body text, badge integer, is_alarm boolean)
language sql security definer set search_path='' as $$
  select j.*,coalesce(n.payload->'is_alarm'='true'::jsonb,false)
  from public.claim_notification_pushes_v3() j
  join public.notificaciones_app n on n.id=j.notification_id and n.perfil_id=j.recipient;
$$;

revoke all on function public.claim_notification_pushes_v4() from public,anon,authenticated;
grant execute on function public.claim_notification_pushes_v4() to service_role;

notify pgrst,'reload schema';
commit;
