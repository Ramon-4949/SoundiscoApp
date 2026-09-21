import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const run = (sql, args = []) => db.query(sql, args);
const apply = file => db.exec(readFileSync(new URL(`../${file}`, import.meta.url), 'utf8'));
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;

try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema account_private;
    create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);
    create function auth.uid() returns uuid language sql as $$ select '${id(1)}'::uuid $$;
    create table perfiles(id uuid primary key,nombre_completo text,rol text,telefono text,cargo text);
    create table account_private.access(user_id uuid,estado text,created_at timestamptz default now());
    create function public.es_admin() returns boolean language sql as $$ select true $$;
    create table asignaciones(id uuid primary key,tipo_flujo text,titulo text,ubicacion text,instrucciones text);
    create table hitos_itinerario(id uuid primary key,descripcion text);
    create table comunicados(id uuid primary key,asunto text,mensaje text);
    create table notas_asignacion(id uuid primary key,contenido text);
    insert into auth.users values('${id(1)}','old@example.test',
      '{"nombre_usuario":"old.user","nombre_completo":"Usuario Anterior","telefono":"809-555-0101","cargo":"Técnico de pantallas"}');
    insert into perfiles values('${id(1)}','Usuario Anterior','tecnico','809-555-0101',null);
    insert into account_private.access values('${id(1)}','aprobada',now());
  `);
  await apply('profile_roles_and_jobs.sql');
  await apply('input_validation_setup.sql');
  await apply('input_validation_setup.sql');

  assert.deepEqual((await run('select rol,cargo from perfiles where id=$1',[id(1)])).rows[0],
    {rol:'empleado',cargo:'Técnico audiovisuales'});

  await run('insert into auth.users values($1,$2,$3)', [id(2),'new@example.test', JSON.stringify({
    nombre_usuario:'maria.01',nombre_completo:'María Pérez',telefono:'+1 (809) 555-0192',cargo:'Recursos Humanos'
  })]);
  assert.deepEqual((await run('select rol,cargo from perfiles where id=$1',[id(2)])).rows[0],
    {rol:'empleado',cargo:'Recursos Humanos'});

  await assert.rejects(run('insert into auth.users values($1,$2,$3)', [id(3),'bad@example.test', JSON.stringify({
    nombre_usuario:'x!',nombre_completo:'Usuario 3',telefono:'123',cargo:'Cargo inventado'
  })]), /nombre de usuario no es valido/);

  await assert.rejects(run('insert into asignaciones values($1,$2,$3,$4,$5)',[id(10),'campo','A','X','ok']),/asignaciones_texto_valido/);
  await assert.rejects(run('insert into hitos_itinerario values($1,$2)',[id(11),'X']),/hitos_texto_valido/);
  await assert.rejects(run('insert into comunicados values($1,$2,$3)',[id(12),'Hi','Corto']),/comunicados_texto_valido/);
  await assert.rejects(run('insert into notas_asignacion values($1,$2)',[id(13),'No']),/notas_texto_valido/);
  await run('insert into asignaciones values($1,$2,$3,$4,$5)',[id(14),'campo','Montaje principal','Auditorio','Revisar cableado']);
  await run('insert into comunicados values($1,$2,$3)',[id(15),'Cambio de horario','El horario fue actualizado correctamente.']);
  console.log('PASS registration metadata, canonical jobs, employee roles and database text constraints');
} finally {
  await db.close();
}
