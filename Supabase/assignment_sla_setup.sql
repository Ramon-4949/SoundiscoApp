-- Apply after assignment_expiration_setup.sql and account_access_setup.sql.
begin;
create schema if not exists sla_private;
revoke all on schema sla_private from public, anon, authenticated;

-- One source of truth; existing editors continue writing fecha_programada.
alter table public.hitos_itinerario add column if not exists hora_programada timestamptz
  generated always as (fecha_programada) stored;
alter table public.hitos_itinerario add column if not exists sla_abierto boolean not null default false;
create table if not exists sla_private.windows (
  hito_id uuid primary key references public.hitos_itinerario(id) on delete cascade,
  hora_programada timestamptz not null,
  opened_at timestamptz not null default clock_timestamp()
);
create table if not exists sla_private.participants (
  hito_id uuid references sla_private.windows(hito_id) on delete cascade,
  usuario_id uuid references public.perfiles(id) on delete cascade,
  primary key(hito_id, usuario_id)
);
create table if not exists public.confirmaciones_hitos (
  id uuid primary key default gen_random_uuid(),
  asignacion_id uuid not null references public.asignaciones(id) on delete cascade,
  hito_id uuid not null references public.hitos_itinerario(id) on delete cascade,
  usuario_id uuid not null references public.perfiles(id) on delete cascade,
  estado_hito text not null default 'completado' check(estado_hito = 'completado'),
  created_at timestamptz not null default clock_timestamp(),
  hora_programada timestamptz not null,
  evaluacion text not null check(evaluacion in ('temprano','a_tiempo','tardio')),
  unique(hito_id, usuario_id)
);
create index if not exists confirmations_assignment on public.confirmaciones_hitos(asignacion_id);
create index if not exists confirmations_user_time on public.confirmaciones_hitos(usuario_id, created_at);

-- Extend installations that already had the two-state SLA model and repair
-- their historical evaluations from the server timestamps.
alter table public.confirmaciones_hitos
  drop constraint if exists confirmaciones_hitos_evaluacion_check;
update public.confirmaciones_hitos
set evaluacion = case
  when created_at < hora_programada then 'temprano'
  when created_at <= hora_programada + interval '15 minutes' then 'a_tiempo'
  else 'tardio'
end;
alter table public.confirmaciones_hitos
  add constraint confirmaciones_hitos_evaluacion_check
  check(evaluacion in ('temprano','a_tiempo','tardio'));
create table if not exists public.notas_asignacion (
  id uuid primary key default gen_random_uuid(),
  asignacion_id uuid not null references public.asignaciones(id) on delete cascade,
  usuario_id uuid not null references public.perfiles(id) on delete cascade,
  contenido text not null check(char_length(btrim(contenido)) between 1 and 4000),
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists notes_assignment_time on public.notas_asignacion(asignacion_id, created_at);
alter table public.confirmaciones_hitos enable row level security;
alter table public.notas_asignacion enable row level security;
revoke all on public.confirmaciones_hitos, public.notas_asignacion from anon, authenticated;
grant select on public.confirmaciones_hitos, public.notas_asignacion to authenticated;
drop policy if exists sla_read on public.confirmaciones_hitos;
create policy sla_read on public.confirmaciones_hitos for select to authenticated
 using(public.account_is_approved() and (public.es_admin() or usuario_id = auth.uid())
   and public.puede_ver_asignacion(asignacion_id));
drop policy if exists notes_read on public.notas_asignacion;
create policy notes_read on public.notas_asignacion for select to authenticated
 using(public.account_is_approved() and public.puede_ver_asignacion(asignacion_id));

create or replace function sla_private.advance(p_assignment uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare h record; scheduled timestamptz; total integer; confirmed integer;
begin
  perform 1 from public.asignaciones where id=p_assignment for update;
  for h in select * from public.hitos_itinerario where asignacion_id=p_assignment order by orden loop
    if coalesce(h.completado,false) or h.estado_hito='completado' then continue; end if;
    scheduled := null;
    select hora_programada into scheduled from sla_private.windows where hito_id=h.id;
    if scheduled is null then
      if h.fecha_programada is null or h.fecha_programada > clock_timestamp() then exit; end if;
      insert into sla_private.windows(hito_id,hora_programada) values(h.id,h.fecha_programada)
        on conflict do nothing;
      if found then
        insert into sla_private.participants select h.id,perfil_id from public.asignacion_equipo
          where asignacion_id=p_assignment;
        update public.hitos_itinerario set sla_abierto=true where id=h.id;
      end if;
      select hora_programada into scheduled from sla_private.windows where hito_id=h.id;
    end if;
    select count(*) into total from sla_private.participants where hito_id=h.id;
    select count(*) into confirmed from public.confirmaciones_hitos c
      join sla_private.participants p on p.hito_id=c.hito_id and p.usuario_id=c.usuario_id where c.hito_id=h.id;
    if confirmed > 0 and (confirmed >= total or clock_timestamp() > scheduled + interval '15 minutes') then
      update public.hitos_itinerario set completado=true,estado_hito='completado',hora_real_completado=clock_timestamp()
        where id=h.id;
    else
      update public.hitos_itinerario set estado_hito='en_curso' where id=h.id and estado_hito is distinct from 'en_curso';
      exit;
    end if;
  end loop;
  update public.asignaciones a set estado = case
    when exists(select 1 from public.hitos_itinerario where asignacion_id=a.id)
      and not exists(select 1 from public.hitos_itinerario where asignacion_id=a.id and not coalesce(completado,false)) then 'completada'
    when public.assignment_deadline(a.id) <= clock_timestamp() then 'vencida'
    when exists(select 1 from public.confirmaciones_hitos where asignacion_id=a.id) then 'en_curso'
    else 'pendiente' end
  where a.id=p_assignment;
end $$;

create or replace function public.check_in_milestone(p_hito_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare h public.hitos_itinerario%rowtype; scheduled timestamptz; checked_at timestamptz; aid uuid;
begin
  if auth.uid() is null or not public.account_is_approved() then raise exception 'Acceso no aprobado' using errcode='42501'; end if;
  select asignacion_id into aid from public.hitos_itinerario where id=p_hito_id;
  perform 1 from public.asignaciones where id=aid for update;
  select * into h from public.hitos_itinerario where id=p_hito_id;
  if not found then raise exception 'El hito ya no existe'; end if;
  if not exists(select 1 from public.asignacion_equipo where asignacion_id=aid and perfil_id=auth.uid()) then
    raise exception 'No estas asignado a este evento' using errcode='42501'; end if;
  if exists(select 1 from public.confirmaciones_hitos where hito_id=h.id and usuario_id=auth.uid()) then return; end if;
  if exists(select 1 from public.hitos_itinerario where asignacion_id=aid and orden<h.orden
    and not coalesce(completado,false)) then
    raise exception 'Completa primero el hito anterior' using errcode='23514'; end if;
  perform sla_private.advance(aid);
  select hora_programada into scheduled from sla_private.windows where hito_id=h.id;
  if scheduled is null then
    if h.fecha_programada is null then raise exception 'El hito no tiene hora programada'; end if;
    insert into sla_private.windows(hito_id,hora_programada) values(h.id,h.fecha_programada)
      on conflict do nothing;
    if found then
      insert into sla_private.participants select h.id,perfil_id from public.asignacion_equipo
        where asignacion_id=aid;
      update public.hitos_itinerario set sla_abierto=true where id=h.id;
    end if;
    select hora_programada into scheduled from sla_private.windows where hito_id=h.id;
  end if;
  if not exists(select 1 from sla_private.participants where hito_id=h.id and usuario_id=auth.uid()) then
    raise exception 'No perteneces al equipo registrado al abrir este hito'; end if;
  checked_at := clock_timestamp();
  insert into public.confirmaciones_hitos(asignacion_id,hito_id,usuario_id,created_at,hora_programada,evaluacion)
    values(aid,h.id,auth.uid(),checked_at,scheduled,
      case
        when checked_at < scheduled then 'temprano'
        when checked_at <= scheduled + interval '15 minutes' then 'a_tiempo'
        else 'tardio'
      end);
  perform sla_private.advance(aid);
end $$;

-- Old app versions must no longer complete the global milestone on behalf of everyone.
create or replace function public.employee_complete_milestone(p_hito_id uuid,p_notas text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if nullif(btrim(p_notas),'') is not null then raise exception 'Actualiza la app para enviar notas independientes'; end if;
  perform public.check_in_milestone(p_hito_id);
end $$;

create or replace function public.add_assignment_note(p_id uuid,p_asignacion_id uuid,p_contenido text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.account_is_approved() or not public.puede_ver_asignacion(p_asignacion_id) then
    raise exception 'No tienes acceso a esta asignacion' using errcode='42501'; end if;
  if p_contenido is null or char_length(btrim(p_contenido)) not between 1 and 4000 then raise exception 'Escribe entre 1 y 4000 caracteres'; end if;
  insert into public.notas_asignacion(id,asignacion_id,usuario_id,contenido)
    values(p_id,p_asignacion_id,auth.uid(),btrim(p_contenido)) on conflict(id) do nothing;
end $$;

create or replace function sla_private.protect_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from sla_private.windows where hito_id=old.id) then
    if tg_op='DELETE' then
      if exists(select 1 from public.asignaciones where id=old.asignacion_id) then
        raise exception 'No se puede eliminar un hito con ventana SLA abierta'; end if;
      return old;
    end if;
    if (new.asignacion_id,new.orden,new.fecha_programada) is distinct from (old.asignacion_id,old.orden,old.fecha_programada) then
      raise exception 'No se puede cambiar el horario ni el orden de un hito con ventana SLA abierta'; end if;
  end if;
  return new;
end $$;
drop trigger if exists sla_protect_history on public.hitos_itinerario;
create trigger sla_protect_history before update on public.hitos_itinerario
 for each row execute function sla_private.protect_history();
-- Keep existing admin deletion workflows operational; FK cascades remove the SLA records.

create or replace function public.process_assignment_sla()
returns void language plpgsql security definer set search_path = '' as $$
declare a record;
begin
  if not pg_try_advisory_xact_lock(81420932) then return; end if;
  for a in select id from public.asignaciones where estado is distinct from 'completada' order by id loop
    perform sla_private.advance(a.id);
  end loop;
end $$;
revoke all on all functions in schema sla_private from public,anon,authenticated;
revoke all on all tables in schema sla_private from public,anon,authenticated;
revoke all on function public.process_assignment_sla() from public,anon,authenticated;
grant execute on function public.process_assignment_sla() to service_role;
revoke all on function public.check_in_milestone(uuid),public.add_assignment_note(uuid,uuid,text),
 public.employee_complete_milestone(uuid,text) from public,anon;
grant execute on function public.check_in_milestone(uuid),public.add_assignment_note(uuid,uuid,text),
 public.employee_complete_milestone(uuid,text) to authenticated;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('assignment-sla-every-minute','* * * * *','select public.process_assignment_sla();');
notify pgrst,'reload schema';
commit;
