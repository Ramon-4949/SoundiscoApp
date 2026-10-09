import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const migration = readFileSync(new URL('../notification_reminders.sql', import.meta.url), 'utf8');
assert.equal(/--|\/\*/.test(migration), false);
const sql = migration.replace('tick timestamptz := clock_timestamp()', "tick timestamptz := current_setting('test.clock')::timestamptz");
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
    create schema notification_private;
    create table hitos_itinerario(id uuid primary key,asignacion_id uuid,descripcion text,fecha_programada timestamptz);
    create table hitos_colaboradores(hito_id uuid references hitos_itinerario(id) on delete cascade,usuario_id uuid,
      confirmado_at timestamptz,primary key(hito_id,usuario_id));
    create table notificaciones_app(id uuid primary key,perfil_id uuid,titulo text,mensaje text,leida boolean,
      fecha_creacion timestamptz,tipo text,destino_tipo text,destino_id uuid,evento_key text,unique(perfil_id,evento_key));
    insert into hitos_itinerario values('${h}','${h}','Montaje','2026-10-08 12:00:00+00');
    insert into hitos_colaboradores values('${h}','${u}',null);
  `);
  await db.exec(sql);
  await db.exec(sql);
  await run('2026-10-08 11:39:59+00');
  assert.equal(await count(), 0);
  for (const [minute,expected] of [[40,1],[45,2],[50,3],[55,4]]) {
    await run(`2026-10-08 11:${minute}:00+00`);
    await run(`2026-10-08 11:${minute}:01+00`);
    assert.equal(await count(), expected);
  }
  const alarms = (await db.query("select payload->'is_alarm' alarm from notificaciones_app order by fecha_creacion")).rows;
  assert.deepEqual(alarms.map(x=>x.alarm), [false,false,false,true]);
  await db.exec(`
    create function public.claim_notification_pushes_v3()
    returns table(job_id uuid,lease uuid,notification_id uuid,recipient uuid,token text,
      environment text,title text,body text,badge integer)
    language sql as $$ select id,id,id,perfil_id,'test-token','production',titulo,mensaje,4
      from public.notificaciones_app $$;
  `);
  const alarmSQL = readFileSync(new URL('../ios_alarm_notifications.sql', import.meta.url), 'utf8');
  await db.exec(alarmSQL);
  await db.exec(alarmSQL);
  const pushes = (await db.query('select * from claim_notification_pushes_v4()')).rows;
  assert.equal(pushes.length, 4);
  assert.equal(pushes.filter(p=>p.is_alarm).length, 1);
  assert.ok(pushes.every(p=>p.badge===4));
  assert.equal((await db.query("select has_function_privilege('authenticated','claim_notification_pushes_v4()','execute') allowed")).rows[0].allowed, false);
  await run('2026-10-08 12:00:00+00');
  assert.equal(await count(), 5);
  await run('2026-10-08 12:09:59+00');
  assert.equal(await count(), 5);
  await run('2026-10-08 12:10:00+00');
  assert.equal(await count(), 6);
  await db.exec(sql);
  await run('2026-10-08 12:10:01+00');
  assert.equal(await count(), 6);
  await run('2027-10-08 12:20:00+00');
  assert.equal(await count(), 7);
  await run('2027-10-08 12:30:00+00');
  assert.equal(await count(), 8);
  await db.exec('update hitos_colaboradores set confirmado_at=now()');
  await run('2027-10-08 13:00:00+00');
  assert.equal(await count(), 8);
  await db.exec('update hitos_colaboradores set confirmado_at=null');
  await run('2027-10-08 13:00:00+00');
  assert.equal(await count(), 9);
  await db.exec("update hitos_itinerario set fecha_programada='2027-10-08 14:00:00+00'");
  await run('2027-10-08 13:39:59+00');
  assert.equal(await count(), 9);
  await run('2027-10-08 13:40:00+00');
  assert.equal(await count(), 10);
  await db.exec('delete from hitos_colaboradores');
  assert.equal((await db.query('select * from notification_private.milestone_reminders')).rows.length, 0);
  assert.equal((await db.query("select has_function_privilege('authenticated','generate_notification_reminders()','execute') allowed")).rows[0].allowed, false);
  console.log('PASS: preventive thresholds, alarms, duplicate prevention, indefinite overdue, confirmation, undo, rescheduling, deletion and permissions');
} finally { await db.close(); }
