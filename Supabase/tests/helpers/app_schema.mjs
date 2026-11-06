import { readFileSync } from 'node:fs';

export async function appDatabase(modulePath) {
  const { PGlite } = await import(modulePath);
  const { btree_gist } = await import(new URL('./contrib/btree_gist.js', modulePath).href);
  const db = new PGlite({ extensions: { btree_gist } });
  const schema = JSON.parse(readFileSync(new URL('../fixtures/admin_ownership_schema.json', import.meta.url), 'utf8'));
  const quote = name => `"${name.replaceAll('"', '""')}"`;
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
  await db.exec(`grant select on all tables in schema public to authenticated; set check_function_bodies=on;`);
  return db;
}

export async function login(db, uid) {
  await db.exec('reset role');
  await db.query("select set_config('test.uid',$1,false),set_config('test.role','authenticated',false)", [uid]);
  await db.exec('set role authenticated');
}

export async function maintenance(db) {
  await db.exec('reset role');
  await db.exec("select set_config('test.uid','',false),set_config('test.role','',false)");
}
