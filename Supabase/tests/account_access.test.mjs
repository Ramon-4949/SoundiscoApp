import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const { btree_gist } = await import(new URL('./contrib/btree_gist.js', `file://${process.env.PGLITE_PATH}`));
const db = new PGlite({ extensions: { btree_gist } });
const admin = '00000000-0000-0000-0000-000000000001';
const employee = '00000000-0000-0000-0000-000000000002';
const pending = '00000000-0000-0000-0000-000000000003';
const newcomer = '00000000-0000-0000-0000-000000000004';
const assignment = '10000000-0000-0000-0000-000000000001';
const run = (sql, args = []) => db.query(sql, args);
const as = uid => run("select set_config('test.uid',$1,false)", [uid]);
const apply = async file => db.exec(readFileSync(new URL(`../${file}`, import.meta.url), 'utf8'));
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role; create role authenticator;
    create schema auth;
    create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);
    create function auth.uid() returns uuid language sql as
      $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function auth.role() returns text language sql as $$ select 'authenticated'::text $$;
    create table perfiles(id uuid primary key,nombre_completo text,rol text,telefono text);
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
    insert into perfiles values ('${admin}','Admin','admin',null),('${employee}','Employee','tecnico',null);
    insert into auth.users values ('${admin}','admin@example.test','{}'),('${employee}','employee@example.test','{}');
    select set_config('test.uid','${admin}',false);
  `);
  await db.exec('alter table auth.users add column email_confirmed_at timestamptz');
  for (const file of ['admin_creation_setup.sql','assignment_checklist_setup.sql','admin_crud_completion.sql',
    'administrative_assignment_location_fix.sql','notifications_setup.sql','notification_reminders.sql',
    'notifications_dynamic.sql','employee_availability.sql','account_access_setup.sql',
    'account_approval_auth_fix.sql','profile_roles_and_jobs.sql']) await apply(file);
  await apply('profile_roles_and_jobs.sql');
  assert.equal((await run('select rol from perfiles where id=$1',[employee])).rows[0].rol,'empleado');
  assert.notEqual((await run('select email_confirmed_at from auth.users where id=$1',[admin])).rows[0].email_confirmed_at,null);
  assert.equal((await run('select account_is_approved() ok')).rows[0].ok, true);
  assert.equal((await run("select has_function_privilege('service_role','public.check_account_access()','execute') ok")).rows[0].ok,true);
  assert.equal((await run("select has_function_privilege('anon','public.check_account_access()','execute') ok")).rows[0].ok,true);
  await run('insert into auth.users(id,email,raw_user_meta_data) values ($1,$2,$3)', [pending,'pending@example.test',
    JSON.stringify({nombre_completo:'New Employee',cargo:'Técnico de sonido',rol:'admin'})]);
  const pendingProfile = (await run('select rol,cargo from perfiles where id=$1',[pending])).rows[0];
  assert.deepEqual(pendingProfile,{rol:'empleado',cargo:'Técnico de sonido'});
  await apply('account_access_setup.sql');
  await as(pending);
  assert.equal((await run('select my_account_access() s')).rows[0].s.estado,'pendiente');
  await assert.rejects(run('select admin_list_accounts()'),/Solo administradores/);
  await assert.rejects(run('select admin_review_account($1,$2)',[pending,'aprobada']),/Solo administradores/);
  await db.exec("select set_config('request.path','/rpc/employee_complete_milestone',false)");
  await assert.rejects(run('select check_account_access()'),/no tiene acceso aprobado/);
  await db.exec("select set_config('request.path','/rpc/my_account_access',false)");
  await run('select check_account_access()');
  await db.exec('set role authenticated');
  await assert.rejects(run("update account_private.access set estado='aprobada'"),/permission denied/);
  await db.exec('reset role');
  await db.exec('grant select on public.perfiles to authenticated; set role authenticated');
  assert.deepEqual((await run('select id from perfiles')).rows.map(r=>r.id),[pending]);
  await db.exec('reset role');
  console.log('PASS existing access, pending registration, tamper resistance and RPC guard');

  await as(admin);
  await run('select admin_review_account($1,$2)',[pending,'rechazada']);
  assert.equal((await run('select email_confirmed_at from auth.users where id=$1',[pending])).rows[0].email_confirmed_at,null);
  await run('select admin_review_account($1,$2)',[pending,'aprobada']);
  const confirmed = (await run('select email_confirmed_at from auth.users where id=$1',[pending])).rows[0].email_confirmed_at;
  assert.notEqual(confirmed,null);
  await run('select admin_review_account($1,$2)',[pending,'aprobada']);
  assert.deepEqual((await run('select email_confirmed_at from auth.users where id=$1',[pending])).rows[0].email_confirmed_at,confirmed);
  await run('update auth.users set email_confirmed_at=null where id=$1',[pending]);
  await apply('account_approval_auth_fix.sql');
  assert.notEqual((await run('select email_confirmed_at from auth.users where id=$1',[pending])).rows[0].email_confirmed_at,null);
  assert.equal((await run("select count(*)::int n from notificaciones_app where perfil_id=$1 and tipo='cuenta_aprobada'",[pending])).rows[0].n,1);
  await as(pending);
  await run('select check_account_access()');
  assert.equal((await run('select my_account_access() s')).rows[0].s.estado,'aprobada');
  console.log('PASS approval/rejection transitions, idempotency and notification');

  await as(admin);
  await run('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[newcomer,'new@example.test','{}']);
  await apply('account_approval_auth_fix.sql');
  assert.equal((await run('select email_confirmed_at from auth.users where id=$1',[newcomer])).rows[0].email_confirmed_at,null);
  console.log('PASS Auth confirmation on approval, repair of old approvals, pending exclusion and idempotency');
  await db.exec(`insert into asignaciones(id,titulo,tipo_flujo,ubicacion,estado,fecha_creacion,fecha_limite)
    values('${assignment}','Audit','administrativa',null,'pendiente',now(),now()+interval '2 hours');`);
  await assert.rejects(run('insert into asignacion_equipo values($1,$2)',[assignment,newcomer]),/acceso aprobado/);
  await run('insert into asignacion_equipo values($1,$2)',[assignment,pending]);
  await run("insert into comunicados(id,asunto,mensaje,leido_por) values(gen_random_uuid(),'News','Hello',$1::uuid[])",[[pending]]);
  assert.equal((await run("select count(*)::int n from notificaciones_app where perfil_id=$1 and destino_tipo='comunicado'",[newcomer])).rows[0].n,0);
  await as(pending);
  await run('select delete_my_account()');
  for (const table of ['auth.users','perfiles']) {
    assert.equal((await run(`select count(*)::int n from ${table} where id=$1`,[pending])).rows[0].n,0);
  }
  assert.equal((await run('select count(*)::int n from asignacion_equipo where perfil_id=$1',[pending])).rows[0].n,0);
  assert.equal((await run('select count(*)::int n from comunicados where $1=any(leido_por)',[pending])).rows[0].n,0);
  await db.exec("select set_config('request.path','/asignaciones',false)");
  await assert.rejects(run('select check_account_access()'),/no tiene acceso aprobado/);
  await as(newcomer);
  await run('select delete_my_account()');
  assert.equal((await run('select count(*)::int n from auth.users where id=$1',[newcomer])).rows[0].n,0);
  console.log('PASS assignment eligibility, pending push privacy, actual deletion and stale JWT denial');
} finally {
  await db.close();
}
