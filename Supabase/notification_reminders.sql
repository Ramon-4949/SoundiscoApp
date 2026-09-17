-- Apply after notifications_setup.sql.
-- Invoke every minute using Supabase Cron (not executed by this migration).
create or replace function public.generate_notification_reminders()
returns void language plpgsql security definer set search_path = '' as $$
declare r record; recipient uuid; phase text; event_key text;
begin
  if not pg_try_advisory_xact_lock(81420931) then return; end if;
  for r in
    select a.id aid,a.titulo,a.estado,h.id milestone,h.descripcion description,h.fecha_programada due
    from public.asignaciones a join public.hitos_itinerario h on h.asignacion_id = a.id
    where a.tipo_flujo = 'campo' and coalesce(a.estado,'pendiente') <> 'completada'
      and not coalesce(h.completado,false) and coalesce(h.estado_hito,'') <> 'completado'
      and h.fecha_programada between now() - interval '1 day' and now() + interval '15 minutes'
      and not exists(select 1 from public.hitos_itinerario prior where prior.asignacion_id = a.id
        and prior.orden < h.orden and not coalesce(prior.completado,false) and coalesce(prior.estado_hito,'') <> 'completado')
    union all
    select a.id,a.titulo,a.estado,null::uuid,'Fecha límite',a.fecha_limite
    from public.asignaciones a where a.tipo_flujo <> 'campo' and coalesce(a.estado,'pendiente') <> 'completada'
      and a.fecha_limite between now() - interval '1 day' and now() + interval '15 minutes'
  loop
    phase := case when r.due <= now() then 'vencida' else 'proxima' end;
    event_key := 'reminder:' || coalesce(r.milestone,r.aid)::text || ':' ||
      extract(epoch from r.due)::text || ':' || phase;
    for recipient in
      select perfil_id from public.asignacion_equipo where asignacion_id = r.aid
      union select id from public.perfiles where rol = 'admin' and phase = 'vencida'
    loop
      perform notification_private.emit(recipient,'recordatorio',r.titulo,
        case phase when 'vencida' then 'Horario vencido: ' else 'En los próximos 15 minutos: ' end || r.description,
        'asignacion',r.aid,case phase when 'vencida' then 'vencida' else r.estado end,event_key);
    end loop;
  end loop;
end;
$$;
revoke all on function public.generate_notification_reminders() from public,anon,authenticated;
grant execute on function public.generate_notification_reminders() to service_role;
