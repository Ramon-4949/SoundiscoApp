import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const source = readFileSync(new URL('../notification_reminders.sql', import.meta.url), 'utf8');
assert.equal(/--|\/\*/.test(source), false);
const sql = source.replace('tick timestamptz := clock_timestamp()', "tick timestamptz := current_setting('test.clock')::timestamptz");
const h = '00000000-0000-0000-0000-000000000001';
const u = '00000000-0000-0000-0000-000000000002';
const run = async time => {
  await db.query("select set_config('test.clock',$1,false)", [time]);
  await db.exec('select generate_notification_reminders()');
};
const count = async () => Number((await db.query('select count(*) n from notificaciones_app')).rows[0].n);
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema notification_private; create schema android_push_private;
    create table asignaciones(id uuid primary key);
    insert into asignaciones values('${h}');
    create table hitos_itinerario(id uuid primary key,asignacion_id uuid,descripcion text,fecha_programada timestamptz);
    create table hitos_colaboradores(hito_id uuid references hitos_itinerario(id) on delete cascade,usuario_id uuid,
      confirmado_at timestamptz,primary key(hito_id,usuario_id));
    create table notificaciones_app(id uuid primary key,perfil_id uuid,titulo text,mensaje text,leida boolean,
      fecha_creacion timestamptz,tipo text,destino_tipo text,destino_id uuid,evento_key text,unique(perfil_id,evento_key));
    create table notification_private.outbox(notification_id uuid references notificaciones_app(id),sent_at timestamptz);
    create table android_push_private.outbox(notification_id uuid references notificaciones_app(id),sent_at timestamptz);
    insert into hitos_itinerario values('${h}','${h}','Montaje','2030-10-08 12:00:00+00');
    insert into hitos_colaboradores values('${h}','${u}',null);
  `);
  await db.exec(sql);
  await db.exec(sql);
  for (const [time,expected] of [['11:40:00',0],['11:45:00',0],['11:50:00',0],['11:55:00',0],['12:00:00',0],['12:14:59',0],['12:15:00',1],['12:29:59',1],['12:30:00',2],['12:59:59',2],['13:00:00',3],['14:00:00',3]]) {
    await run(`2030-10-08 ${time}+00`);
    await run(`2030-10-08 ${time}+00`);
    assert.equal(await count(), expected, time);
  }
  await db.exec(sql);
  await run('2031-10-08 12:00:00+00');
  assert.equal(await count(), 3);
  const rows = (await db.query('select payload from notificaciones_app order by fecha_creacion')).rows;
  assert.deepEqual(rows.map(r=>r.payload.reminder_phase), ['after:15','after:30','after:60']);
  assert.ok(rows.every(r=>r.payload.is_alarm===false));
  await db.exec("update hitos_itinerario set fecha_programada='2032-10-08 12:00:00+00'");
  await run('2032-10-08 12:15:00+00');
  assert.equal(await count(), 4);
  await db.exec('update hitos_colaboradores set confirmado_at=now()');
  await run('2032-10-08 13:00:00+00');
  assert.equal(await count(), 4);
  await db.exec('update hitos_colaboradores set confirmado_at=null');
  await run('2032-10-08 13:00:00+00');
  await run('2032-10-08 13:00:01+00');
  assert.equal(await count(), 5);
  await db.exec(`
    insert into notificaciones_app(id,tipo,destino_tipo,payload) values
      ('${u}','recordatorio','asignacion','{"reminder_phase":"overdue:500"}');
    insert into notification_private.outbox values('${u}',null),('${u}',now());
    insert into android_push_private.outbox values('${u}',null),('${u}',now());
    insert into notification_private.outbox select id,null from notificaciones_app where id<>'${u}';
    update notification_private.milestone_reminders set schedule_version=1,due_at=now()-interval '2 hours';
  `);
  await db.exec(sql);
  assert.equal((await db.query('select * from android_push_private.outbox where sent_at is null')).rows.length, 0);
  assert.equal((await db.query('select * from android_push_private.outbox')).rows.length, 1);
  assert.equal((await db.query('select * from notification_private.outbox where sent_at is null')).rows.length, 5);
  assert.equal((await db.query("select next_reminder_at='infinity'::timestamptz as stopped from notification_private.milestone_reminders")).rows[0].stopped, true);
  await db.exec('delete from hitos_colaboradores');
  assert.equal((await db.query('select * from notification_private.milestone_reminders')).rows.length, 0);
  assert.equal((await db.query("select has_function_privilege('authenticated','generate_notification_reminders()','execute') allowed")).rows[0].allowed, false);
  await db.exec(`
    update notificaciones_app set titulo='Alarma de Hito',payload=jsonb_set(payload,'{is_alarm}','true');
    insert into notificaciones_app(id,tipo,destino_tipo,titulo,payload)
    values(gen_random_uuid(),'asignacion_creada','asignacion','Nueva asignación','{}');
  `);
  await db.exec(sql);
  assert.equal((await db.query("select * from notificaciones_app where tipo='recordatorio' and (titulo='Alarma de Hito' or payload->'is_alarm'='true'::jsonb)")).rows.length, 0);
  assert.equal((await db.query("select * from notificaciones_app where tipo='asignacion_creada' and titulo='Nueva asignación' and payload='{}'::jsonb")).rows.length, 1);
  console.log('PASS: +15/+30/+60 only, deduplication, finite schedule, confirmation, undo, rescheduling, migration, both queues and permissions');
} finally { await db.close(); }
