import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema account_private;
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
    create function auth.role() returns text language sql as $$ select current_setting('test.role',true) $$;
    create function public.account_is_approved() returns boolean language sql as $$ select current_setting('test.approved',true) = 'true' $$;
    create table auth.users(id uuid primary key,raw_user_meta_data jsonb);
    create table public.perfiles(id uuid primary key,nombre_completo text,telefono text,cargo text,rol text);
    create table public.cargos_empresa(nombre text,activo boolean);
    insert into cargos_empresa values('Supervisor',true),('Obsoleto',false);
    insert into auth.users values('${id(1)}','{"nombre_usuario":"ana.old"}'),('${id(2)}','{}');
    insert into perfiles values('${id(1)}','Ana Pérez','8095550100','Supervisor','empleado'),('${id(2)}','Otro Usuario','8095550101','Supervisor','empleado');
    grant usage on schema public,auth to authenticated,anon;
    grant select,update on perfiles to authenticated;
  `);
  const migration = readFileSync(new URL('../profile_editing.sql',import.meta.url),'utf8');
  await db.exec(migration);
  await db.exec(migration);
  await db.exec(`
    create or replace function account_private.test_profile_created()
    returns trigger language plpgsql security definer set search_path='' as $$
    begin
      insert into public.perfiles(id,nombre_completo,telefono,cargo,rol)
      values(new.id,new.raw_user_meta_data->>'nombre_completo','8095550111','Supervisor','empleado');
      return new;
    end $$;
    create trigger zz_profile_created after insert on auth.users
    for each row execute function account_private.test_profile_created();
  `);
  await db.query('insert into auth.users values($1,$2)',[id(3),JSON.stringify({nombre_usuario:'nuevo.03',nombre_completo:'Nuevo Usuario'})]);
  assert.equal((await db.query('select nombre_usuario from perfiles where id=$1',[id(3)])).rows[0].nombre_usuario,'nuevo.03');
  await db.query("select set_config('test.uid',$1,false)",[id(1)]);
  await db.exec("select set_config('test.role','authenticated',false); select set_config('test.approved','true',false); set role authenticated");
  await db.query('select update_my_profile($1,$2,$3)',['ana.new','809-555-0188','Supervisor']);
  let profile = (await db.query('select * from perfiles where id=$1',[id(1)])).rows[0];
  assert.equal(profile.nombre_usuario,'ana.new');
  assert.equal(profile.nombre_completo,'Ana Pérez');
  assert.equal(profile.rol,'empleado');
  assert.equal((await db.query('select telefono from perfiles where id=$1',[id(2)])).rows[0].telefono,'8095550101');
  await assert.rejects(db.query("update perfiles set nombre_completo='Otro Nombre' where id=$1",[id(1)]),/no se puede modificar/);
  await assert.rejects(db.query('select update_my_profile($1,$2,$3)',['!','8095550188','Supervisor']),/usuario/);
  await assert.rejects(db.query('select update_my_profile($1,$2,$3)',['ana.new','1','Supervisor']),/teléfono/);
  await assert.rejects(db.query('select update_my_profile($1,$2,$3)',['ana.new','8095550188','Obsoleto']),/cargo/);
  await db.exec("select set_config('test.approved','false',false)");
  await assert.rejects(db.query('select update_my_profile($1,$2,$3)',['ana.new','8095550188','Supervisor']),/acceso/);
  await db.exec('reset role');
  assert.equal((await db.query('select raw_user_meta_data from auth.users where id=$1',[id(1)])).rows[0].raw_user_meta_data.nombre_usuario,'ana.new');
  console.log('PASS profile ownership, immutable full name, validation, approval, metadata and idempotency');
} finally {
  await db.close();
}
