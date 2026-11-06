import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const modulePath = process.env.PGLITE_PATH;
if (!modulePath) throw new Error('Set PGLITE_PATH to the PGlite dist/index.js file URL');
const { PGlite } = await import(modulePath);
const { btree_gist } = await import(new URL('./contrib/btree_gist.js', modulePath).href);
const db = new PGlite({ extensions: { btree_gist } });
const schema = JSON.parse(readFileSync(new URL('./fixtures/admin_ownership_schema.json', import.meta.url), 'utf8'));
const migration = readFileSync(new URL('../admin_content_ownership.sql', import.meta.url), 'utf8');
const quote = name => `"${name.replaceAll('"', '""')}"`;
const id = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const adminA = id(100), adminB = id(101), employee = id(102), stranger = id(103);
const users = [adminA, adminB, employee, stranger];
const payload = (aid, title) => ({ id: aid, titulo: title, tipo_flujo: 'campo',
  ubicacion: 'Recinto ficticio', nivel_prioridad: 'baja', estado: 'pendiente' });
const milestone = (hid, members, hour = 10) => ({ id: hid, descripcion: 'Preparar montaje', orden: 1,
  fecha_programada: `2035-01-01T${hour}:00:00Z`, hora_estimada: `${hour}:00:00`, colaboradores: members });
const login = async uid => {
  await db.exec('reset role');
  await db.query("select set_config('test.uid',$1,false),set_config('test.role','authenticated',false)", [uid]);
  await db.exec('set role authenticated');
};
const maintenance = async () => {
  await db.exec('reset role');
  await db.exec("select set_config('test.uid','',false),set_config('test.role','',false)");
};
let checks = 0;
const check = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const denied = async (sql, args = []) => { await assert.rejects(db.query(sql, args)); checks++; };
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth;
    create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',
      email_confirmed_at timestamptz,banned_until timestamptz);
    create function auth.uid() returns uuid language sql stable as
      $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function auth.role() returns text language sql stable as
      $$select nullif(current_setting('test.role',true),'')$$;
    grant usage on schema public,auth to anon,authenticated,service_role;
    create extension btree_gist;
    set check_function_bodies=off;
  `);
  for (const name of new Set(schema.tables.map(t => t.schema))) {
    if (name !== 'public') await db.exec(`create schema ${quote(name)}`);
  }
  for (const table of schema.tables) {
    const columns = table.columns.map(c => `${quote(c.name)} ${c.type.startsWith('_') ? c.type.slice(1) + '[]' : c.type}
      ${c.nullable === 'NO' ? 'not null' : ''} ${c.default === null ? '' : 'default ' + c.default}`);
    await db.exec(`create table ${quote(table.schema)}.${quote(table.name)} (${columns.join(',')})`);
  }
  for (const constraint of schema.constraints.filter(c => !c.definition.startsWith('FOREIGN KEY') && !c.definition.startsWith('TRIGGER'))) {
    await db.exec(`alter table ${quote(constraint.schema)}.${quote(constraint.name)} add constraint ${quote(constraint.conname)} ${constraint.definition}`);
  }
  for (const constraint of schema.constraints.filter(c => c.definition.startsWith('FOREIGN KEY'))) {
    await db.exec(`alter table ${quote(constraint.schema)}.${quote(constraint.name)} add constraint ${quote(constraint.conname)} ${constraint.definition}`);
  }
  for (const index of schema.indexes) await db.exec(index.definition);
  for (const routine of schema.extraFunctions) await db.exec(routine.definition);
  for (const routine of schema.functions) {
    await db.exec(routine.definition);
    await db.exec(`revoke all on function ${routine.signature} from public,anon,authenticated`);
    if (routine.client_execute) await db.exec(`grant execute on function ${routine.signature} to authenticated`);
  }
  await db.exec(`create view asignaciones_estado_efectivo as ${schema.view}`);
  for (const table of schema.tables) {
    await db.exec(`alter table ${quote(table.schema)}.${quote(table.name)} enable row level security`);
  }
  for (const policy of schema.policies) {
    await db.exec(`create policy ${quote(policy.policyname)} on ${quote(policy.schemaname)}.${quote(policy.tablename)}
      as ${policy.permissive} for ${policy.cmd} to ${policy.roles.slice(1, -1).split(',').map(quote).join(',')}
      ${policy.qual ? `using (${policy.qual})` : ''} ${policy.with_check ? `with check (${policy.with_check})` : ''}`);
  }
  await db.exec(`
    grant select,insert,update,delete,truncate,references,trigger on all tables in schema public to authenticated;
    revoke insert,update,delete on perfiles from authenticated;
    grant update(nombre_usuario,telefono,cargo,usa_biometria) on perfiles to authenticated;
    revoke all on notas_asignacion from authenticated;
    revoke insert,update,delete on hitos_colaboradores,confirmaciones_hitos,asignacion_supervisores,notificaciones_app from authenticated;
    set check_function_bodies=on;
  `);
  for (let n = 0; n < users.length; n++) {
    await db.query('insert into auth.users(id,email) values($1,$2)', [users[n],
      ['yankee_admin@gmail.com', 'admin.b@example.invalid', 'employee@example.invalid', 'stranger@example.invalid'][n]]);
    await db.query('insert into perfiles(id,nombre_completo,rol,telefono,cargo) values($1,$2,$3,$4,$5)',
      [users[n], ['Admin A', 'Admin B', 'Employee', 'Stranger'][n], n < 2 ? 'admin' : 'empleado', '+18095550100', null]);
    await db.query("insert into account_private.access(user_id,estado) values($1,'aprobada')", [users[n]]);
  }
  for (const trigger of schema.triggers) await db.exec(trigger.definition);
  await login(adminA);
  await db.query('select admin_create_assignment($1,$2,$3)', [payload(id(200), 'Legacy A'),
    [employee], [milestone(id(210), [employee])]]);
  await db.query("insert into comunicados(id,asunto,mensaje) values($1,'Legacy A','Company-wide bulletin')", [id(220)]);
  await maintenance();
  await db.query("update auth.users set email='unavailable@example.invalid' where id=$1", [adminA]);
  await assert.rejects(db.exec(migration), /El creador historico debe ser una cuenta administradora existente/); checks++;
  await db.exec('rollback');
  check((await db.query("select column_name from information_schema.columns where table_name='asignaciones' and column_name='created_by'")).rows, []);
  await db.query("update auth.users set email='yankee_admin@gmail.com' where id=$1", [adminA]);
  await db.exec(migration);
  await db.exec(migration);
  check((await db.query('select created_by from asignaciones where id=$1', [id(200)])).rows[0].created_by, adminA);
  check((await db.query("select id from notificaciones_app where perfil_id=$1 and destino_tipo in('asignacion','comunicado')", [adminB])).rows, []);

  for (let n = 0; n < users.length; n++) {
    await login(users[n]);
    await db.query("select register_push_device($1,$2,'production')", [id(300 + n), String(n + 1).repeat(64)]);
    await db.query('select register_android_push_device($1,$2)', [id(400 + n), `fcm-test-${String(n + 1).repeat(120)}`]);
  }
  await login(adminB);
  check((await db.query('select id from asignaciones')).rows, []);
  check((await db.query('select id from comunicados')).rows, []);
  check((await db.query('select id from asignaciones_estado_efectivo')).rows, []);
  check((await db.query('select id from hitos_itinerario')).rows, []);
  check((await db.query('select admin_dashboard_summary() result')).rows[0].result.total, 0);
  check((await db.query('select admin_assignments_page() result')).rows[0].result.items, []);
  check((await db.query("select * from admin_employee_performance('2035-01-01')")).rows, []);
  const blockedWindow = (await db.query("select disponible,ocupado_desde,ocupado_hasta from admin_employee_availability('2035-01-01T10:00:00Z','2035-01-01T11:00:00Z') where id=$1", [employee])).rows[0];
  check(blockedWindow, { disponible: false, ocupado_desde: null, ocupado_hasta: null });
  await denied("select admin_employee_availability('2035-01-01','2035-01-02',$1)", [id(200)]);
  check((await db.query('select assignment_deadline($1) deadline', [id(200)])).rows[0].deadline, null);
  await denied('select admin_delete_assignment($1)', [id(200)]);
  await denied('select admin_update_assignment($1,$2,$3,$4)', [id(200), payload(id(200), 'Stolen event'),
    [employee], [milestone(id(210), [employee])]]);
  await denied('select assignment_notes($1)', [id(200)]);
  await denied('select assignment_collaborators($1)', [id(200)]);
  check((await db.query("update comunicados set asunto='Stolen message' where id=$1 returning id", [id(220)])).rows, []);
  await denied('truncate asignaciones cascade');
  await denied('select * from ownership_private.resource_creators');
  await denied('select ownership_private.check_in_legacy($1)', [id(210)]);
  await denied("insert into comunicados(asunto,mensaje,created_by) values('Forged message','Forged author is forbidden',$1)", [adminA]);
  await db.query('select admin_create_assignment($1,$2,$3)', [{ ...payload(id(201), 'B event'), created_by: adminA },
    [employee, adminA], [milestone(id(211), [employee, adminA], 14)]]);
  check((await db.query('select created_by from asignaciones where id=$1', [id(201)])).rows[0].created_by, adminB);
  await denied('update asignaciones set created_by=$1 where id=$2', [adminA, id(201)]);
  await db.query("insert into comunicados(id,asunto,mensaje) values($1,'B bulletin','Message published by admin B')", [id(221)]);
  check((await db.query('select id from asignaciones')).rows.map(r => r.id), [id(201)]);
  check((await db.query('select id from comunicados')).rows.map(r => r.id), [id(221)]);
  check((await db.query('select admin_dashboard_summary() result')).rows[0].result.total, 1);
  check((await db.query('select admin_assignments_page() result')).rows[0].result.items.map(r => r.id), [id(201)]);
  check((await db.query("select item->>'asignaciones' total from admin_employee_performance('2035-01-01') item")).rows.map(r => r.total), ['1']);

  await login(adminA);
  check((await db.query('select id from asignaciones')).rows.map(r => r.id), [id(200)]);
  check((await db.query('select id from hitos_itinerario')).rows.map(r => r.id), [id(210)]);
  check((await db.query('select hito_id from hitos_colaboradores where hito_id=$1', [id(211)])).rows, []);
  check((await db.query("select ocupado_desde is not null visible from admin_employee_availability('2035-01-01T10:00:00Z','2035-01-01T11:00:00Z') where id=$1", [employee])).rows[0].visible, true);
  await denied('select check_in_milestone($1)', [id(211)]);
  await denied('select undo_milestone_confirmation($1)', [id(211)]);
  await denied('select employee_complete_milestone($1,null)', [id(211)]);
  await denied('select admin_delete_assignment($1)', [id(201)]);
  check((await db.query('select id from perfiles order by id')).rows.map(r => r.id), users);
  check((await db.query('select id from admin_list_accounts() order by id')).rows.map(r => r.id), users);
  await db.query('select admin_update_assignment($1,$2,$3,$4)', [id(200), payload(id(200), 'Edited A event'),
    [employee], [milestone(id(210), [employee])]]);
  await login(employee);
  check((await db.query('select id from asignaciones order by id')).rows.map(r => r.id), [id(200), id(201)]);
  check((await db.query('select id from comunicados order by id')).rows.map(r => r.id), [id(220), id(221)]);
  await db.query('select add_assignment_note($1,$2,$3)', [id(230), id(200), 'Note for A event']);
  await db.query('select add_assignment_note($1,$2,$3)', [id(231), id(201), 'Note for B event']);
  await db.query("select report_assignment_note($1,'otro')", [id(230)]);
  await db.query("select report_assignment_note($1,'otro')", [id(231)]);
  await maintenance();
  await db.query("update notas_asignacion set created_at='2035-01-01T11:00:00Z' where id in($1,$2)", [id(230), id(231)]);
  for (const admin of [adminA, adminB]) {
    await login(admin);
    check((await db.query("select item->'notas_semanales'->0->>'cantidad' total from admin_employee_performance('2035-01-01') item")).rows.map(r => r.total), ['1']);
  }
  await login(employee);
  await db.query('select check_in_milestone($1)', [id(210)]);
  await login(adminA);
  check((await db.query("select item->>'temprano' total from admin_employee_performance('2035-01-01') item")).rows.map(r => r.total), ['1']);
  await login(adminB);
  check((await db.query("select item->>'temprano' total from admin_employee_performance('2035-01-01') item")).rows.map(r => r.total), ['0']);
  await login(employee);
  await db.query('select undo_milestone_confirmation($1)', [id(210)]);
  await db.query('select check_in_milestone($1)', [id(211)]);
  await db.query('select undo_milestone_confirmation($1)', [id(211)]);
  await login(stranger);
  check((await db.query('select id from asignaciones')).rows, []);
  await denied('select check_in_milestone($1)', [id(210)]);
  await login(adminB);
  const reports = (await db.query('select * from admin_note_reports()')).rows;
  check(reports.map(r => r.note_id), [id(231)]);
  await denied('select admin_remove_assignment_note($1)', [id(230)]);
  await login(adminA);
  const reportA = (await db.query('select * from admin_note_reports()')).rows;
  check(reportA.map(r => r.note_id), [id(230)]);
  await denied('select admin_resolve_note_report($1)', [reports[0].id]);
  await db.query('select admin_resolve_note_report($1)', [reportA[0].id]);
  await db.query('select admin_remove_assignment_note($1)', [id(230)]);
  await maintenance();
  check((await db.query("select perfil_id,destino_id from notificaciones_app where tipo='hito_completado' and destino_id in($1,$2) order by destino_id", [id(200), id(201)])).rows,
    [{ perfil_id: adminA, destino_id: id(200) }, { perfil_id: adminB, destino_id: id(201) }]);
  check((await db.query(`select count(*)::int n from notificaciones_app n join perfiles p on p.id=n.perfil_id
    where p.rol='admin' and not coalesce(ownership_private.notification_allowed(n.perfil_id,n.destino_tipo,n.destino_id,n.asignacion_relacionada_id),false)`)).rows[0].n, 0);
  for (const queue of ['notification_private', 'android_push_private']) {
    check((await db.query(`select count(*)::int n from ${queue}.outbox o join notificaciones_app n on n.id=o.notification_id
      join perfiles p on p.id=o.recipient where p.rol='admin' and not coalesce(
      ownership_private.notification_allowed(o.recipient,n.destino_tipo,n.destino_id,n.asignacion_relacionada_id),false)`)).rows[0].n, 0);
    check((await db.query(`select count(*)::int n from ${queue}.outbox o join notificaciones_app n on n.id=o.notification_id
      where o.recipient=$1 and n.destino_id=$2`, [adminA, id(200)])).rows[0].n > 0, true);
  }
  await db.query('select process_assignment_sla()');
  await db.query('select generate_notification_reminders()');
  await login(adminB);
  await db.query('select admin_delete_assignment($1)', [id(201)]);
  await db.query('delete from comunicados where id=$1', [id(221)]);
  await maintenance();
  check((await db.query('select count(*)::int n from asignaciones where id=$1', [id(200)])).rows[0].n, 1);
  await db.query("select notification_private.emit($1,'asignacion_eliminada','Late notice','Must not arrive','asignacion',$2,null,'late-other-admin')", [adminA, id(201)]);
  check((await db.query("select id from notificaciones_app where evento_key='late-other-admin'")).rows, []);
  await login(adminA);
  await denied('select admin_create_assignment($1,$2,$3)', [payload(id(201), 'Reused foreign identifier'),
    [employee], [milestone(id(214), [employee], 16)]]);
  await maintenance();
  await db.exec(migration);
  await login(adminA);
  await db.query('select delete_my_account()');
  await maintenance();
  check((await db.query('select id from auth.users where id=$1', [adminA])).rows, []);
  check((await db.query('select id from auth.users where id=$1', [adminB])).rows.map(r => r.id), [adminB]);
  check((await db.query('select created_by from asignaciones where id=$1', [id(200)])).rows[0].created_by, adminA);
  await db.exec('set role anon');
  await denied('select admin_assignments_page()');
  await denied('select public.admin_owns_assignment($1)', [id(200)]);
  await denied('select * from ownership_private.resource_creators');
  console.log(`PASS: ${checks} creator-ownership checks against actual RPC definitions and RLS policies`);
} catch (error) {
  console.error(`Failed after ${checks} creator-ownership checks`, error);
  throw error;
} finally {
  await db.close();
}
