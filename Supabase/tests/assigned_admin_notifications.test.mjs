import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite }=await import(process.env.PGLITE_PATH);
const db=new PGlite();
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const migration=readFileSync(new URL('../assigned_admin_notifications.sql',import.meta.url),'utf8');
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema notification_private; create schema android_push_private;
    create function auth.uid() returns uuid language sql as $$select '${id(1)}'::uuid$$;
    create table perfiles(id uuid primary key,rol text);
    insert into perfiles values('${id(1)}','admin'),('${id(2)}','admin'),('${id(3)}','empleado'),('${id(4)}','admin');
    create table asignaciones(id uuid primary key,titulo text,tipo_flujo text,estado text,nivel_prioridad text);
    insert into asignaciones values('${id(10)}','Evento','campo','pendiente','baja');
    create table asignacion_equipo(asignacion_id uuid,perfil_id uuid);
    insert into asignacion_equipo select '${id(10)}',id from perfiles where id<>'${id(4)}';
    create table notification_private.assignment_events(transaction_id bigint,assignment_id uuid,old_team uuid[],old_title text,old_priority text,content_changed bool);
    create table notificaciones_app(id uuid primary key,perfil_id uuid,titulo text,mensaje text,leida bool,
      fecha_creacion timestamptz,tipo text,destino_tipo text,destino_id uuid,estado text,evento_key text,unique(perfil_id,evento_key));
    create table notification_private.devices(installation uuid primary key,perfil_id uuid);
    create table android_push_private.devices(installation uuid primary key,perfil_id uuid);
    insert into notification_private.devices select id,id from perfiles;
    insert into android_push_private.devices select id,id from perfiles;
    create table notification_private.outbox(notification_id uuid references notificaciones_app(id),installation uuid,recipient uuid,sent_at timestamptz);
    create table android_push_private.outbox(notification_id uuid references notificaciones_app(id),installation uuid,recipient uuid,sent_at timestamptz,unique(notification_id,installation));
  `);
  for(const file of ['notifications_setup.sql','push-worker/android_push.sql']) {
    const source=readFileSync(new URL(`../${file}`,import.meta.url),'utf8');
    const name=file.includes('android')?'android_push_private':'notification_private';
    const start=source.indexOf(`create or replace function ${name}.enqueue_push()`);
    const end=source.indexOf('$$;',start)+3;
    await db.exec(source.slice(start,end));
    await db.exec(`create trigger enqueue_${name} after insert on notificaciones_app for each row execute function ${name}.enqueue_push()`);
  }
  await db.exec(migration); await db.exec(migration);
  await db.exec('create trigger flush after insert on notification_private.assignment_events for each row execute function notification_private.flush_assignment()');
  await db.exec(`insert into notification_private.assignment_events values(1,'${id(10)}','{}','Evento','baja',true)`);
  const recipients=(await db.query("select perfil_id from notificaciones_app where tipo='asignacion_nueva' order by perfil_id")).rows.map(r=>r.perfil_id);
  assert.deepEqual(recipients,[id(1),id(2),id(3)]);
  for(const schema of ['notification_private','android_push_private']) {
    assert.equal((await db.query(`select * from ${schema}.outbox`)).rows.length,3);
  }
  await db.exec(`select notification_private.emit('${id(1)}','comunicado_nuevo','Own','Own','comunicado','${id(10)}',null,'own')`);
  assert.equal((await db.query("select * from notificaciones_app where evento_key='own'")).rows.length,0);
  await db.exec(`
    create table hitos_itinerario(id uuid primary key,asignacion_id uuid,descripcion text,fecha_programada timestamptz);
    create table hitos_colaboradores(hito_id uuid,usuario_id uuid,confirmado_at timestamptz,primary key(hito_id,usuario_id));
    insert into hitos_itinerario values('${id(20)}','${id(10)}','Inicio','2030-10-12T14:00:00Z');
    insert into hitos_colaboradores select '${id(20)}',perfil_id,null from asignacion_equipo;
  `);
  const reminders=readFileSync(new URL('../notification_reminders.sql',import.meta.url),'utf8')
    .replace('tick timestamptz := clock_timestamp()',"tick timestamptz := '2030-10-12T14:15:00Z'");
  await db.exec(reminders);
  await db.exec('select generate_notification_reminders(); select generate_notification_reminders();');
  assert.deepEqual((await db.query("select perfil_id from notificaciones_app where tipo='recordatorio' order by perfil_id")).rows.map(r=>r.perfil_id),recipients);
  assert.equal((await db.query("select * from notificaciones_app where tipo='recordatorio' and payload->'is_alarm'='true'::jsonb")).rows.length,0);
  for(const schema of ['notification_private','android_push_private']) {
    assert.equal((await db.query(`select * from ${schema}.outbox`)).rows.length,6);
  }
  console.log('PASS: assigned admins, self assignment, unrelated admin excluded, both push queues, personal normal reminders and deduplication');
} finally { await db.close(); }
