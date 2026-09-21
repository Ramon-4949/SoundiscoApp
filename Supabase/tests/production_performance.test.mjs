import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const assignmentOne = 'c4ca4238-a0b9-2382-0dcc-509a6f75849b';
await db.exec(`
create role anon; create role authenticated;
create schema auth; create schema notification_private;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function public.es_admin() returns boolean language sql as $$ select auth.uid()='00000000-0000-0000-0000-000000000001'::uuid $$;
create table perfiles(id uuid primary key,nombre_completo text,rol text);
create table asignaciones(id uuid primary key,tipo_flujo text,titulo text,ubicacion text,nivel_prioridad text,
 instrucciones text,estado text,fecha_creacion timestamptz,fecha_limite timestamptz);
create table asignacion_equipo(asignacion_id uuid,perfil_id uuid);
create table hitos_itinerario(id uuid primary key,asignacion_id uuid,orden int,descripcion text,hora_estimada time,
 fecha_programada timestamptz,estado_hito text,notas_incidencias text);
create table confirmaciones_hitos(asignacion_id uuid,usuario_id uuid,created_at timestamptz,hora_programada timestamptz);
create table notas_asignacion(asignacion_id uuid,usuario_id uuid,created_at timestamptz);
create table notificaciones_app(perfil_id uuid,fecha_creacion timestamptz);
create table notification_private.devices(perfil_id uuid);
create table notification_private.outbox(id int primary key,installation uuid,next_attempt timestamptz,attempts int,sent_at timestamptz,leased_until timestamptz);
insert into perfiles values('00000000-0000-0000-0000-000000000002','Ana Sonido','empleado');
insert into asignaciones select md5(n::text)::uuid,'campo','Montaje '||n,'Santo Domingo','media',null,
 'pendiente',now(),now()+interval '1 day' from generate_series(1,1005) n;
insert into asignacion_equipo values(md5('1')::uuid,'00000000-0000-0000-0000-000000000002');
insert into hitos_itinerario values(md5('hito')::uuid,md5('1')::uuid,1,'Llegada','06:00',now()+interval '1 hour','en_curso',null);
insert into notification_private.outbox(id,attempts,sent_at,leased_until) values
 (1,1,now()-interval '31 days',null), (2,1,now()-interval '29 days',null),
 (3,8,null,null), (4,0,null,null), (5,1,now()-interval '31 days',now()+interval '1 hour');
select set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
`);
for (const name of ['production_performance.sql','admin_dashboard_queries.sql']) {
  const sql = readFileSync(new URL(`../${name}`,import.meta.url),'utf8');
  await db.exec(sql); await db.exec(sql);
}
const value = async sql => Object.values((await db.query(sql)).rows[0])[0];
const summary = await value('select admin_dashboard_summary()');
assert.equal(summary.total,1005); assert.equal(summary.creadas_ultimos_7_dias.length,7);
const first = await value("select admin_assignments_page(0,999,'todas')");
assert.equal(first.items.length,100); assert.equal(first.has_more,true); assert.equal(first.next_offset,100);
const searched = await value("select admin_assignments_page(0,50,'todas','ana sonido')");
const enriched = searched.items.find(x=>x.id===assignmentOne);
assert.equal(enriched.hitos_itinerario.length,1); assert.equal(enriched.asignacion_equipo[0].perfiles.nombre_completo,'Ana Sonido');
const second = await value("select admin_assignments_page(100,100,'todas')");
assert.equal(new Set([...first.items,...second.items].map(x=>x.id)).size,200);
assert.equal((await value("select admin_assignments_page(1000,100,'todas')")).has_more,false);
assert.equal((await value("select admin_assignments_page(0,50,'completadas')")).items.length,0);
assert.equal(searched.items.length,1);
await db.exec("update asignaciones set fecha_limite=now()-interval '1 day' where id=md5('1')::uuid");
assert.equal((await value("select admin_assignments_page(0,50,'vencidas')")).items.length,1);
assert.equal((await value('select admin_dashboard_summary()')).vencidas,1);
assert.equal(await value('select notification_private.purge_sent_outbox()'),1);
assert.equal(await value('select count(*)::int from notification_private.outbox'),4);
await db.exec("grant usage on schema auth to authenticated; set role authenticated; select set_config('test.uid','00000000-0000-0000-0000-000000000002',false)");
await assert.rejects(value('select admin_dashboard_summary()'),/Solo administradores/);
await assert.rejects(value('select admin_assignments_page()'),/Solo administradores/);
await assert.rejects(value('select notification_private.purge_sent_outbox()'),/permission denied/);
await db.close();
console.log('PASS idempotence, 1005-row summary, bounded deterministic pages, expiry, authorization and safe retention');
