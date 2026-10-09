begin;

alter table public.notificaciones_app
  add column if not exists payload jsonb not null default '{}'::jsonb;

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
      values(new.hito_id,new.usuario_id,due,due-interval '20 minutes')
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
      select new.id,c.usuario_id,new.fecha_programada,new.fecha_programada-interval '20 minutes'
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
  select c.hito_id,c.usuario_id,h.fecha_programada,h.fecha_programada-interval '20 minutes'
  from public.hitos_colaboradores c join public.hitos_itinerario h on h.id=c.hito_id
  where c.confirmado_at is null and h.fecha_programada is not null
  on conflict(hito_id,usuario_id) do nothing;

create or replace function public.generate_notification_reminders()
returns void language plpgsql security definer set search_path='' as $$
declare
  r record;
  tick timestamptz := clock_timestamp();
  phase text;
  minutes_before integer;
  alarm boolean;
  following timestamptz;
  overdue_slot bigint;
begin
  if not pg_try_advisory_xact_lock(81420931) then return; end if;
  for r in
    select s.*,h.asignacion_id,h.descripcion
    from notification_private.milestone_reminders s
    join public.hitos_colaboradores c on c.hito_id=s.hito_id and c.usuario_id=s.usuario_id
    join public.hitos_itinerario h on h.id=s.hito_id
    where s.next_reminder_at<=tick and c.confirmado_at is null and h.fecha_programada=s.due_at
    order by s.next_reminder_at,s.hito_id,s.usuario_id
    limit 500 for update of h,c,s skip locked
  loop
    if tick>=r.due_at then
      overdue_slot:=floor(extract(epoch from (tick-r.due_at))/600)::bigint;
      phase:='overdue:' || overdue_slot::text;
      alarm:=true;
      following:=r.due_at + (overdue_slot+1)*interval '10 minutes';
    else
      minutes_before:=case
        when tick>=r.due_at-interval '5 minutes' then 5
        when tick>=r.due_at-interval '10 minutes' then 10
        when tick>=r.due_at-interval '15 minutes' then 15
        else 20 end;
      phase:='before:' || minutes_before::text;
      alarm:=minutes_before=5;
      following:=r.due_at-(minutes_before-5)*interval '1 minute';
    end if;
    insert into public.notificaciones_app(id,perfil_id,titulo,mensaje,leida,fecha_creacion,
      tipo,destino_tipo,destino_id,evento_key,payload)
      values(gen_random_uuid(),r.usuario_id,
        case when alarm then 'Alarma de Hito' else 'Recordatorio de Hito' end,
        case when tick>=r.due_at then 'El hito ' || coalesce(r.descripcion,'pendiente') || ' está vencido. Confírmalo cuanto antes.'
          else 'Confirma el hito ' || coalesce(r.descripcion,'pendiente') || ' antes de su vencimiento: ' ||
            to_char(r.due_at at time zone 'America/Santo_Domingo','DD/MM/YYYY HH24:MI') || '.' end,
        false,tick,'recordatorio','asignacion',r.asignacion_id,
        'milestone-reminder:' || r.generation::text || ':' || phase,
        jsonb_build_object('is_alarm',alarm,'hito_id',r.hito_id,'due_at',r.due_at,'reminder_phase',phase))
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
