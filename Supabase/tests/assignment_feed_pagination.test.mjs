import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { appDatabase, login, maintenance } from './helpers/app_schema.mjs';

const db = await appDatabase(process.env.PGLITE_PATH);
const migration = readFileSync(new URL('../assignment_feed_pagination.sql', import.meta.url), 'utf8');
const ownership = readFileSync(new URL('../admin_content_ownership.sql', import.meta.url), 'utf8');
const id = n => `90000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const admin = id(1), otherAdmin = id(2), alice = id(3), bob = id(4), supervisor = id(5), outsider = id(6), pending = id(7);
let checks = 0;
const check = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const page = async (status = 'pending', offset = 0, limit = 10, search = '', start = null, end = null) =>
  (await db.query('select assignments_feed_page($1,$2,$3,$4,$5,$6) result', [offset, limit, status, search, start, end])).rows[0].result;
const denied = async (...args) => { await assert.rejects(page(...args)); checks++; };
const add = async (n, { state = 'pendiente', due = '2035-01-01T15:00:00Z', members = [alice, bob], confirmed = [], owner = admin, title = `Evento ${n}` } = {}) => {
  await db.query(`insert into asignaciones(id,titulo,tipo_flujo,ubicacion,nivel_prioridad,estado,created_by,fecha_creacion,fecha_limite)
    values($1,$2,'campo','Recinto ficticio','baja',$3,$4,$5,$6)`, [id(n), title, state, owner,
      new Date(Date.parse('2026-01-01T00:00:00Z') + n * 1000).toISOString(), due]);
  await db.query(`insert into hitos_itinerario(id,asignacion_id,orden,descripcion,fecha_programada,estado_hito,completado)
    values($1,$2,1,'Montaje',$3,'disponible',false)`, [id(n + 10000), id(n), due]);
  for (const user of members) {
    await db.query('insert into asignacion_equipo(asignacion_id,perfil_id) values($1,$2)', [id(n), user]);
    await db.query(`insert into hitos_colaboradores(hito_id,usuario_id,confirmado_at,estado,hora_programada)
      values($1,$2,$3,$4,$5)`, [id(n + 10000), user, confirmed.includes(user) ? '2026-01-01T00:00:00Z' : null,
      confirmed.includes(user) ? 'temprano' : 'sin_confirmar', confirmed.includes(user) ? due : null]);
  }
};
try {
  for (const [index, user] of [admin, otherAdmin, alice, bob, supervisor, outsider, pending].entries()) {
    await db.query('insert into auth.users(id,email) values($1,$2)', [user, index === 0 ? 'yankee_admin@gmail.com' : `test-${index}@example.invalid`]);
    await db.query('insert into perfiles(id,nombre_completo,rol) values($1,$2,$3)', [user, `Persona ${String.fromCharCode(65 + index)}`, index < 2 ? 'admin' : 'empleado']);
    await db.query('insert into account_private.access(user_id,estado) values($1,$2)', [user, user === pending ? 'pendiente' : 'aprobada']);
  }
  await db.exec(ownership);
  for (let n = 100; n < 145; n++) await add(n);
  await add(200, { due: '2020-01-01T15:00:00Z' });
  await add(201, { confirmed: [alice] });
  await add(202, { members: [bob], owner: otherAdmin });
  await add(203, { state: 'vencida' });
  await add(204, { due: null });
  await add(205, { due: '2035-01-02T04:00:00Z' });
  await db.exec(migration);
  await db.exec(migration);

  await login(db, alice);
  const first = await page();
  const second = await page('pending', 10);
  const third = await page('pending', 20);
  const fourth = await page('pending', 30);
  const fifth = await page('pending', 40);
  check(first.items.length, 10);
  check(first.has_more, true);
  check(first.next_offset, 10);
  check(second.items.length, 10);
  check(second.has_more, true);
  check(third.items.length, 10);
  check(fourth.items.length, 10);
  check(fifth.items.length, 8);
  check(fifth.has_more, false);
  check(fifth.next_offset, null);
  const allItems = [first, second, third, fourth, fifth].flatMap(p => p.items);
  check(new Set(allItems.map(x => x.id)).size, 48);
  check(allItems.map(x => x.id), [205, 204, 203, ...Array.from({length: 45}, (_, i) => 144 - i)].map(id));
  check((await page('pending')).items.map(x => x.id), first.items.map(x => x.id));
  check((await page('pending', 0, 200)).items.length, 10);
  check((await page('pending', -50, 0)).items.length, 1);
  check((await page('pending', 500)).items, []);
  check((await page('overdue')).items.map(x => x.id), [id(200)]);
  check((await page('completed')).items.map(x => x.id), [id(201)]);
  check((await page('pending', 0, 10, 'Evento 100')).items.map(x => x.id), [id(100)]);
  check((await page('completed', 0, 10, 'Evento 201')).items.length, 1);
  check((await page('pending', 0, 10, 'Evento 201')).items, []);
  check(first.items[0].hitos_itinerario[0].hitos_colaboradores.some(x => x.usuario_id === alice), true);
  check(Array.isArray(first.items[0].asignacion_supervisores), true);
  check(Array.isArray(first.items[0].asignacion_equipo), true);
  const day = await page('all', 0, 10, '', '2035-01-01T04:00:00Z', '2035-01-02T04:00:00Z');
  check(day.items.length, 10);
  check(day.has_more, true);
  check((await page('completed', 0, 10, '', '2035-01-01T04:00:00Z', '2035-01-02T04:00:00Z')).items.map(x => x.id), [id(201)]);
  check((await page('overdue', 0, 10, '', '2020-01-01T04:00:00Z', '2020-01-02T04:00:00Z')).items.map(x => x.id), [id(200)]);
  check((await page('all', 0, 10, 'Evento 205', '2035-01-01T04:00:00Z', '2035-01-02T04:00:00Z')).items, []);
  check((await page('all', 0, 10, 'Evento 205', '2035-01-02T04:00:00Z', '2035-01-03T04:00:00Z')).items.map(x => x.id), [id(205)]);
  await denied('invalid');
  await denied('all', 0, 10, 'x'.repeat(101));
  await denied('all', 0, 10, '', '2035-01-01', null);
  await denied('all', 0, 10, '', '2035-01-02', '2035-01-01');
  await denied('all', 0, 10, '', '2035-01-01', '2035-01-04');

  await login(db, bob);
  check((await page('completed')).items, []);
  check((await page('pending', 0, 10, 'Evento 201')).items.length, 1);
  check((await page('all', 0, 10, 'Evento 202')).items.length, 1);
  await login(db, outsider);
  check((await page('all')).items, []);
  await login(db, pending);
  await denied('all');
  await login(db, admin);
  check((await page('overdue')).items.map(x => x.id), [id(203), id(200)]);
  check((await page('all', 0, 10, 'Evento 202')).items, []);
  check((await page('pending', 0, 10, 'Evento 201')).items.length, 1);
  await login(db, otherAdmin);
  check((await page('all')).items.map(x => x.id), [id(202)]);

  await maintenance(db);
  await db.query('insert into asignacion_equipo(asignacion_id,perfil_id) values($1,$2)', [id(201), supervisor]);
  await db.query('insert into asignacion_supervisores(asignacion_id,usuario_id) values($1,$2)', [id(201), supervisor]);
  await login(db, supervisor);
  check((await page('pending')).items.map(x => x.id), [id(201)]);
  check((await page('completed')).items, []);
  await maintenance(db);
  await add(206, { state: 'completada' });
  await login(db, admin);
  check((await page('completed', 0, 10, 'Evento 206')).items.map(x => x.id), [id(206)]);
  check((await page('all', 0, 10, 'Evento 206', '2035-01-01T04:00:00Z', '2035-01-02T05:00:00Z')).items.map(x => x.id), [id(206)]);
  // Verify the 10/11 boundary independently for each Home filter and role.
  for (const [index, status] of ['pending', 'overdue', 'completed'].entries()) {
    const base = 300 + index * 100;
    const title = `Serie ${status}`;
    const options = {
      title, state: status === 'completed' ? 'completada' : status === 'overdue' ? 'vencida' : 'pendiente',
      due: status === 'overdue' ? '2020-01-01T15:00:00Z' : '2035-01-01T15:00:00Z',
      confirmed: status === 'completed' ? [alice, bob] : []
    };
    await maintenance(db);
    for (let n = base; n < base + 10; n++) await add(n, options);
    const adminStatus = { pending: 'pendientes', overdue: 'vencidas', completed: 'completadas' }[status];
    const read = async (user, offset = 0) => {
      await login(db, user);
      return user === admin
        ? (await db.query('select admin_assignments_page($1,10,$2,$3) result', [offset, adminStatus, title])).rows[0].result
        : await page(status, offset, 10, title);
    };
    for (const user of [alice, admin]) {
      const ten = await read(user);
      check(ten.items.length, 10);
      check(ten.has_more, false);
      check(ten.items.map(x => x.id), Array.from({ length: 10 }, (_, i) => id(base + 9 - i)));
    }
    await maintenance(db);
    await add(base + 10, options);
    // Creation time, not a deadline or UUID, determines which record comes first.
    await db.query("update asignaciones set fecha_creacion='2027-01-01T00:00:00Z' where id=$1", [id(base)]);
    for (const user of [alice, admin]) {
      const eleven = await read(user);
      check(eleven.items.length, 10);
      check(eleven.items[0].id, id(base));
      check(eleven.has_more, true);
      check(eleven.next_offset, 10);
      const last = await read(user, 10);
      check(last.items.map(x => x.id), [id(base + 1)]);
      check(last.has_more, false);
      check(last.next_offset, null);
    }
  }
  await maintenance(db);
  await db.exec('set role anon');
  await denied('all');
  await db.exec('reset role');
  check((await db.query("select prosecdef from pg_proc where oid='public.assignments_feed_page(integer,integer,text,text,timestamptz,timestamptz)'::regprocedure")).rows[0].prosecdef, false);
  console.log(`PASS: ${checks} feed checks; bounded pages, personal states, daily filters, ownership and RLS`);
} finally {
  await db.close();
}
