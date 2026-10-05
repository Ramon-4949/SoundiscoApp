-- Apply after assignment_status_automation.sql and notifications_dynamic.sql.
begin;

create or replace function public.check_in_milestone(p_hito_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare h public.hitos_itinerario%rowtype; aid uuid; checked timestamptz;
  evaluation text; recipient uuid; actor_name text; confirmation_id uuid;
begin
  if auth.uid() is null or not coalesce(public.account_is_approved(),false) then
    raise exception 'Acceso no aprobado' using errcode='42501'; end if;
  select asignacion_id into aid from public.hitos_itinerario where id=p_hito_id;
  perform 1 from public.asignaciones where id=aid for update;
  select * into h from public.hitos_itinerario where id=p_hito_id;
  if not found then raise exception 'El hito ya no existe'; end if;
  if not exists(select 1 from public.hitos_colaboradores where hito_id=h.id and usuario_id=auth.uid()) then
    raise exception 'No estás asignado a este hito' using errcode='42501'; end if;
  if exists(select 1 from public.hitos_colaboradores where hito_id=h.id and usuario_id=auth.uid() and confirmado_at is not null) then return; end if;
  if h.fecha_programada is null then raise exception 'Falta la fecha límite del hito'; end if;
  if exists(select 1 from public.hitos_itinerario m join public.hitos_colaboradores c on c.hito_id=m.id
    where m.asignacion_id=aid and m.orden<h.orden and c.usuario_id=auth.uid() and c.confirmado_at is null) then
    raise exception 'Confirma primero tu hito anterior' using errcode='23514'; end if;
  checked:=clock_timestamp();
  evaluation:=case when checked<h.fecha_programada then 'temprano'
    when checked=h.fecha_programada then 'a_tiempo' else 'tardio' end;
  update public.hitos_colaboradores set confirmado_at=checked,hora_programada=h.fecha_programada,estado=evaluation
    where hito_id=h.id and usuario_id=auth.uid();
  insert into public.confirmaciones_hitos(asignacion_id,hito_id,usuario_id,created_at,hora_programada,evaluacion)
    values(aid,h.id,auth.uid(),checked,h.fecha_programada,evaluation) returning id into confirmation_id;
  select coalesce(nombre_completo,'Un colaborador') into actor_name from public.perfiles where id=auth.uid();
  for recipient in
    select id from public.perfiles where rol='admin'
    union select usuario_id from public.asignacion_supervisores where asignacion_id=aid
  loop
    perform notification_private.emit(recipient,'hito_completado','Confirmación de Hito',
      actor_name||' confirmó '||h.descripcion,'asignacion',aid,null,
      'checkin:'||confirmation_id::text);
  end loop;
  perform set_config('soundisco.individual_checkin','true',true);
  perform sla_private.advance(aid);
  if exists(select 1 from public.asignaciones where id=aid and estado='completada') then
    for recipient in
      select id from public.perfiles where rol='admin'
      union select usuario_id from public.asignacion_supervisores where asignacion_id=aid
    loop
      perform notification_private.emit(recipient,'asignacion_completada','Asignación completada',
        'El evento ha sido completado al 100%', 'asignacion',aid,'completada',
        'checkin-complete:'||confirmation_id::text);
    end loop;
  end if;
end $$;

create or replace function public.undo_milestone_confirmation(p_hito_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare h public.hitos_itinerario%rowtype; aid uuid; confirmation_id uuid; recipient uuid; actor_name text;
begin
  if auth.uid() is null or not coalesce(public.account_is_approved(),false) then
    raise exception 'Acceso no aprobado' using errcode='42501'; end if;
  select asignacion_id into aid from public.hitos_itinerario where id=p_hito_id;
  perform 1 from public.asignaciones where id=aid for update;
  select * into h from public.hitos_itinerario where id=p_hito_id;
  if not found then raise exception 'El hito ya no existe'; end if;
  if not exists(select 1 from public.hitos_colaboradores where hito_id=h.id and usuario_id=auth.uid()) then
    raise exception 'No estás asignado a este hito' using errcode='42501'; end if;
  if not exists(select 1 from public.hitos_colaboradores where hito_id=h.id and usuario_id=auth.uid() and confirmado_at is not null) then return; end if;
  delete from public.confirmaciones_hitos where hito_id=h.id and usuario_id=auth.uid() returning id into confirmation_id;
  update public.hitos_colaboradores set confirmado_at=null,estado='sin_confirmar',hora_programada=h.fecha_programada
    where hito_id=h.id and usuario_id=auth.uid();
  perform sla_private.advance(aid);
  select coalesce(nombre_completo,'Un colaborador') into actor_name from public.perfiles where id=auth.uid();
  for recipient in
    select id from public.perfiles where rol='admin'
    union select usuario_id from public.asignacion_supervisores where asignacion_id=aid
  loop
    perform notification_private.emit(recipient,'hito_revertido','Confirmación deshecha',
      actor_name||' deshizo su confirmación de '||h.descripcion,'asignacion',aid,null,
      'undo:'||coalesce(confirmation_id,gen_random_uuid())::text);
  end loop;
end $$;
revoke all on function public.check_in_milestone(uuid),public.undo_milestone_confirmation(uuid) from public,anon;
grant execute on function public.check_in_milestone(uuid),public.undo_milestone_confirmation(uuid) to authenticated;

create or replace function notification_private.assignment_note_added()
returns trigger language plpgsql security definer set search_path='' as $$
declare assignment_title text;
begin
  select titulo into assignment_title from public.asignaciones where id=new.asignacion_id;
  insert into public.notificaciones_app(id,perfil_id,titulo,mensaje,leida,fecha_creacion,
    tipo,destino_tipo,destino_id,asignacion_relacionada_id,evento_key)
  select gen_random_uuid(),r.id,'Nueva nota / incidencia',
    'Se añadió una nota o incidencia en '||coalesce(assignment_title,'la asignación'),false,now(),
    'nota_asignacion','asignacion',new.asignacion_id,new.asignacion_id,'note:'||new.id::text
  from (
    select id from public.perfiles where rol='admin'
    union select usuario_id from public.asignacion_supervisores where asignacion_id=new.asignacion_id
    union select c.usuario_id from public.hitos_colaboradores c
      join public.hitos_itinerario h on h.id=c.hito_id where h.asignacion_id=new.asignacion_id
  ) r on conflict(perfil_id,evento_key) do nothing;
  return new;
end $$;
revoke all on function notification_private.assignment_note_added() from public,anon,authenticated;
drop trigger if exists notification_assignment_note on public.notas_asignacion;
create trigger notification_assignment_note after insert on public.notas_asignacion
  for each row execute function notification_private.assignment_note_added();

create index if not exists notification_unread_recipient on public.notificaciones_app(perfil_id)
  where leida is not true;
create or replace function public.claim_notification_pushes_v3()
returns table(job_id uuid, lease uuid, notification_id uuid, recipient uuid, token text,
  environment text, title text, body text, badge integer)
language sql security definer set search_path='' as $$
  select j.*, (select count(*)::integer from public.notificaciones_app n
    where n.perfil_id=j.recipient and n.leida is not true)
  from public.claim_notification_pushes_v2() j;
$$;
revoke all on function public.claim_notification_pushes_v3() from public,anon,authenticated;
grant execute on function public.claim_notification_pushes_v3() to service_role;
notify pgrst,'reload schema';
commit;
