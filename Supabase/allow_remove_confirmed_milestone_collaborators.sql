begin;

create or replace function milestone_private.save_members(
  p_assignment uuid,
  p_hitos jsonb,
  p_supervisores jsonb
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_hito jsonb;
begin
  delete from public.confirmaciones_hitos c using public.hitos_itinerario h
    where h.id=c.hito_id and h.asignacion_id=p_assignment and not exists(
      select 1 from jsonb_array_elements(p_hitos) j
      cross join lateral jsonb_array_elements_text(j->'colaboradores') u
      where (j->>'id')::uuid=h.id and u.value::uuid=c.usuario_id);

  delete from public.hitos_colaboradores c using public.hitos_itinerario h
    where h.id=c.hito_id and h.asignacion_id=p_assignment and not exists(
      select 1 from jsonb_array_elements(p_hitos) j
      cross join lateral jsonb_array_elements_text(j->'colaboradores') u
      where (j->>'id')::uuid=h.id and u.value::uuid=c.usuario_id);

  for v_hito in select value from jsonb_array_elements(p_hitos) loop
    insert into public.hitos_colaboradores(hito_id,usuario_id,hora_programada)
      select (v_hito->>'id')::uuid,value::uuid,(v_hito->>'fecha_programada')::timestamptz
      from jsonb_array_elements_text(v_hito->'colaboradores')
      on conflict do nothing;
  end loop;

  update public.hitos_colaboradores c set hora_programada=h.fecha_programada
    from public.hitos_itinerario h
    where h.id=c.hito_id and h.asignacion_id=p_assignment and c.confirmado_at is null;

  delete from public.asignacion_supervisores where asignacion_id=p_assignment;
  insert into public.asignacion_supervisores
    select distinct p_assignment,value::uuid
    from jsonb_array_elements_text(p_supervisores);

  insert into sla_private.windows(hito_id,hora_programada)
    select id,fecha_programada from public.hitos_itinerario where asignacion_id=p_assignment
    on conflict(hito_id) do update set hora_programada=excluded.hora_programada;

  delete from sla_private.participants
    where hito_id in(select id from public.hitos_itinerario where asignacion_id=p_assignment);
  insert into sla_private.participants
    select c.hito_id,c.usuario_id from public.hitos_colaboradores c
    join public.hitos_itinerario h on h.id=c.hito_id
    where h.asignacion_id=p_assignment;
end
$$;

notify pgrst, 'reload schema';
commit;
