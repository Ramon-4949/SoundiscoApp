-- Apply after notifications_dynamic.sql. Milestone confirmations are private
-- operational signals for administrators; all other routing stays unchanged.
begin;

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

revoke all on function notification_private.flush_assignment() from public,anon,authenticated;
notify pgrst, 'reload schema';
commit;
