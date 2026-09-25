-- Apply after milestone_collaborators.sql.
-- Notes remain visible to assignment participants, but author names are disclosed
-- only to administrators and supervisors assigned to the same assignment.
begin;

create or replace function public.assignment_notes(
  p_assignment uuid,
  p_offset integer default 0,
  p_limit integer default 200
)
returns table(
  id uuid,
  usuario_id uuid,
  contenido text,
  created_at timestamptz,
  autor_nombre text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  reveal_authors boolean;
begin
  if auth.uid() is null
     or not coalesce(public.account_is_approved(), false)
     or not coalesce(public.puede_ver_asignacion(p_assignment), false) then
    raise exception 'No tienes acceso a esta asignación' using errcode = '42501';
  end if;

  if p_offset is null or p_limit is null or p_offset < 0 or p_limit < 1 or p_limit > 200 then
    raise exception 'Paginación inválida' using errcode = '22023';
  end if;

  reveal_authors := coalesce(public.can_supervise_assignment(p_assignment), false);

  return query
  select
    n.id,
    case when reveal_authors or n.usuario_id = auth.uid() then n.usuario_id end as usuario_id,
    n.contenido,
    n.created_at,
    case when reveal_authors then nullif(btrim(p.nombre_completo), '') end as autor_nombre
  from public.notas_asignacion n
  left join public.perfiles p on p.id = n.usuario_id
  where n.asignacion_id = p_assignment
  order by n.created_at desc, n.id
  offset p_offset
  limit p_limit;
end;
$$;

revoke all on function public.assignment_notes(uuid,integer,integer) from public, anon;
grant execute on function public.assignment_notes(uuid,integer,integer) to authenticated;

-- Prevent clients from bypassing the RPC and joining author UUIDs to profiles.
revoke select on public.notas_asignacion from authenticated;

notify pgrst, 'reload schema';
commit;
