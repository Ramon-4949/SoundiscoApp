import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const migration = readFileSync(new URL('../reminder_delivery_guard.sql', import.meta.url), 'utf8');
const insert = async (n, assignment = 1, milestone = 2, recipient = 3) => db.query(`
  insert into notificaciones_app values($1,$2,'recordatorio','asignacion',$3,
    jsonb_build_object('hito_id',$4::text,'due_at','2026-10-08T12:00:00+00:00','is_alarm',true))`,
  [id(n), id(recipient), id(assignment), id(milestone)]);
const count = async () => Number((await db.query('select count(*) n from notificaciones_app')).rows[0].n);
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema notification_private;
    create table asignaciones(id uuid primary key);
    create table hitos_itinerario(id uuid primary key,asignacion_id uuid,fecha_programada timestamptz);
    create table hitos_colaboradores(hito_id uuid,usuario_id uuid,confirmado_at timestamptz,
      primary key(hito_id,usuario_id));
    create table notificaciones_app(id uuid primary key,perfil_id uuid,tipo text,destino_tipo text,
      destino_id uuid,payload jsonb);
    create table notification_private.outbox(notification_id uuid references notificaciones_app(id) on delete cascade);
    create function public.claim_notification_pushes_v3()
    returns table(job_id uuid,lease uuid,notification_id uuid,recipient uuid,token text,
      environment text,title text,body text,badge integer)
    language sql as $$ select id,id,id,perfil_id,'token','production','title','body',1 from public.notificaciones_app $$;
    insert into asignaciones values('${id(1)}');
    insert into hitos_itinerario values('${id(2)}','${id(1)}','2026-10-08 12:00:00+00');
    insert into hitos_colaboradores values('${id(2)}','${id(3)}',null);
  `);
  await insert(10);
  await insert(11, 99);
  await insert(12, 1, 2, 99);
  await db.exec('insert into notification_private.outbox select id from notificaciones_app');
  await db.exec(migration);
  await db.exec(migration);
  assert.equal(await count(), 1);
  assert.equal((await db.query('select * from notification_private.outbox')).rows.length, 1);
  assert.equal((await db.query('select * from claim_notification_pushes_v4()')).rows.length, 1);
  await insert(13, 99);
  await insert(14, 1, 99);
  assert.equal(await count(), 1);
  await db.exec('update hitos_colaboradores set confirmado_at=now()');
  assert.equal(await count(), 0);
  assert.equal((await db.query('select * from notification_private.outbox')).rows.length, 0);
  await insert(15);
  assert.equal(await count(), 0);
  await db.exec('update hitos_colaboradores set confirmado_at=null');
  await insert(16);
  assert.equal(await count(), 1);
  await db.exec('delete from hitos_colaboradores');
  assert.equal(await count(), 0);
  await db.exec(`insert into hitos_colaboradores values('${id(2)}','${id(3)}',null)`);
  await insert(17);
  await db.exec("update hitos_itinerario set fecha_programada=fecha_programada+interval '1 hour'");
  assert.equal(await count(), 0);
  await db.exec("update hitos_itinerario set fecha_programada=fecha_programada-interval '1 hour'");
  await insert(18);
  await db.exec('delete from asignaciones');
  assert.equal(await count(), 0);
  await insert(19);
  assert.equal(await count(), 0);
  await db.exec(`insert into notificaciones_app values('${id(20)}','${id(3)}','asignacion_eliminada','asignacion','${id(1)}','{}')`);
  assert.equal((await db.query('select * from claim_notification_pushes_v4()')).rows.length, 1);
  assert.equal((await db.query("select has_function_privilege('authenticated','notification_private.reminder_is_actionable(uuid,uuid,jsonb)','execute') allowed")).rows[0].allowed, false);
  console.log('PASS: stale cleanup, queue cascade, deleted assignment, removed membership, confirmation, undo, rescheduling and unrelated notifications');
} finally { await db.close(); }
