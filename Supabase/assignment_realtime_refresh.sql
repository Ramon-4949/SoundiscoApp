-- Ejecutar una vez para que las asignaciones se refresquen en tiempo real.
begin;

do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array[
      'asignaciones',
      'asignacion_equipo',
      'hitos_itinerario'
    ] loop
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          table_name
        );
      end if;
    end loop;
  end if;
end $$;

-- Los valores anteriores son necesarios para identificar bajas y reasignaciones.
alter table public.asignacion_equipo replica identity full;
alter table public.asignaciones replica identity full;
alter table public.hitos_itinerario replica identity full;

commit;
