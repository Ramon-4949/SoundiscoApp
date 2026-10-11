begin;

select pg_advisory_xact_lock(81420931);

alter table public.notificaciones_app
  add column if not exists payload jsonb not null default '{}'::jsonb;

update public.notificaciones_app
set payload=jsonb_set(payload,'{is_alarm}','false'::jsonb),
  titulo=case when titulo='Alarma de Hito' then 'Recordatorio de Hito' else titulo end
where tipo='recordatorio' and destino_tipo='asignacion'
  and (payload->'is_alarm'='true'::jsonb or titulo='Alarma de Hito');

create table if not exists notification_private.milestone_reminders (
  hito_id uuid not null,
  usuario_id uuid not null,
  due_at timestamptz not null,
  next_reminder_at timestamptz not null,
  last_reminder_sent_at timestamptz,
  last_phase text,
  generation uuid not null default gen_random_uuid(),
  primary key(hito_id,usuario_id),
  foreign key(hito_id,usuario_id) references public.hitos_colaboradores(hito_id,usuario_id) on delete cascade
);

alter table notification_private.milestone_reminders
  add column if not exists schedule_version integer not null default 1;
alter table notification_private.milestone_reminders alter column schedule_version set default 2;

update notification_private.milestone_reminders
set next_reminder_at=case
    when now()<=due_at+interval '15 minutes' then due_at+interval '15 minutes'
    when now()<=due_at+interval '30 minutes' then due_at+interval '30 minutes'
    when now()<=due_at+interval '60 minutes' then due_at+interval '60 minutes'
    else 'infinity'::timestamptz end,
  last_phase=null,schedule_version=2
where schedule_version<>2;

do $$
declare queue_schema text;
begin
  foreach queue_schema in array array['notification_private','android_push_private'] loop
    if to_regclass(format('%I.outbox',queue_schema)) is not null then
      execute format('delete from %I.outbox o using public.notificaciones_app n
        where o.notification_id=n.id and o.sent_at is null
          and n.tipo=''recordatorio'' and n.destino_tipo=''asignacion''
          and n.payload->>''reminder_schedule'' is distinct from ''overdue-three-v2''',queue_schema);
    end if;
  end loop;
end;
$$;

alter table notification_private.milestone_reminders enable row level security;
revoke all on notification_private.milestone_reminders from public,anon,authenticated;
create index if not exists milestone_reminders_next
  on notification_private.milestone_reminders(next_reminder_at,hito_id,usuario_id);

create or replace function notification_private.sync_member_reminder()
returns trigger language plpgsql security definer set search_path='' as $$
declare due timestamptz;
begin
  select fecha_programada into due from public.hitos_itinerario where id=new.hito_id;
  if new.confirmado_at is not null or due is null then
    delete from notification_private.milestone_reminders
      where hito_id=new.hito_id and usuario_id=new.usuario_id;
  else
    insert into notification_private.milestone_reminders(hito_id,usuario_id,due_at,next_reminder_at)
      values(new.hito_id,new.usuario_id,due,due+interval '15 minutes')
      on conflict(hito_id,usuario_id) do nothing;
  end if;
  return new;
end;
$$;

create or replace function notification_private.sync_milestone_reminders()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.fecha_programada is not distinct from old.fecha_programada then return new; end if;
  delete from notification_private.milestone_reminders where hito_id=new.id;
  if new.fecha_programada is not null then
    insert into notification_private.milestone_reminders(hito_id,usuario_id,due_at,next_reminder_at)
      select new.id,c.usuario_id,new.fecha_programada,new.fecha_programada+interval '15 minutes'
      from public.hitos_colaboradores c where c.hito_id=new.id and c.confirmado_at is null;
  end if;
  return new;
end;
$$;

revoke all on function notification_private.sync_member_reminder(),
  notification_private.sync_milestone_reminders() from public,anon,authenticated;

drop trigger if exists notification_member_reminder on public.hitos_colaboradores;
create trigger notification_member_reminder after insert or update of confirmado_at
  on public.hitos_colaboradores for each row execute function notification_private.sync_member_reminder();
drop trigger if exists notification_milestone_reminders on public.hitos_itinerario;
create trigger notification_milestone_reminders after update of fecha_programada
  on public.hitos_itinerario for each row execute function notification_private.sync_milestone_reminders();

insert into notification_private.milestone_reminders(hito_id,usuario_id,due_at,next_reminder_at)
  select c.hito_id,c.usuario_id,h.fecha_programada,h.fecha_programada+interval '15 minutes'
  from public.hitos_colaboradores c join public.hitos_itinerario h on h.id=c.hito_id
  where c.confirmado_at is null and h.fecha_programada is not null
  on conflict(hito_id,usuario_id) do nothing;

create or replace function public.generate_notification_reminders()
returns void language plpgsql security definer set search_path='' as $$
declare
  r record;
  tick timestamptz := clock_timestamp();
  phase text;
  minutes_after integer;
  following timestamptz;
begin
  if not pg_try_advisory_xact_lock(81420931) then return; end if;
  for r in
    select s.*,h.asignacion_id,h.descripcion
    from notification_private.milestone_reminders s
    join public.hitos_colaboradores c on c.hito_id=s.hito_id and c.usuario_id=s.usuario_id
    join public.hitos_itinerario h on h.id=s.hito_id
    join public.asignaciones a on a.id=h.asignacion_id
    where s.next_reminder_at<=tick and c.confirmado_at is null and h.fecha_programada=s.due_at
    order by s.next_reminder_at,s.hito_id,s.usuario_id
    limit 500 for update of h,c,s skip locked
  loop
    minutes_after:=case
      when tick>=r.due_at+interval '60 minutes' then 60
      when tick>=r.due_at+interval '30 minutes' then 30
      else 15 end;
    phase:='after:' || minutes_after::text;
    following:=case minutes_after
      when 15 then r.due_at+interval '30 minutes'
      when 30 then r.due_at+interval '60 minutes'
      else 'infinity'::timestamptz end;
    insert into public.notificaciones_app(id,perfil_id,titulo,mensaje,leida,fecha_creacion,
      tipo,destino_tipo,destino_id,evento_key,payload)
      values(gen_random_uuid(),r.usuario_id,
        'Recordatorio de Hito',
        'El hito ' || coalesce(r.descripcion,'pendiente') || ' está vencido. Confírmalo cuanto antes.',
        false,tick,'recordatorio','asignacion',r.asignacion_id,
        'milestone-reminder:' || r.generation::text || ':' || phase,
        jsonb_build_object('is_alarm',false,'hito_id',r.hito_id,'due_at',r.due_at,
          'reminder_phase',phase,'reminder_schedule','overdue-three-v2'))
      on conflict(perfil_id,evento_key) do nothing;
    update notification_private.milestone_reminders
      set next_reminder_at=following,last_reminder_sent_at=tick,last_phase=phase
      where hito_id=r.hito_id and usuario_id=r.usuario_id;
  end loop;
end;
$$;

revoke all on function public.generate_notification_reminders() from public,anon,authenticated;
grant execute on function public.generate_notification_reminders() to service_role;

notify pgrst,'reload schema';
commit;
