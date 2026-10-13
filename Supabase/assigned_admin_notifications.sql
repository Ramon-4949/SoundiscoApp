begin;

create or replace function notification_private.emit(
  recipient uuid, kind text, title text, body text, target_type text, target_id uuid, state text, event_key text
) returns void language sql security definer set search_path='' as $$
  insert into public.notificaciones_app(id,perfil_id,titulo,mensaje,leida,fecha_creacion,
    tipo,destino_tipo,destino_id,estado,evento_key)
  select gen_random_uuid(),recipient,title,body,false,now(),kind,target_type,target_id,state,event_key
  where recipient is distinct from auth.uid()
    or (kind='asignacion_nueva' and target_type='asignacion' and exists(
      select 1 from public.asignacion_equipo e where e.asignacion_id=target_id and e.perfil_id=recipient))
  on conflict(perfil_id,evento_key) do nothing;
$$;

create or replace function notification_private.flush_assignment()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  e notification_private.assignment_events%rowtype;
  a public.asignaciones%rowtype;
  team uuid[]; recipient uuid; kind text; title text; body text;
  event_key text; assignment_title text;
begin
  delete from notification_private.assignment_events
    where transaction_id=new.transaction_id and assignment_id=new.assignment_id returning * into e;
  if not found then return null; end if;
  if current_setting('soundisco.individual_checkin',true)='true' then return null; end if;
  select * into a from public.asignaciones where id=e.assignment_id;
  select coalesce(array_agg(distinct perfil_id),'{}') into team
    from public.asignacion_equipo where asignacion_id=e.assignment_id;
  assignment_title:=coalesce(nullif(a.titulo,''),nullif(e.old_title,''),'la actividad');
  event_key:=e.transaction_id::text||':'||e.assignment_id::text;
  for recipient in select distinct unnest(e.old_team||team) loop
    kind:=null;
    if a.id is null then
      kind:='asignacion_eliminada'; title:='Asignación cancelada';
      body:='La asignación '||assignment_title||' ha sido eliminada';
    elsif recipient=any(e.old_team) and not recipient=any(team) then
      kind:='asignacion_retirada'; title:='Asignación cancelada';
      body:='Has sido removido de la asignación '||assignment_title;
    elsif recipient=any(team) and not recipient=any(e.old_team) then
      kind:='asignacion_nueva'; title:='Nueva asignación';
      body:=case when a.tipo_flujo='campo' then 'Se te ha asignado al montaje: '
        else 'Se te ha asignado la tarea: ' end||assignment_title;
    elsif e.content_changed or
      (select array_agg(x order by x) from unnest(e.old_team) x) is distinct from
      (select array_agg(x order by x) from unnest(team) x) then
      kind:='asignacion_actualizada'; title:='Cambios en tu evento';
      body:='La asignación '||assignment_title||' ha sido modificada';
    end if;
    if kind is not null then
      perform notification_private.emit(recipient,kind,title,body,'asignacion',e.assignment_id,a.estado,event_key);
    end if;
    if a.id is not null and recipient=any(team) and lower(a.nivel_prioridad)='alta'
      and lower(coalesce(e.old_priority,''))<>'alta' then
      perform notification_private.emit(recipient,'asignacion_urgente','¡URGENTE!',
        'La asignación '||assignment_title||' ha sido marcada como urgente. Se requiere atención inmediata en el evento.',
        'asignacion',e.assignment_id,a.estado,event_key||':urgente');
    end if;
  end loop;
  return null;
end;
$$;

revoke all on function notification_private.emit(uuid,text,text,text,text,uuid,text,text),
  notification_private.flush_assignment() from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
