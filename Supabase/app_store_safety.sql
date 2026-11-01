begin;

create schema if not exists moderation_private;
revoke all on schema moderation_private from public,anon,authenticated;

create table if not exists moderation_private.blocked_phrases (
  phrase text primary key check(char_length(phrase)>2)
);
insert into moderation_private.blocked_phrases values
  ('hijo de puta'),('hija de puta'),('vete a la mierda') on conflict do nothing;

create table if not exists moderation_private.note_reports (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notas_asignacion(id) on delete cascade,
  reporter_id uuid not null references public.perfiles(id) on delete cascade,
  reason text not null check(reason in ('acoso','contenido_inapropiado','datos_personales','otro')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique(note_id,reporter_id)
);
create index if not exists note_reports_pending on moderation_private.note_reports(created_at,id)
  where resolved_at is null;
alter table moderation_private.blocked_phrases enable row level security;
alter table moderation_private.note_reports enable row level security;
revoke all on all tables in schema moderation_private from public,anon,authenticated;

create or replace function moderation_private.validate_content()
returns trigger language plpgsql security definer set search_path='' as $$
declare content text;
begin
  content:=lower(regexp_replace(coalesce(to_jsonb(new)->>'contenido',
    (to_jsonb(new)->>'asunto')||' '||(to_jsonb(new)->>'mensaje'),''),'[[:space:][:punct:]]+',' ','g'));
  if exists(select 1 from moderation_private.blocked_phrases p
    where position(' '||p.phrase||' ' in ' '||content||' ')>0) then
    raise exception 'El contenido contiene expresiones no permitidas. Revísalo antes de publicarlo.' using errcode='22023';
  end if;
  return new;
end;
$$;
drop trigger if exists moderate_note_content on public.notas_asignacion;
create trigger moderate_note_content before insert or update of contenido on public.notas_asignacion
  for each row execute function moderation_private.validate_content();
drop trigger if exists moderate_bulletin_content on public.comunicados;
create trigger moderate_bulletin_content before insert or update of asunto,mensaje on public.comunicados
  for each row execute function moderation_private.validate_content();

create or replace function public.report_assignment_note(p_note_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
  if auth.uid() is null or not coalesce(public.account_is_approved(),false) then
    raise exception 'Acceso no aprobado' using errcode='42501'; end if;
  select asignacion_id into aid from public.notas_asignacion where id=p_note_id;
  if aid is null or not coalesce(public.puede_ver_asignacion(aid),false) then
    raise exception 'No tienes acceso a esta nota' using errcode='42501'; end if;
  if p_reason is null or p_reason not in ('acoso','contenido_inapropiado','datos_personales','otro') then
    raise exception 'Selecciona un motivo válido' using errcode='22023'; end if;
  insert into moderation_private.note_reports(note_id,reporter_id,reason)
    values(p_note_id,auth.uid(),p_reason) on conflict(note_id,reporter_id) do nothing;
end;
$$;

create or replace function public.admin_note_reports(p_offset integer default 0)
returns table(id uuid,note_id uuid,reason text,created_at timestamptz,contenido text,asignacion text)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not coalesce(public.account_is_approved(),false) or not public.es_admin() then
    raise exception 'Solo administradores pueden revisar reportes' using errcode='42501'; end if;
  return query select r.id,r.note_id,r.reason,r.created_at,n.contenido,a.titulo
    from moderation_private.note_reports r
    join public.notas_asignacion n on n.id=r.note_id
    join public.asignaciones a on a.id=n.asignacion_id
    where r.resolved_at is null order by r.created_at,r.id
    limit 50 offset greatest(coalesce(p_offset,0),0);
end;
$$;

create or replace function public.admin_resolve_note_report(p_report_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not coalesce(public.account_is_approved(),false) or not public.es_admin() then
    raise exception 'Solo administradores pueden revisar reportes' using errcode='42501'; end if;
  update moderation_private.note_reports set resolved_at=now() where id=p_report_id and resolved_at is null;
end;
$$;

create or replace function public.admin_remove_assignment_note(p_note_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not coalesce(public.account_is_approved(),false) or not public.es_admin() then
    raise exception 'Solo administradores pueden retirar notas' using errcode='42501'; end if;
  delete from public.notas_asignacion where id=p_note_id;
end;
$$;

create or replace function public.admin_suspend_account(p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not coalesce(public.account_is_approved(),false) or not public.es_admin() then
    raise exception 'Solo administradores pueden suspender accesos' using errcode='42501'; end if;
  if p_user_id=auth.uid() or exists(select 1 from public.perfiles where id=p_user_id and rol='admin') then
    raise exception 'No puedes suspender una cuenta administradora desde este panel' using errcode='42501'; end if;
  update account_private.access set estado='rechazada',reviewed_at=now(),reviewed_by=auth.uid()
    where user_id=p_user_id;
  if not found then raise exception 'La cuenta ya no existe' using errcode='P0002'; end if;
  delete from notification_private.devices where perfil_id=p_user_id;
  if to_regclass('android_push_private.devices') is not null then
    execute 'delete from android_push_private.devices where perfil_id=$1' using p_user_id;
  end if;
end;
$$;

revoke all on all functions in schema moderation_private from public,anon,authenticated;
revoke all on function public.report_assignment_note(uuid,text),public.admin_note_reports(integer),
  public.admin_resolve_note_report(uuid),public.admin_remove_assignment_note(uuid),
  public.admin_suspend_account(uuid) from public,anon,authenticated;
grant execute on function public.report_assignment_note(uuid,text),public.admin_note_reports(integer),
  public.admin_resolve_note_report(uuid),public.admin_remove_assignment_note(uuid),
  public.admin_suspend_account(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
