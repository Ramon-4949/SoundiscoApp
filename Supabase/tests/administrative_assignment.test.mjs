import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const { PGlite } = await import(process.env.PGLITE_PATH);
const db = new PGlite();

const admin = '00000000-0000-0000-0000-000000000001';
const employee = '00000000-0000-0000-0000-000000000002';

await db.exec(`
  create role authenticated;
  create schema auth;

  create function auth.uid() returns uuid language sql as
    $$ select nullif(current_setting('test.uid', true), '')::uuid $$;

  create table perfiles (
    id uuid primary key,
    nombre_completo text,
    rol text
  );

  create function es_admin() returns boolean
  language sql stable
  as $$ select exists (
    select 1
    from public.perfiles
    where id = auth.uid() and lower(rol) = 'admin'
  ) $$;

  create table asignaciones (
    id uuid primary key,
    titulo text not null,
    tipo_flujo text not null,
    ubicacion text not null,
    nivel_prioridad text not null,
    instrucciones text,
    estado text not null,
    fecha_creacion timestamptz not null,
    fecha_limite timestamptz
  );

  create table asignacion_equipo (
    asignacion_id uuid references asignaciones(id),
    perfil_id uuid references perfiles(id)
  );

  create table hitos_itinerario (
    id uuid primary key,
    asignacion_id uuid references asignaciones(id),
    orden integer,
    descripcion text,
    hora_estimada time,
    completado boolean,
    estado_hito text,
    fecha_programada timestamptz
  );

  insert into perfiles values
    ('${admin}', 'Admin', 'admin'),
    ('${employee}', 'Empleado', 'tecnico');

  select set_config('test.uid', '${admin}', false);
`);

await db.exec(
  readFileSync(
    new URL('../administrative_assignment_location_fix.sql', import.meta.url),
    'utf8'
  )
);

const administrativePayload = {
  id: '10000000-0000-0000-0000-000000000001',
  titulo: 'Auditoria mensual',
  tipo_flujo: 'administrativa',
  nivel_prioridad: 'media',
  estado: 'pendiente',
  fecha_creacion: '2026-09-20T08:00:00Z'
};
const administrativeMilestones = [
  { id: '20000000-0000-0000-0000-000000000001', orden: 1, descripcion: 'Revisar documentos',
    fecha_programada: '2026-09-21T09:00:00Z', hora_estimada: '09:00:00' },
  { id: '20000000-0000-0000-0000-000000000002', orden: 2, descripcion: 'Entregar informe',
    fecha_programada: '2026-09-30T17:00:00Z', hora_estimada: '17:00:00' }
];

const created = await db.query(
  'select admin_create_assignment($1::jsonb, $2::uuid[], $3::jsonb) as id',
  [JSON.stringify(administrativePayload), [employee], JSON.stringify(administrativeMilestones)]
);

assert.equal(created.rows[0].id, administrativePayload.id);

const saved = (
  await db.query(
    'select tipo_flujo, ubicacion, fecha_limite from asignaciones where id = $1',
    [administrativePayload.id]
  )
).rows[0];

assert.equal(saved.tipo_flujo, 'administrativa');
assert.equal(saved.ubicacion, null);
assert.equal(saved.fecha_limite.toISOString(), '2026-09-30T17:00:00.000Z');
assert.equal((await db.query('select count(*)::int count from hitos_itinerario where asignacion_id = $1',
  [administrativePayload.id])).rows[0].count, 2);
console.log('PASS administrative assignment: saves without a location and with multiple milestones');

await assert.rejects(
  db.query(
    'select admin_create_assignment($1::jsonb, $2::uuid[], $3::jsonb)',
    [
      JSON.stringify({
        ...administrativePayload,
        id: '10000000-0000-0000-0000-000000000002',
        ubicacion: 'Oficina'
      }),
      [employee],
      JSON.stringify(administrativeMilestones.map((h, index) => ({ ...h,
        id: `20000000-0000-0000-0000-${String(index + 3).padStart(12, '0')}` })))
    ]
  ),
  /no deben incluir ubicacion/
);
console.log('PASS administrative assignment: rejects an accidental location');

await assert.rejects(
  db.query('select admin_create_assignment($1::jsonb, $2::uuid[], $3::jsonb)', [
    JSON.stringify({ ...administrativePayload, id: '10000000-0000-0000-0000-000000000004' }),
    [employee], '[]'
  ]), /al menos un hito/
);
console.log('PASS administrative assignment: requires an itinerary');

await assert.rejects(
  db.query(
    'select admin_create_assignment($1::jsonb, $2::uuid[], $3::jsonb)',
    [
      JSON.stringify({
        ...administrativePayload,
        id: '10000000-0000-0000-0000-000000000003',
        tipo_flujo: 'campo'
      }),
      [employee],
      '[]'
    ]
  ),
  /requieren ubicacion/
);
console.log('PASS field assignment: still requires a location');

await db.close();
