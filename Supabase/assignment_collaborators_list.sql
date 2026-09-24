-- Execute after milestone_collaborators.sql.
begin;
create or replace function public.assignment_collaborators(p_assignment uuid)
returns table(id uuid, nombre text, cargo text, es_supervisor boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.account_is_approved()
    or not public.puede_ver_asignacion(p_assignment) then
    raise exception 'No tienes acceso a esta asignación' using errcode = '42501';
  end if;
  return query
  with members as (
    select c.usuario_id from public.hitos_colaboradores c
    join public.hitos_itinerario h on h.id = c.hito_id
    where h.asignacion_id = p_assignment
    union
    select s.usuario_id from public.asignacion_supervisores s
    where s.asignacion_id = p_assignment
  )
  select p.id, coalesce(nullif(btrim(p.nombre_completo),''),'Sin nombre'),
    coalesce(nullif(btrim(p.cargo),''),'Sin cargo'),
    exists(select 1 from public.asignacion_supervisores s
      where s.asignacion_id = p_assignment and s.usuario_id = p.id) as supervisor
  from members m join public.perfiles p on p.id = m.usuario_id
  order by supervisor desc, lower(p.nombre_completo), p.id;
end $$;
revoke all on function public.assignment_collaborators(uuid) from public,anon;
grant execute on function public.assignment_collaborators(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
