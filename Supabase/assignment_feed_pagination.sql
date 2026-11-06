begin;

create or replace function public.assignments_feed_page(
  p_offset integer default 0,p_limit integer default 10,p_status text default 'pending',
  p_search text default '',p_day_start timestamptz default null,p_day_end timestamptz default null
) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare page_size integer:=least(10,greatest(1,coalesce(p_limit,10)));
  page_offset integer:=greatest(0,coalesce(p_offset,0));
  search_text text:=lower(btrim(coalesce(p_search,''))); result jsonb;
  viewer uuid:=auth.uid(); administrator boolean:=public.es_admin();
begin
  if viewer is null or not coalesce(public.account_is_approved(),false) then
    raise exception 'Acceso no aprobado' using errcode='42501'; end if;
  if p_status is null or p_status not in('all','pending','overdue','completed') then
    raise exception 'Filtro de asignaciones no valido' using errcode='22023'; end if;
  if length(search_text)>100 then raise exception 'La busqueda excede 100 caracteres' using errcode='22023'; end if;
  if (p_day_start is null)<>(p_day_end is null) or p_day_end<=p_day_start
    or p_day_end-p_day_start>interval '26 hours' then
    raise exception 'Intervalo de agenda no valido' using errcode='22023'; end if;

  with accessible as (
    select a.*,
      not administrator and exists(select 1 from public.hitos_itinerario h where h.asignacion_id=a.id)
        and not exists(select 1 from public.asignacion_supervisores s where s.asignacion_id=a.id and s.usuario_id=viewer) personal
    from public.asignaciones a
    where public.puede_ver_asignacion(a.id) and (administrator or exists(
      select 1 from public.asignacion_equipo e where e.asignacion_id=a.id and e.perfil_id=viewer))
      and(search_text='' or strpos(lower(a.titulo),search_text)>0 or strpos(lower(coalesce(a.ubicacion,'')),search_text)>0)
  ), effective as (
    select a.*,
      case when a.personal then personal.last_at else coalesce(a.fecha_limite,hitos.last_at) end feed_deadline,
      case when a.personal then personal.total>0 and personal.remaining=0
        when a.estado is not null then lower(a.estado) in('completada','completado','finalizada','finalizado')
        else lower(coalesce(a.tipo_flujo,'')) like '%campo%' and hitos.total>0 and hitos.remaining=0 end feed_completed
    from accessible a
    cross join lateral(
      select count(*) total,count(*) filter(where not coalesce(h.completado,false)) remaining,
        (array_agg(h.fecha_programada order by coalesce(h.orden,0) desc,h.id) filter(where h.fecha_programada is not null))[1] last_at
      from public.hitos_itinerario h where h.asignacion_id=a.id
    ) hitos
    cross join lateral(
      select count(*) total,count(*) filter(where c.confirmado_at is null) remaining,
        (array_agg(h.fecha_programada order by coalesce(h.orden,0) desc,h.id))[1] last_at
      from public.hitos_itinerario h join public.hitos_colaboradores c on c.hito_id=h.id and c.usuario_id=viewer
      where h.asignacion_id=a.id
    ) personal
  ), classified as (
    select e.*,not e.feed_completed and ((not e.personal and e.estado='vencida') or e.feed_deadline<now()) feed_overdue
    from effective e
  ), candidates as materialized (
    select c.id,c.feed_deadline,c.fecha_creacion from classified c
    where (p_status='all' or(p_status='completed' and c.feed_completed)
      or(p_status='overdue' and c.feed_overdue)
      or(p_status='pending' and not c.feed_completed and not coalesce(c.feed_overdue,false)))
      and(p_day_start is null or(c.feed_deadline>=p_day_start and c.feed_deadline<p_day_end) or exists(
        select 1 from public.hitos_itinerario h where h.asignacion_id=c.id
          and h.fecha_programada>=p_day_start and h.fecha_programada<p_day_end))
    order by c.fecha_creacion desc,c.id desc
    limit page_size+1 offset page_offset
  ), page as (
    select * from candidates order by fecha_creacion desc,id desc limit page_size
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object(
      'hitos_itinerario',coalesce((select jsonb_agg(to_jsonb(h)||jsonb_build_object(
        'hitos_colaboradores',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('perfiles',
          case when p.id is null then null else jsonb_build_object('id',p.id,'nombre_completo',p.nombre_completo,'rol',p.rol) end))
          from public.hitos_colaboradores c left join public.perfiles p on p.id=c.usuario_id where c.hito_id=h.id),'[]'::jsonb))
        order by h.orden,h.id) from public.hitos_itinerario h where h.asignacion_id=a.id),'[]'::jsonb),
      'asignacion_supervisores',coalesce((select jsonb_agg(jsonb_build_object('usuario_id',s.usuario_id))
        from public.asignacion_supervisores s where s.asignacion_id=a.id),'[]'::jsonb),
      'asignacion_equipo',coalesce((select jsonb_agg(jsonb_build_object('perfiles',
        case when p.id is null then null else jsonb_build_object('id',p.id,'nombre_completo',p.nombre_completo,'rol',p.rol) end))
        from public.asignacion_equipo e left join public.perfiles p on p.id=e.perfil_id where e.asignacion_id=a.id),'[]'::jsonb))
      order by page.fecha_creacion desc,page.id desc)
      from page join public.asignaciones a on a.id=page.id),'[]'::jsonb),
    'has_more',(select count(*)>page_size from candidates),
    'next_offset',case when(select count(*)>page_size from candidates) then page_offset+page_size else null end)
    into result;
  return result;
end;
$$;

revoke all on function public.assignments_feed_page(integer,integer,text,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.assignments_feed_page(integer,integer,text,text,timestamptz,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
