import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const source = readFileSync(new URL('../milestone_confirmation_timing_fix.sql',import.meta.url),'utf8');
assert.ok(source.includes('checked timestamptz:=statement_timestamp()'));
const sql = source.replace('checked timestamptz:=statement_timestamp()',"checked timestamptz:=current_setting('test.clock')::timestamptz");
const user = n => db.query("select set_config('test.uid',$1,false)",[id(n)]);
const at = t => db.query("select set_config('test.clock',$1,false)",[t]);
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema milestone_private; create schema notification_private; create schema sla_private;
    create function auth.uid() returns uuid language sql as $$select current_setting('test.uid',true)::uuid$$;
    create table perfiles(id uuid primary key,nombre_completo text,rol text,approved boolean);
    create function account_is_approved() returns boolean language sql as $$select approved from public.perfiles where id=auth.uid()$$;
    create table asignaciones(id uuid primary key,estado text);
    create table hitos_itinerario(id uuid primary key,asignacion_id uuid,orden integer,descripcion text,fecha_programada timestamptz);
    create table hitos_colaboradores(hito_id uuid,usuario_id uuid,confirmado_at timestamptz,hora_programada timestamptz,estado text,primary key(hito_id,usuario_id));
    create table confirmaciones_hitos(id uuid default gen_random_uuid(),asignacion_id uuid,hito_id uuid,usuario_id uuid,created_at timestamptz,hora_programada timestamptz,evaluacion text,unique(hito_id,usuario_id));
    create table emitted(recipient uuid,kind text);
    create function notification_private.emit(uuid,text,text,text,text,uuid,text,text) returns void language sql as $$insert into public.emitted values($1,$2)$$;
    create function sla_private.advance(uuid) returns void language sql as $$select null::void$$;
    insert into perfiles values('${id(1)}','Admin','admin',true),('${id(2)}','Employee','empleado',true),('${id(3)}','Other admin','admin',true),('${id(4)}','Unapproved','empleado',false);
    create table asignacion_supervisores(asignacion_id uuid,usuario_id uuid);
    insert into asignaciones values('${id(10)}','pendiente');
    insert into hitos_itinerario values('${id(20)}','${id(10)}',1,'Inicio','2030-10-12T10:00:00-04:00');
    insert into hitos_colaboradores values('${id(20)}','${id(1)}',null,null,'sin_confirmar'),('${id(20)}','${id(2)}',null,null,'sin_confirmar'),('${id(20)}','${id(4)}',null,null,'sin_confirmar');
    insert into hitos_colaboradores values('${id(99)}','${id(2)}','2030-10-12T14:05:00Z','2030-10-12T14:00:00Z','tardio');
    insert into confirmaciones_hitos(asignacion_id,hito_id,usuario_id,created_at,hora_programada,evaluacion) values('${id(10)}','${id(99)}','${id(2)}','2030-10-12T14:05:00Z','2030-10-12T14:00:00Z','tardio');
  `);
  await db.exec(sql);
  await db.exec(sql);
  for (const timezone of ['UTC','America/Santo_Domingo','Asia/Tokyo']) {
    await db.query("select set_config('TimeZone',$1,false)",[timezone]);
    for (const [time,expected] of [['13:59:59','temprano'],['14:00:00','a_tiempo'],['14:14:59','a_tiempo'],['14:15:00','a_tiempo'],['14:15:00.001','tardio']]) {
      const result=await db.query("select milestone_private.confirmation_evaluation($1,'2030-10-12T10:00:00-04:00') as state",[`2030-10-12T${time}Z`]);
      assert.equal(result.rows[0].state,expected);
    }
  }
  assert.equal((await db.query('select estado from hitos_colaboradores where hito_id=$1',[id(99)])).rows[0].estado,'a_tiempo');
  assert.equal((await db.query('select evaluacion from confirmaciones_hitos where hito_id=$1',[id(99)])).rows[0].evaluacion,'a_tiempo');
  await user(1); await at('2030-10-12T13:58:00Z');
  await db.query('select check_in_milestone($1)',[id(20)]);
  await db.query('select check_in_milestone($1)',[id(20)]);
  assert.equal((await db.query('select count(*)::int n from confirmaciones_hitos where usuario_id=$1',[id(1)])).rows[0].n,1);
  assert.equal((await db.query('select estado from hitos_colaboradores where hito_id=$1 and usuario_id=$2',[id(20),id(1)])).rows[0].estado,'temprano');
  await user(2); await at('2030-10-12T14:15:00Z');
  await db.query('select check_in_milestone($1)',[id(20)]);
  assert.equal((await db.query('select estado from hitos_colaboradores where hito_id=$1 and usuario_id=$2',[id(20),id(2)])).rows[0].estado,'a_tiempo');
  await user(3);
  await assert.rejects(db.query('select check_in_milestone($1)',[id(20)]),/No estás asignado/);
  await user(4);
  await assert.rejects(db.query('select check_in_milestone($1)',[id(20)]),/Acceso no aprobado/);
  assert.equal((await db.query("select has_function_privilege('anon','check_in_milestone(uuid)','execute') allowed")).rows[0].allowed,false);
  console.log('PASS: assigned admin and employee, unassigned admin rejected, approval, idempotence, timezone equivalence, exact grace boundaries and historical repair');
} finally { await db.close(); }
