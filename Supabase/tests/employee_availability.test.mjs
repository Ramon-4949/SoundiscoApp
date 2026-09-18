import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const { btree_gist } = await import(new URL('./contrib/btree_gist.js', `file://${process.env.PGLITE_PATH}`));
const db = new PGlite({ extensions: { btree_gist } });
const admin = '00000000-0000-0000-0000-000000000001';
const alice = '00000000-0000-0000-0000-000000000002';
const bob = '00000000-0000-0000-0000-000000000003';
let nextID = 1;
const id = () => `10000000-0000-0000-0000-${String(nextID++).padStart(12, '0')}`;
const at = hour => `2026-10-01T${String(hour).padStart(2, '0')}:00:00Z`;
const administrative = (start, end) => ({
  titulo: 'Auditoria', tipo_flujo: 'administrativa', nivel_prioridad: 'media',
  estado: 'pendiente', fecha_creacion: at(start)
});
const field = () => ({
  titulo: 'Montaje', tipo_flujo: 'campo', ubicacion: 'Evento', nivel_prioridad: 'alta',
  estado: 'pendiente', fecha_creacion: at(7)
});
const milestones = (start, end) => [start, end].map((hour, index) => ({
  id: id(), orden: index + 1, descripcion: `Hito ${index + 1}`,
  fecha_programada: at(hour), hora_estimada: `${String(hour).padStart(2, '0')}:00:00`
}));
const create = async (payload, employees, itinerary = []) =>
  (await db.query('select admin_create_assignment($1::jsonb,$2::uuid[],$3::jsonb) id',
    [JSON.stringify(payload), employees, JSON.stringify(itinerary)])).rows[0].id;
const update = async (assignment, payload, employees, itinerary = []) =>
  db.query('select admin_update_assignment($1,$2::jsonb,$3::uuid[],$4::jsonb)',
    [assignment, JSON.stringify(payload), employees, JSON.stringify(itinerary)]);
const availability = async (start, end, excluding = null) =>
  (await db.query('select * from admin_employee_availability($1,$2,$3)',
    [at(start), at(end), excluding])).rows;

try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth;
    create table auth.users(id uuid primary key,raw_user_meta_data jsonb);
    create function auth.uid() returns uuid language sql as
      $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function auth.role() returns text language sql as $$ select 'authenticated'::text $$;
    create table perfiles(id uuid primary key,nombre_completo text,rol text);
    create table asignaciones(id uuid primary key,titulo text,tipo_flujo text,ubicacion text not null,
      nivel_prioridad text,instrucciones text,estado text,fecha_creacion timestamptz,fecha_limite timestamptz);
    create table asignacion_equipo(asignacion_id uuid references asignaciones(id),perfil_id uuid references perfiles(id));
    create table hitos_itinerario(id uuid primary key,asignacion_id uuid references asignaciones(id),
      orden int,descripcion text,hora_estimada time,fecha_programada timestamptz,estado_hito text,
      completado bool,notas_incidencias text,hora_real_completado timestamptz);
    create table checklist_equipos(id uuid primary key,asignacion_id uuid references asignaciones(id));
    create table comunicados(id uuid primary key,asunto text,mensaje text,fecha_publicacion timestamptz,leido_por uuid[]);
    create table notificaciones_app(id uuid primary key,perfil_id uuid references perfiles(id),titulo text,mensaje text,
      leida bool,fecha_creacion timestamptz,asignacion_relacionada_id uuid references asignaciones(id));
    grant usage on schema public,auth to authenticated,anon;
    insert into perfiles values ('${admin}','Admin','admin'),('${alice}','Alice','tecnico'),('${bob}','Bob','tecnico');
    insert into auth.users values ('${alice}','{"cargo":"Sonido"}');
    select set_config('test.uid','${admin}',false);
  `);
  for (const file of ['admin_creation_setup.sql','assignment_checklist_setup.sql',
    'admin_crud_completion.sql','administrative_assignment_location_fix.sql',
    'notifications_setup.sql','notification_reminders.sql','employee_availability.sql']) {
    await db.exec(readFileSync(new URL(`../${file}`, import.meta.url), 'utf8'));
  }
  const first = await create(administrative(9, 12), [alice], milestones(9, 12));
  assert.equal((await availability(10, 11)).find(e => e.id === alice).disponible, false);
  assert.equal((await availability(10, 11)).find(e => e.id === bob).disponible, true);
  assert.equal((await availability(10, 11)).find(e => e.id === alice).cargo, 'Sonido');
  assert.equal((await availability(10, 11, first)).find(e => e.id === alice).disponible, true);
  await assert.rejects(create(administrative(10, 11), [alice], milestones(10, 11)), /no esta disponible/);
  assert.equal((await db.query('select count(*)::int n from asignaciones')).rows[0].n, 1);
  console.log('PASS administrative interval, self-exclusion, cargo and atomic conflict rollback');

  await assert.rejects(create(administrative(12, 13), [alice], milestones(12, 13)), /no esta disponible/);
  await create(administrative(13, 14), [alice], milestones(13, 14));
  const fieldMilestones = milestones(15, 18);
  const fieldID = await create(field(), [alice], fieldMilestones);
  assert.equal((await availability(16, 17)).find(e => e.id === alice).disponible, false);
  assert.equal((await db.query('select fecha_programada from hitos_itinerario where id=$1',
    [fieldMilestones[0].id])).rows[0].fecha_programada.toISOString(), '2026-10-01T15:00:00.000Z');
  await assert.rejects(create(administrative(16, 17), [alice], milestones(16, 17)), /no esta disponible/);
  const otherMilestones = milestones(16, 17);
  const other = await create(administrative(16, 17), [bob], otherMilestones);
  await assert.rejects(update(other, administrative(16, 17), [alice], otherMilestones), /no esta disponible/);
  await update(fieldID, field(), [alice], fieldMilestones);
  console.log('PASS boundaries, non-overlap, field timestamps, cross-type conflicts and editing');

  await db.query("update asignaciones set estado='completada' where id=$1", [first]);
  assert.equal((await availability(10, 11)).find(e => e.id === alice).disponible, true);
  await db.query('select admin_delete_assignment($1)', [fieldID]);
  assert.equal((await availability(16, 17)).find(e => e.id === alice).disponible, true);
  const slot = milestones(19, 19);
  await create(field(), [alice], slot);
  await assert.rejects(create(field(), [alice], milestones(19, 19)), /no esta disponible/);
  await assert.rejects(create(administrative(12, 10), [bob], milestones(11, 11)), /anteriores a la creacion/);
  await assert.rejects(create(field(), [bob], milestones(20, 18)), /orden del itinerario/);
  console.log('PASS completion/deletion release reservations, point events and invalid intervals');

  await db.exec(readFileSync(new URL('../employee_availability.sql', import.meta.url), 'utf8'));
  await db.exec(`select set_config('test.uid','${alice}',false); set role authenticated;`);
  await assert.rejects(availability(10, 11), /Solo administradores/);
  await assert.rejects(db.exec('select * from scheduling_private.bookings'), /permission denied/);
  await db.exec('reset role;');
  console.log('PASS migration reapplication and employee access restrictions');
} catch (error) {
  console.error(error.message, error.where ?? '');
  process.exitCode = 1;
} finally {
  await db.close();
}
