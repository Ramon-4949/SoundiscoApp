import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const { btree_gist } = await import(new URL('./contrib/btree_gist.js', `file://${process.env.PGLITE_PATH}`));
const db = new PGlite({ extensions: { btree_gist } });
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const sql = file => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8')
  .replaceAll('create extension if not exists pg_cron with schema pg_catalog;', '');
const user = n => db.query("select set_config('test.uid',$1,false)", [id(n)]);
const check = n => db.query('select check_in_milestone($1)', [id(n)]);
const at = delta => new Date(Date.now() + delta * 60000).toISOString();
const h = (n, order, delta, users) => ({ id: id(n), orden: order, descripcion: `Hito ${n}`,
  fecha_programada: at(delta), hora_estimada: '12:00:00', colaboradores: users.map(id) });
const payload = { titulo: 'Evento granular', tipo_flujo: 'campo', ubicacion: 'Almacen',
  nivel_prioridad: 'media', supervisores: [id(4)] };
const create = async milestones => (await db.query('select admin_create_assignment($1,$2,$3) id',
  [payload, [], JSON.stringify(milestones)])).rows[0].id;
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema account_private; create schema cron;
    create table auth.users(id uuid primary key, raw_user_meta_data jsonb);
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function auth.role() returns text language sql as $$ select 'authenticated'::text $$;
    create function cron.schedule(text,text,text) returns bigint language sql as $$ select 1::bigint $$;
    create function cron.unschedule(bigint) returns boolean language sql as $$ select true $$;
    create table cron.job(jobid bigint,jobname text);
    create table perfiles(id uuid primary key,nombre_completo text,rol text,cargo text);
    create table account_private.access(user_id uuid,estado text);
    create function public.account_is_approved() returns boolean language sql security definer as $$
      select exists(select 1 from account_private.access where user_id=auth.uid() and estado='aprobada') $$;
    create table asignaciones(id uuid primary key,titulo text,tipo_flujo text,ubicacion text,
      nivel_prioridad text,instrucciones text,estado text,fecha_creacion timestamptz,fecha_limite timestamptz);
    create table asignacion_equipo(asignacion_id uuid references asignaciones(id) on delete cascade,perfil_id uuid references perfiles(id));
    create table hitos_itinerario(id uuid primary key,asignacion_id uuid references asignaciones(id) on delete cascade,
      orden int,descripcion text,hora_estimada time,fecha_programada timestamptz,estado_hito text,
      completado bool,notas_incidencias text,hora_real_completado timestamptz);
    create table checklist_equipos(id uuid primary key,asignacion_id uuid references asignaciones(id));
    create table comunicados(id uuid primary key,asunto text,mensaje text,fecha_publicacion timestamptz,leido_por uuid[]);
    create table notificaciones_app(id uuid primary key,perfil_id uuid references perfiles(id),titulo text,mensaje text,
      leida bool,fecha_creacion timestamptz,asignacion_relacionada_id uuid references asignaciones(id));
    grant usage on schema public,auth to authenticated,anon;
    insert into perfiles values('${id(1)}','Admin','admin','Admin'),('${id(2)}','Ana','empleado','Sonido'),
      ('${id(3)}','Bob','empleado','Sonido'),('${id(4)}','Supervisor','empleado','Supervisor'),('${id(5)}','Ajeno','empleado','Sonido');
    insert into account_private.access select id,'aprobada' from perfiles;
  `);
  await user(1);
  for (const file of ['admin_creation_setup.sql', 'assignment_checklist_setup.sql',
    'admin_crud_completion.sql', 'assignment_milestone_editing_fix.sql', 'administrative_assignment_location_fix.sql',
    'notifications_setup.sql', 'notification_reminders.sql', 'notifications_dynamic.sql',
    'milestone_notifications_admin_only.sql', 'employee_availability.sql', 'assignment_expiration_setup.sql',
    'assignment_sla_setup.sql', 'admin_performance_setup.sql', 'milestone_collaborators.sql']) {
    try { await db.exec(sql(file)); } catch (error) { console.error('Migration:', file); throw error; }
  }
  await db.exec(sql('milestone_collaborators.sql'));
  const milestones = [h(101, 1, -10, [2, 3]), h(102, 2, 20, [2]), h(103, 3, 30, [3])];
  const aid = await create(milestones);
  await db.exec(sql('milestone_collaborators.sql'));
  await db.exec(sql('assignment_status_automation.sql'));
  await db.exec(sql('assignment_status_automation.sql'));
  await db.exec(sql('assignment_collaborators_list.sql'));
  await db.exec(sql('assignment_note_author_visibility.sql'));
  await user(2);
  const roster = (await db.query('select * from assignment_collaborators($1)',[aid])).rows;
  assert.equal(roster.length,3);
  assert.equal(roster[0].id,id(4));
  assert.equal(roster[0].es_supervisor,true);
  assert.deepEqual(Object.keys(roster[0]).sort(),['cargo','es_supervisor','id','nombre']);
  await db.query('select add_assignment_note($1,$2,$3)',[id(801),aid,'Nota de Ana']);
  await user(3);
  await db.query('select add_assignment_note($1,$2,$3)',[id(802),aid,'Nota de Bob']);
  let notes = (await db.query('select * from assignment_notes($1,0,200)',[aid])).rows;
  assert.equal(notes.length,2);
  assert.ok(notes.every(note => note.autor_nombre === null));
  assert.equal(notes.find(note => note.contenido === 'Nota de Bob').usuario_id,id(3));
  assert.equal(notes.find(note => note.contenido === 'Nota de Ana').usuario_id,null);
  await user(4);
  notes = (await db.query('select * from assignment_notes($1,0,200)',[aid])).rows;
  assert.deepEqual(new Set(notes.map(note => note.autor_nombre)),new Set(['Ana','Bob']));
  await user(1);
  notes = (await db.query('select * from assignment_notes($1,0,200)',[aid])).rows;
  assert.deepEqual(new Set(notes.map(note => note.autor_nombre)),new Set(['Ana','Bob']));
  await user(5);
  await assert.rejects(db.query('select * from assignment_collaborators($1)',[aid]),/acceso/);
  await assert.rejects(db.query('select * from assignment_notes($1,0,200)',[aid]),/acceso/);
  await user(1);
  assert.equal((await db.query('select count(*)::int n from hitos_colaboradores')).rows[0].n, 4);
  await user(2);
  await assert.rejects(check(102), /primero/);
  await check(101);
  assert.equal((await db.query('select estado from hitos_colaboradores where hito_id=$1 and usuario_id=$2',[id(101),id(2)])).rows[0].estado, 'tardio');
  assert.equal((await db.query('select completado from hitos_itinerario where id=$1',[id(101)])).rows[0].completado, false);
  await check(102);
  await check(102);
  assert.equal((await db.query('select count(*)::int n from confirmaciones_hitos where hito_id=$1',[id(102)])).rows[0].n, 1);
  assert.equal((await db.query('select estado from hitos_colaboradores where hito_id=$1',[id(102)])).rows[0].estado,'temprano');
  await assert.rejects(check(103), /No est.s asignado/);
  const recipients = (await db.query("select distinct perfil_id from notificaciones_app where tipo='hito_completado'")).rows;
  assert.deepEqual(recipients.map(r => r.perfil_id),[id(1)]);
  console.log('PASS early and late, personal sequence, idempotency, no group wait');
  await user(3); await check(101);
  assert.equal((await db.query('select completado from hitos_itinerario where id=$1',[id(101)])).rows[0].completado,true);
  await user(1);
  const removeConfirmed = milestones.map((m,i) => i === 0 ? {...m,colaboradores:[id(3)]} : m);
  await assert.rejects(db.query('select admin_update_assignment($1,$2,$3,$4)',
    [aid,payload,[],JSON.stringify(removeConfirmed)]),/retirar colaboradores/);
  await user(3);
  await db.exec("update hitos_itinerario set fecha_programada=clock_timestamp()-interval '1 minute' where id='"+id(103)+"'");
  await assert.rejects(check(103), /plazo final/);
  await db.exec('select process_assignment_sla()');
  assert.equal((await db.query('select completado from hitos_itinerario where id=$1',[id(103)])).rows[0].completado,false);
  console.log('PASS all required for completion, hard stop enforced by RPC, cron never invents completion');
  await db.exec('grant select on public.hitos_itinerario,public.perfiles,public.asignacion_equipo to authenticated; set role authenticated');
  await user(2);
  assert.equal((await db.query('select count(*)::int n from hitos_itinerario')).rows[0].n,2);
  assert.equal((await db.query('select count(*)::int n from hitos_colaboradores')).rows[0].n,2);
  await assert.rejects(db.query('select * from notas_asignacion'),/permission denied/);
  await assert.rejects(db.exec("update hitos_colaboradores set estado='a_tiempo'"), /permission denied/);
  await user(4);
  assert.equal((await db.query('select count(*)::int n from hitos_itinerario')).rows[0].n,3);
  assert.equal((await db.query('select count(*)::int n from hitos_colaboradores')).rows[0].n,4);
  await assert.rejects(check(103),/No est.s asignado/);
  await user(5);
  assert.equal((await db.query('select count(*)::int n from hitos_itinerario')).rows[0].n,0);
  await user(1);
  assert.equal((await db.query('select count(*)::int n from hitos_itinerario')).rows[0].n,3);
  await db.exec('reset role');
  console.log('PASS employee/supervisor/admin RLS and no direct confirmation writes');
  // A later milestone for Bob must not extend Ana's personal deadline.
  payload.supervisores = [];
  const next = [h(201,1,-20,[5]),h(202,2,-10,[5]),h(203,3,100,[3])];
  const second = await create(next);
  await user(5); await assert.rejects(check(201),/plazo final/); await assert.rejects(check(202),/plazo final/);
  await user(1);
  // Existing confirmations are immutable even when edited by an administrator.
  const edited = [...milestones]; edited[0] = {...edited[0], colaboradores:[id(3)]};
  await assert.rejects(db.query('select admin_update_assignment($1,$2,$3,$4)',[aid,payload,[],JSON.stringify(edited)]), /confirm|horario|fechas/i);
  await assert.rejects(create([h(301,1,200,[])]),/necesita colaboradores/);
  const editable = [h(501,1,200,[2]),h(502,2,220,[3])];
  const editableID = await create(editable);
  const changed = [editable[0],h(503,2,230,[2])];
  await db.query('select admin_update_assignment($1,$2,$3,$4)',[editableID,payload,[],JSON.stringify(changed)]);
  assert.equal((await db.query('select count(*)::int n from hitos_colaboradores where hito_id=$1',[id(502)])).rows[0].n,0);
  assert.equal((await db.query('select usuario_id from hitos_colaboradores where hito_id=$1',[id(503)])).rows[0].usuario_id,id(2));
  const statusID = await create([h(601,1,30,[2,3])]);
  const state = async () => (await db.query('select estado from asignaciones where id=$1',[statusID])).rows[0].estado;
  assert.equal(await state(),'pendiente');
  await user(2); await check(601);
  assert.equal(await state(),'en_curso');
  await user(3); await check(601);
  assert.equal(await state(),'completada');
  const adminMessages = (await db.query("select titulo,mensaje from notificaciones_app where perfil_id=$1 and tipo='hito_completado' order by fecha_creacion desc",[id(1)])).rows;
  assert.ok(adminMessages.some(row => row.titulo === 'Confirmación de Hito' && row.mensaje.includes('confirmó')), JSON.stringify(adminMessages));
  assert.equal((await db.query("select count(*)::int n from notificaciones_app where tipo='estado_actualizado'")).rows[0].n,0);
  await user(1);
  const overdueID = await create([h(602,1,-2,[5])]);
  assert.equal((await db.query('select estado from asignaciones where id=$1',[overdueID])).rows[0].estado,'pendiente');
  assert.equal((await db.query('select estado from asignaciones_estado_efectivo where id=$1',[overdueID])).rows[0].estado,'vencida');
  await db.query('select generate_notification_reminders()');
  await db.query('select admin_delete_assignment($1)',[aid]);
  assert.equal((await db.query('select count(*)::int n from hitos_colaboradores where hito_id=$1',[id(101)])).rows[0].n,0);
  console.log('PASS personal hard stop, idempotent migration, editing/add/remove, confirmed history protected, event deletion');
} catch (error) {
  console.error(error.message, error.where ?? '', error.internalQuery ?? '', error.stack?.split('\n').slice(-4).join('\n'));
  process.exitCode = 1;
} finally { await db.close(); }
