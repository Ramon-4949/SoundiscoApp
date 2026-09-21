import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`
create role anon; create role authenticated; create role service_role;
create schema auth; create schema cron;
create function auth.uid() returns uuid language sql as $$ select current_setting('test.uid',true)::uuid $$;
create function public.account_is_approved() returns boolean language sql as $$ select true $$;
create function public.es_admin() returns boolean language sql as $$ select false $$;
create table public.perfiles(id uuid primary key);
create table public.asignaciones(id uuid primary key, estado text, fecha_limite timestamptz);
create table public.asignacion_equipo(asignacion_id uuid references public.asignaciones,perfil_id uuid references public.perfiles);
create table public.hitos_itinerario(id uuid primary key,asignacion_id uuid references public.asignaciones,orden int,
 fecha_programada timestamptz,completado boolean default false,estado_hito text default 'bloqueado',hora_real_completado timestamptz);
create function public.puede_ver_asignacion(a uuid) returns boolean language sql as $$
 select exists(select 1 from public.asignacion_equipo where asignacion_id=a and perfil_id=auth.uid()) $$;
create function public.assignment_deadline(a uuid) returns timestamptz language sql as $$
 select fecha_limite from public.asignaciones where id=a $$;
create function cron.schedule(text,text,text) returns bigint language sql as $$ select 1::bigint $$;
insert into public.perfiles values ('${id(1)}'),('${id(2)}'),('${id(3)}');
select set_config('test.uid','${id(1)}',false);
`);
const migration = readFileSync(new URL('../assignment_sla_setup.sql', import.meta.url),'utf8')
 .replace('create extension if not exists pg_cron with schema pg_catalog;', '-- pg_cron is hosted by Supabase; scheduler stubbed locally.');
await db.exec(migration);
await db.exec(migration);
async function seed(n, minutes, group = true) {
 await db.query(`insert into asignaciones values ($1,'pendiente',clock_timestamp() + interval '1 hour')`,[id(n)]);
 await db.query(`insert into hitos_itinerario(id,asignacion_id,orden,fecha_programada) values($1,$2,1,clock_timestamp()+$3*interval '1 minute')`,[id(n+100),id(n),minutes]);
 await db.query(`insert into asignacion_equipo values($1,$2)`,[id(n),id(1)]);
 if(group) await db.query(`insert into asignacion_equipo values($1,$2)`,[id(n),id(2)]);
}
async function check(n,user=1) {
 await db.query("select set_config('test.uid',$1,false)",[id(user)]);
 await db.query('select check_in_milestone($1)',[id(n+100)]);
}
async function completed(n) { return (await db.query('select completado from hitos_itinerario where id=$1',[id(n+100)])).rows[0].completado; }
await seed(10,-5);
await check(10); assert.equal(await completed(10),false);
await check(10); assert.equal((await db.query('select count(*)::int n from confirmaciones_hitos')).rows[0].n,1);
await check(10,2); assert.equal(await completed(10),true);
assert.equal((await db.query('select evaluacion from confirmaciones_hitos limit 1')).rows[0].evaluacion,'a_tiempo');
console.log('PASS group waits, all advance, retry is idempotent');
await seed(20,-16); await check(20); assert.equal(await completed(20),true);
await check(20,2);
assert.equal((await db.query('select count(*)::int n from confirmaciones_hitos where asignacion_id=$1 and evaluacion=$2',[id(20),'tardio'])).rows[0].n,2);
console.log('PASS late group advances with one and preserves late check-in after global closure');
await seed(30,-5,false); await check(30); assert.equal(await completed(30),true);
await seed(40,-16,false); await check(40); assert.equal(await completed(40),true);
await seed(50,5); await check(50); assert.equal(await completed(50),false);
assert.equal((await db.query('select evaluacion from confirmaciones_hitos where asignacion_id=$1',[id(50)])).rows[0].evaluacion,'temprano');
await db.query("update confirmaciones_hitos set evaluacion='tardio' where asignacion_id=$1",[id(50)]);
await db.exec(migration);
assert.equal((await db.query('select evaluacion from confirmaciones_hitos where asignacion_id=$1',[id(50)])).rows[0].evaluacion,'temprano');
await check(50,2); assert.equal(await completed(50),true);
await assert.rejects(check(20,3),/No estas asignado/);
console.log('PASS individual immediate, early check-in and historical repair are early, all early confirmations advance, unauthorized rejected');
await seed(60,-16); await db.exec('select process_assignment_sla()'); assert.equal(await completed(60),false);
await db.query("select set_config('test.uid',$1,false)",[id(1)]);
await assert.rejects(db.query("select add_assignment_note($1,$2,'  ')",[id(900),id(10)]),/caracteres/);
await db.query("select add_assignment_note($1,$2,'Incidencia independiente')",[id(900),id(10)]);
await db.query("select add_assignment_note($1,$2,'Incidencia independiente')",[id(900),id(10)]);
assert.equal((await db.query('select count(*)::int n from notas_asignacion')).rows[0].n,1);
await assert.rejects(db.query("update hitos_itinerario set fecha_programada=clock_timestamp() where id=$1",[id(110)]),/horario/);
console.log('PASS zero check-ins never invent completion, notes independent and retry safe, SLA schedule immutable');
await seed(70,-5); await check(70);
// Move only the frozen test window to simulate the passage of time for the cron.
await db.query("update sla_private.windows set hora_programada=clock_timestamp()-interval '16 minutes' where hito_id=$1",[id(170)]);
await db.exec('select process_assignment_sla()'); assert.equal(await completed(70),true);
assert.equal((await db.query('select evaluacion from confirmaciones_hitos where hito_id=$1',[id(170)])).rows[0].evaluacion,'a_tiempo');
await seed(80,-5);
await db.query("insert into hitos_itinerario(id,asignacion_id,orden,fecha_programada) values($1,$2,2,clock_timestamp()-interval '1 minute')",[id(181),id(80)]);
await assert.rejects(db.query('select check_in_milestone($1)',[id(181)]),/hito anterior/);
console.log('PASS cron advances without rewriting evaluation; future sequence blocked');
await db.exec(`grant usage on schema auth to authenticated;
 grant select on public.asignacion_equipo to authenticated; set role authenticated;`);
await db.query("select set_config('test.uid',$1,false)",[id(3)]);
assert.equal((await db.query('select count(*)::int n from confirmaciones_hitos')).rows[0].n,0);
assert.equal((await db.query('select count(*)::int n from notas_asignacion')).rows[0].n,0);
await assert.rejects(db.query("select add_assignment_note($1,$2,'Ajeno')",[id(901),id(10)]),/acceso/);
await db.query("select set_config('test.uid',$1,false)",[id(1)]);
assert.equal((await db.query('select count(*)::int n from confirmaciones_hitos where usuario_id=$1',[id(2)])).rows[0].n,0);
await assert.rejects(db.exec("update confirmaciones_hitos set evaluacion='a_tiempo'"),/permission denied/);
console.log('PASS RLS hides unrelated data and prevents fabricated evaluations');
await db.exec('reset role');
await db.close();
