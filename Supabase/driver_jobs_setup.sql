-- Ejecutar después de profile_roles_and_jobs.sql. Es seguro ejecutarlo más de una vez.
begin;

insert into public.cargos_empresa(nombre, orden, activo) values
  ('Chofer/Técnico de sonido', 11, true),
  ('Chofer/Técnico de audiovisuales', 12, true),
  ('Chofer/Técnico de iluminación', 13, true),
  ('Chofer/Encargado de estructura', 14, true),
  ('Chofer/Encargado de almacén', 15, true)
on conflict(nombre) do update set orden = excluded.orden, activo = true;

create or replace function account_private.normalizar_cargo(p_cargo text)
returns text language sql immutable set search_path = '' as $$
  select case lower(btrim(coalesce(p_cargo, '')))
    when 'técnico de sonido' then 'Técnico de sonido'
    when 'tecnico de sonido' then 'Técnico de sonido'
    when 'técnico audiovisuales' then 'Técnico audiovisuales'
    when 'tecnico audiovisuales' then 'Técnico audiovisuales'
    when 'técnico audiovisual' then 'Técnico audiovisuales'
    when 'tecnico audiovisual' then 'Técnico audiovisuales'
    when 'técnico de pantallas' then 'Técnico audiovisuales'
    when 'tecnico de pantallas' then 'Técnico audiovisuales'
    when 'técnico de iluminación' then 'Técnico de iluminación'
    when 'tecnico de iluminación' then 'Técnico de iluminación'
    when 'tecnico de iluminacion' then 'Técnico de iluminación'
    when 'encargado de estructura' then 'Encargado de estructura'
    when 'técnico de estructuras' then 'Encargado de estructura'
    when 'tecnico de estructuras' then 'Encargado de estructura'
    when 'encargado de almacén' then 'Encargado de almacén'
    when 'encargado de almacen' then 'Encargado de almacén'
    when 'supervisor' then 'Supervisor'
    when 'jefe de cuadrilla' then 'Supervisor'
    when 'administrativo' then 'Administrativo'
    when 'administración' then 'Administrativo'
    when 'administracion' then 'Administrativo'
    when 'contabilidad' then 'Contabilidad'
    when 'recursos humanos' then 'Recursos Humanos'
    when 'marketing digital' then 'Marketing Digital'
    when 'chofer/técnico de sonido' then 'Chofer/Técnico de sonido'
    when 'chofer/tecnico de sonido' then 'Chofer/Técnico de sonido'
    when 'chofer/técnico de audiovisuales' then 'Chofer/Técnico de audiovisuales'
    when 'chofer/tecnico de audiovisuales' then 'Chofer/Técnico de audiovisuales'
    when 'chofer/técnico de iluminación' then 'Chofer/Técnico de iluminación'
    when 'chofer/tecnico de iluminación' then 'Chofer/Técnico de iluminación'
    when 'chofer/tecnico de iluminacion' then 'Chofer/Técnico de iluminación'
    when 'chofer/encargado de estructura' then 'Chofer/Encargado de estructura'
    when 'chofer/encargado de almacén' then 'Chofer/Encargado de almacén'
    when 'chofer/encargado de almacen' then 'Chofer/Encargado de almacén'
    else null
  end;
$$;

revoke all on function account_private.normalizar_cargo(text) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
