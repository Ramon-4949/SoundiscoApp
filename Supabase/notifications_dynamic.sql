-- Run after notifications_setup.sql and notification_reminders.sql.
-- Apply BEFORE deploying the worker that calls claim_notification_pushes_v2.
begin;

alter table notification_private.assignment_events
  add column if not exists old_priority text,
  add column if not exists completed_milestones text[] not null default '{}';

-- Keep the existing transaction aggregation: replacing a team must not notify
-- retained members that they were removed and immediately assigned again.
create or replace function notification_private.capture_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  aid uuid; title text; state text; team uuid[]; priority text;
  content boolean := false; progress boolean := false; milestones text[] := '{}';
begin
  if tg_op = 'UPDATE' and to_jsonb(old) = to_jsonb(new) then return new; end if;
  if tg_table_name = 'asignaciones' then
    aid := case when tg_op = 'DELETE' then old.id else new.id end;
    title := case when tg_op = 'INSERT' then new.titulo else old.titulo end;
    state := case when tg_op = 'INSERT' then null else old.estado end;
    priority := case when tg_op = 'INSERT' then null else old.nivel_prioridad end;
    content := tg_op <> 'UPDATE' or
      (to_jsonb(old) - 'estado') is distinct from (to_jsonb(new) - 'estado');
    progress := tg_op = 'UPDATE' and old.estado is distinct from new.estado;
  else
    aid := case when tg_op = 'DELETE' then old.asignacion_id else new.asignacion_id end;
    select titulo,estado,nivel_prioridad into title,state,priority from public.asignaciones where id = aid;
    if tg_table_name = 'hitos_itinerario' then
      progress := tg_op = 'UPDATE' and
        (old.completado,old.estado_hito,old.notas_incidencias) is distinct from
        (new.completado,new.estado_hito,new.notas_incidencias);
      if tg_op = 'UPDATE' and (coalesce(new.completado,false) or new.estado_hito = 'completado')
        and not (coalesce(old.completado,false) or coalesce(old.estado_hito,'') = 'completado') then
        milestones := array[coalesce(nullif(new.descripcion,''),'el hito')];
      end if;
      content := tg_op <> 'UPDATE' or
        (old.descripcion,old.fecha_programada,old.orden) is distinct from
        (new.descripcion,new.fecha_programada,new.orden);
    end if;
  end if;
  select coalesce(array_agg(distinct perfil_id),'{}') into team
    from public.asignacion_equipo where asignacion_id = aid;
  insert into notification_private.assignment_events(
    transaction_id,assignment_id,old_team,old_title,old_state,actor,content_changed,
    progress_changed,old_priority,completed_milestones)
  values(txid_current(),aid,team,title,state,auth.uid(),content,progress,priority,milestones)
  on conflict(transaction_id,assignment_id) do update set
    content_changed = assignment_events.content_changed or excluded.content_changed,
    progress_changed = assignment_events.progress_changed or excluded.progress_changed,
    completed_milestones = assignment_events.completed_milestones || excluded.completed_milestones;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function notification_private.flush_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  e notification_private.assignment_events%rowtype; a public.asignaciones%rowtype;
  team uuid[]; recipient uuid; kind text; title text; body text; actor_name text;
  event_key text; assignment_title text; milestone text; is_admin boolean; milestone_index int;
begin
  delete from notification_private.assignment_events
    where transaction_id = new.transaction_id and assignment_id = new.assignment_id returning * into e;
  if not found then return null; end if;
  select * into a from public.asignaciones where id = e.assignment_id;
  select coalesce(array_agg(distinct perfil_id),'{}') into team
    from public.asignacion_equipo where asignacion_id = e.assignment_id;
  select nullif(nombre_completo,'') into actor_name from public.perfiles where id = e.actor;
  actor_name := coalesce(actor_name,'Un miembro del equipo');
  assignment_title := coalesce(nullif(a.titulo,''),nullif(e.old_title,''),'la actividad');
  event_key := e.transaction_id::text || ':' || e.assignment_id::text;
  for recipient in select distinct unnest(e.old_team || team ||
    coalesce((select array_agg(id) from public.perfiles where rol = 'admin'),'{}')) loop
    select exists(select 1 from public.perfiles where id = recipient and rol = 'admin') into is_admin;
    if a.id is null then
      kind := 'asignacion_eliminada'; title := 'Asignación cancelada';
      body := 'La asignación ' || assignment_title || ' ha sido eliminada';
    elsif recipient = any(e.old_team) and not recipient = any(team) and not is_admin then
      kind := 'asignacion_retirada'; title := 'Asignación cancelada';
      body := 'Has sido removido de la asignación ' || assignment_title;
    elsif recipient = any(team) and not recipient = any(e.old_team) then
      kind := 'asignacion_nueva'; title := 'Nueva asignación';
      body := case when a.tipo_flujo = 'campo' then 'Se te ha asignado al montaje: '
        else 'Se te ha asignado la tarea: ' end || assignment_title;
    elsif e.old_state is distinct from a.estado and a.estado = 'completada' then
      kind := 'asignacion_completada'; title := 'Asignación completada';
      body := actor_name || ' ha completado la asignación ' || assignment_title;
    elsif cardinality(e.completed_milestones) > 0 then
      -- A completion may also change assignment state in the same transaction.
      -- Preserve the milestone name instead of replacing it with a generic state notice.
      kind := null;
    elsif e.old_state is distinct from a.estado and e.old_state is not null then
      kind := 'estado_actualizado'; title := 'Estado actualizado';
      body := actor_name || ' cambió el estado de ' || assignment_title || ' a ' || coalesce(a.estado,'pendiente');
    elsif e.progress_changed then
      kind := 'estado_actualizado'; title := 'Checklist actualizado';
      body := actor_name || ' actualizó el checklist de ' || assignment_title;
    elsif e.content_changed or
      (select array_agg(x order by x) from unnest(e.old_team) x) is distinct from
      (select array_agg(x order by x) from unnest(team) x) then
      kind := 'asignacion_actualizada'; title := 'Cambios en tu evento';
      body := 'La asignación ' || assignment_title || ' ha sido modificada';
    else kind := null;
    end if;
    if kind is not null then
      perform notification_private.emit(recipient,kind,title,body,'asignacion',e.assignment_id,a.estado,event_key);
    end if;
    if a.id is not null and is_admin then
      milestone_index := 0;
      foreach milestone in array e.completed_milestones loop
        milestone_index := milestone_index + 1;
        perform notification_private.emit(recipient,'hito_completado','Confirmación de Hito',
          actor_name || ' confirmó ' || milestone,'asignacion',e.assignment_id,a.estado,
          event_key || ':hito:' || milestone_index::text);
      end loop;
    end if;
    if a.id is not null and (is_admin or recipient = any(team)) then
      if lower(a.nivel_prioridad) = 'alta' and lower(coalesce(e.old_priority,'')) <> 'alta' then
        perform notification_private.emit(recipient,'asignacion_urgente','¡URGENTE!',
          'La asignación ' || assignment_title || ' ha sido marcada como urgente. Se requiere atención inmediata en el evento.',
          'asignacion',e.assignment_id,a.estado,event_key || ':urgente');
      end if;
    end if;
  end loop;
  return null;
end;
$$;

create or replace function notification_private.bulletin_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.comunicados%rowtype; recipient uuid; kind text; title text; body text;
begin
  if tg_op = 'UPDATE' and (old.asunto,old.mensaje) is not distinct from (new.asunto,new.mensaje) then return new; end if;
  if tg_op = 'DELETE' then c := old; else c := new; end if;
  kind := case tg_op when 'INSERT' then 'comunicado_nuevo' when 'UPDATE' then 'comunicado_actualizado' else 'comunicado_eliminado' end;
  title := case tg_op when 'INSERT' then 'Nuevo Comunicado de Admin' when 'UPDATE' then 'Comunicado actualizado' else 'Comunicado retirado' end;
  body := case tg_op when 'INSERT' then c.asunto when 'UPDATE' then 'El comunicado ' || c.asunto || ' ha sido modificado'
    else 'El comunicado ' || c.asunto || ' ya no está disponible' end;
  for recipient in select id from public.perfiles loop
    perform notification_private.emit(recipient,kind,title,body,'comunicado',c.id,null,
      txid_current()::text || ':comunicado:' || c.id::text || ':' || tg_op);
  end loop;
  if tg_op = 'DELETE' then return old; end if; return new;
end;
$$;

create or replace function public.generate_notification_reminders()
returns void language plpgsql security definer set search_path = '' as $$
declare r record; recipient uuid; phase text; event_key text; title text; body text;
begin
  if not pg_try_advisory_xact_lock(81420931) then return; end if;
  for r in
    select a.id aid,a.titulo,a.estado,h.id milestone,h.descripcion description,h.fecha_programada due
    from public.asignaciones a join public.hitos_itinerario h on h.asignacion_id = a.id
    where coalesce(a.estado,'pendiente') <> 'completada'
      and not coalesce(h.completado,false) and coalesce(h.estado_hito,'') <> 'completado'
      and h.fecha_programada between now() - interval '1 day' and now() + interval '15 minutes'
      and not exists(select 1 from public.hitos_itinerario prior where prior.asignacion_id = a.id
        and prior.orden < h.orden and not coalesce(prior.completado,false) and coalesce(prior.estado_hito,'') <> 'completado')
    union all
    select a.id,a.titulo,a.estado,null::uuid,'Fecha límite',
      coalesce(a.fecha_limite,(select max(fecha_programada) from public.hitos_itinerario where asignacion_id = a.id))
    from public.asignaciones a where coalesce(a.estado,'pendiente') <> 'completada'
      and coalesce(a.fecha_limite,(select max(fecha_programada) from public.hitos_itinerario where asignacion_id = a.id))
        between now() - interval '1 day' and now() + interval '15 minutes'
  loop
    phase := case when r.due <= now() then 'vencida' else 'proxima' end;
    event_key := 'reminder:' || coalesce(r.milestone,r.aid)::text || ':' || extract(epoch from r.due)::text || ':' || phase;
    title := case when r.milestone is not null then 'Alerta de Hito' else 'Cierre de Asignación' end;
    body := case when r.milestone is not null then 'El hito ' || coalesce(r.description,'pendiente') ||
        case phase when 'proxima' then ' está por vencer pronto' else ' ha vencido' end
      else 'La asignación ' || r.titulo || case phase when 'proxima' then ' está próxima a su fecha límite' else ' ha llegado a su fecha límite' end end;
    for recipient in
      select perfil_id from public.asignacion_equipo where asignacion_id = r.aid
      union select id from public.perfiles where rol = 'admin' and phase = 'vencida'
    loop
      perform notification_private.emit(recipient,'recordatorio',title,body,'asignacion',r.aid,
        case phase when 'vencida' then 'vencida' else r.estado end,event_key);
    end loop;
  end loop;
end;
$$;

-- Versioned RPC leaves the running v1 worker compatible during rollout.
create or replace function public.claim_notification_pushes_v2()
returns table(job_id uuid, lease uuid, notification_id uuid, recipient uuid, token text,
  environment text, title text, body text)
language sql security definer set search_path = '' as $$
  select j.job_id,j.lease,j.notification_id,j.recipient,j.token,j.environment,n.titulo,n.mensaje
  from public.claim_notification_pushes() j join public.notificaciones_app n
    on n.id = j.notification_id and n.perfil_id = j.recipient;
$$;
revoke all on function public.claim_notification_pushes_v2() from public,anon,authenticated;
grant execute on function public.claim_notification_pushes_v2() to service_role;

-- Registration is currently open. Do not claim that approval is pending.
-- Notify when the application profile exists, for both signup and manual creation.
create or replace function notification_private.profile_registered()
returns trigger language plpgsql security definer set search_path = '' as $$
declare recipient uuid;
begin
  for recipient in select id from public.perfiles where rol = 'admin' and id <> new.id loop
    perform notification_private.emit(recipient,'usuario_nuevo','Nuevo registro',
      'Un nuevo usuario ha creado sus credenciales','perfil',new.id,null,'registro:' || new.id::text);
  end loop;
  return new;
end;
$$;
drop trigger if exists notification_profile_registered on public.perfiles;
create trigger notification_profile_registered after insert on public.perfiles
for each row execute function notification_private.profile_registered();
revoke all on all functions in schema notification_private from public,anon,authenticated;
notify pgrst, 'reload schema';
commit;
