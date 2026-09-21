import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
await db.exec(`
create role anon; create role authenticated;
create schema auth; create schema account_private; create schema sla_private;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function public.es_admin() returns boolean language sql as $$ select auth.uid()='${id(1)}'::uuid $$;
create table perfiles(id uuid primary key,nombre_completo text,cargo text,rol text);
create table account_private.access(user_id uuid,estado text);
create table asignaciones(id uuid primary key,tipo_flujo text,estado text,fecha_creacion timestamptz,fecha_limite timestamptz);
create table asignacion_equipo(asignacion_id uuid,perfil_id uuid);
create table hitos_itinerario(id uuid primary key,asignacion_id uuid,fecha_programada timestamptz);
create table sla_private.windows(hito_id uuid,hora_programada timestamptz);
create table sla_private.participants(hito_id uuid,usuario_id uuid);
create table confirmaciones_hitos(id uuid,hito_id uuid,asignacion_id uuid,usuario_id uuid,created_at timestamptz,hora_programada timestamptz,evaluacion text);
create table notas_asignacion(id uuid,asignacion_id uuid,usuario_id uuid,contenido text,created_at timestamptz);
insert into perfiles values('${id(1)}','Admin','Admin','admin'),('${id(2)}','Ana','Sonido','tecnico'),
 ('${id(3)}','Sin datos',null,'tecnico'),('${id(4)}','Pendiente','Luces','tecnico');
insert into account_private.access values('${id(1)}','aprobada'),('${id(2)}','aprobada'),('${id(3)}','aprobada'),('${id(4)}','pendiente');
insert into asignaciones values('${id(10)}','campo','completada','2020-01-01T10:00:00Z','2020-01-10T11:00:00Z'),
 ('${id(11)}','administrativa','pendiente','2020-01-15T10:00:00Z','2020-02-01T11:00:00Z');
insert into asignacion_equipo values('${id(10)}','${id(2)}'),('${id(11)}','${id(2)}');
insert into hitos_itinerario values('${id(20)}','${id(10)}','2020-01-10T10:00:00Z'),('${id(21)}','${id(10)}','2020-01-10T11:00:00Z'),
 ('${id(22)}','${id(10)}','2020-01-10T11:00:00Z'),('${id(23)}','${id(10)}','2020-01-10T11:00:00Z');
insert into sla_private.windows select id,fecha_programada from hitos_itinerario;
insert into sla_private.participants select id,'${id(2)}' from hitos_itinerario;
insert into confirmaciones_hitos values
 ('${id(30)}','${id(20)}','${id(10)}','${id(2)}','2020-01-10T09:59:00Z','2020-01-10T10:00:00Z','temprano'),
 ('${id(31)}','${id(21)}','${id(10)}','${id(2)}','2020-01-10T11:15:00Z','2020-01-10T11:00:00Z','a_tiempo'),
 ('${id(32)}','${id(22)}','${id(10)}','${id(2)}','2020-01-10T11:20:00Z','2020-01-10T11:00:00Z','tardio');
insert into notas_asignacion values('${id(40)}','${id(10)}','${id(2)}','Nota','2020-01-07T20:00:00Z'),
 ('${id(41)}','${id(10)}','${id(2)}','Nota 2','2020-01-08T05:00:00Z'),
 ('${id(42)}','${id(10)}','${id(2)}','Otro mes','2020-02-01T05:00:00Z');
select set_config('test.uid','${id(1)}',false);
`);
const migration = readFileSync(new URL('../admin_performance_setup.sql',import.meta.url),'utf8');
await db.exec(migration); await db.exec(migration);
const fetch = async month => (await db.query('select * from admin_employee_performance($1)',[month])).rows.map(r=>r.admin_employee_performance);
let rows = await fetch('2020-01-01');
assert.equal(rows.length,2);
const ana = rows.find(x=>x.id===id(2));
assert.deepEqual([ana.temprano,ana.a_tiempo,ana.tardio,ana.sin_confirmar],[1,1,1,1]);
assert.equal(ana.retraso_medio_minutos,5);
assert.deepEqual(ana.notas_semanales.map(w=>w.cantidad),[1,1,0,0,0]);
assert.deepEqual([ana.asignaciones,ana.completadas,ana.activas,ana.vencidas],[2,1,0,1]);
assert.equal(rows.find(x=>x.id===id(3)).retraso_medio_minutos,null);
assert.equal(rows.find(x=>x.id===id(3)).asignaciones,0);
assert.equal((await fetch('2019-12-01')).find(x=>x.id===id(2)).temprano,0);
assert.equal((await db.query('select * from admin_employee_performance($1,0,$2)',['2020-01-01',id(2)])).rows.length,1);
assert.equal((await db.query('select * from admin_employee_performance($1,100)',['2020-01-01'])).rows.length,0);
await db.exec(`grant usage on schema auth to authenticated; set role authenticated; select set_config('test.uid','${id(2)}',false);`);
await assert.rejects(fetch('2020-01-01'),/Solo administradores/);
await db.exec(`select set_config('test.uid','',false);`);
await assert.rejects(fetch('2020-01-01'),/Solo administradores/);
console.log('PASS admin-only authorization, missing confirmations, early/on-time compliance, notes by week, zero data, monthly overlap, pagination and month isolation');
await db.close();
