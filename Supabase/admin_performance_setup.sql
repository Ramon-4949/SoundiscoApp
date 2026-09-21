-- Apply after account_access_setup.sql, employee_availability.sql and assignment_sla_setup.sql.
begin;
create index if not exists sla_participants_user on sla_private.participants(usuario_id,hito_id);
create index if not exists notes_user_created on public.notas_asignacion(usuario_id,created_at);

create or replace function public.admin_employee_performance(
  p_month date, p_offset integer default 0, p_employee uuid default null
)
returns setof jsonb language plpgsql stable security definer set search_path = '' as $$
declare start_at timestamptz; end_at timestamptz;
begin
  if auth.uid() is null or not coalesce(public.es_admin(),false) then
    raise exception 'Solo administradores pueden consultar rendimiento' using errcode='42501';
  end if;
  if p_month is null then raise exception 'Selecciona un mes'; end if;
  start_at := date_trunc('month',p_month::timestamp) at time zone 'America/Santo_Domingo';
  end_at := (date_trunc('month',p_month::timestamp)+interval '1 month') at time zone 'America/Santo_Domingo';
  return query
  with employees as (
    select p.id,coalesce(nullif(btrim(p.nombre_completo),''),'Sin nombre') nombre,
      coalesce(nullif(btrim(p.cargo),''),'Sin cargo') cargo
    from public.perfiles p join account_private.access access on access.user_id=p.id
    where access.estado='aprobada' and coalesce(p.rol,'tecnico') <> 'admin'
      and (p_employee is null or p.id=p_employee)
    order by lower(coalesce(p.nombre_completo,'')),p.id
    limit 100 offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'id',e.id,'nombre',e.nombre,'cargo',e.cargo,
    'temprano',punctual.early,'a_tiempo',punctual.ontime,'tardio',punctual.late,
    'sin_confirmar',punctual.missing,'retraso_medio_minutos',punctual.delay,
    'notas_semanales',notes.weeks,
    'asignaciones',work.total,'completadas',work.completed,'activas',work.active,'vencidas',work.overdue
  )
  from employees e
  cross join lateral (
    select count(*) filter(where c.evaluacion='temprano') early,
      count(*) filter(where c.evaluacion='a_tiempo') ontime,
      count(*) filter(where c.evaluacion='tardio') late,
      count(*) filter(where c.id is null) missing,
      round(avg(greatest(0,extract(epoch from (c.created_at-c.hora_programada-interval '15 minutes'))/60))
        filter(where c.evaluacion='tardio'),1) delay
    from (
      select w.hito_id,w.hora_programada
      from sla_private.participants sp join sla_private.windows w using(hito_id)
      where sp.usuario_id=e.id
      union
      select c.hito_id,c.hora_programada from public.confirmaciones_hitos c where c.usuario_id=e.id
    ) scheduled
    left join public.confirmaciones_hitos c on c.hito_id=scheduled.hito_id and c.usuario_id=e.id
    where scheduled.hora_programada >= start_at and scheduled.hora_programada < end_at
      and (c.id is not null or scheduled.hora_programada+interval '15 minutes' < now())
  ) punctual
  cross join lateral (
    select jsonb_agg(jsonb_build_object('semana',week,'cantidad',amount) order by week) weeks
    from (
      select week,count(n.id) amount
      from generate_series(1,ceil(extract(day from (end_at at time zone 'America/Santo_Domingo')-interval '1 day')/7)::int) week
      left join public.notas_asignacion n on n.usuario_id=e.id and n.created_at>=start_at and n.created_at<end_at
        and ((extract(day from n.created_at at time zone 'America/Santo_Domingo')::int-1)/7)+1=week
      group by week
    ) weekly
  ) notes
  cross join lateral (
    select count(*) total,count(*) filter(where a.estado='completada') completed,
      count(*) filter(where coalesce(a.estado,'pendiente')<>'completada'
        and (a.estado='vencida' or coalesce(d.last_at,a.fecha_limite)<now())) overdue,
      count(*) filter(where coalesce(a.estado,'pendiente') not in ('completada','vencida')
        and (coalesce(d.last_at,a.fecha_limite)>=now() or coalesce(d.last_at,a.fecha_limite) is null)) active
    from public.asignaciones a
    left join lateral (
      select min(fecha_programada) first_at,max(fecha_programada) last_at
      from public.hitos_itinerario where asignacion_id=a.id
    ) d on true
    where a.id in (
      select asignacion_id from public.asignacion_equipo where perfil_id=e.id
      union select asignacion_id from public.confirmaciones_hitos where usuario_id=e.id
      union select h.asignacion_id from sla_private.participants sp
        join public.hitos_itinerario h on h.id=sp.hito_id where sp.usuario_id=e.id
    )
    and coalesce(case when a.tipo_flujo='administrativa' then a.fecha_creacion else d.first_at end,a.fecha_creacion)<end_at
    and coalesce(d.last_at,a.fecha_limite,a.fecha_creacion)>=start_at
  ) work;
end $$;
revoke all on function public.admin_employee_performance(date,integer,uuid) from public,anon;
grant execute on function public.admin_employee_performance(date,integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
