import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const migration = readFileSync(new URL('../cancel_deleted_assignment_reminders.sql', import.meta.url), 'utf8');
const id = value => `00000000-0000-0000-0000-${String(value).padStart(12, '0')}`;

try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema notification_private;
    create table public.asignaciones(id uuid primary key);
    create table public.notificaciones_app(
      id uuid primary key,
      destino_tipo text,
      destino_id uuid,
      tipo text
    );
    create table notification_private.outbox(
      id uuid primary key,
      notification_id uuid not null references public.notificaciones_app(id) on delete cascade
    );
    insert into public.asignaciones values('${id(1)}');
    insert into public.notificaciones_app values
      ('${id(10)}','asignacion','${id(1)}','recordatorio'),
      ('${id(11)}','asignacion','${id(1)}','asignacion_actualizada'),
      ('${id(12)}','asignacion','${id(2)}','recordatorio');
    insert into notification_private.outbox values
      ('${id(20)}','${id(10)}'),
      ('${id(21)}','${id(11)}'),
      ('${id(22)}','${id(12)}');
  `);
  await db.exec(migration);
  await db.exec(migration);
  assert.deepEqual(
    (await db.query('select id from public.notificaciones_app order by id')).rows.map(row => row.id),
    [id(10), id(11)]
  );
  assert.deepEqual(
    (await db.query('select notification_id from notification_private.outbox order by notification_id')).rows.map(row => row.notification_id),
    [id(10), id(11)]
  );
  await db.query('delete from public.asignaciones where id=$1', [id(1)]);
  assert.deepEqual(
    (await db.query('select id from public.notificaciones_app order by id')).rows.map(row => row.id),
    [id(11)]
  );
  assert.deepEqual(
    (await db.query('select notification_id from notification_private.outbox')).rows.map(row => row.notification_id),
    [id(11)]
  );
  assert.equal(
    (await db.query("select has_function_privilege('authenticated','notification_private.cancel_deleted_assignment_reminders()','execute') allowed")).rows[0].allowed,
    false
  );
  console.log('PASS: deleted assignments cancel reminder notifications and pending push jobs');
} finally {
  await db.close();
}
