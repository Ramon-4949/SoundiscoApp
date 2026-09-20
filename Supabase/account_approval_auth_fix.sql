-- Apply after account_access_setup.sql.
-- SounDisco uses administrator approval instead of an email-confirmation step.
begin;

create or replace function account_private.sync_approved_auth()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'aprobada' then
    update auth.users
    set email_confirmed_at = now()
    where id = new.user_id and email_confirmed_at is null
      and nullif(btrim(email), '') is not null;
  end if;
  return new;
end;
$$;
revoke all on function account_private.sync_approved_auth() from public,anon,authenticated;

drop trigger if exists account_approval_sync_auth on account_private.access;
create trigger account_approval_sync_auth after insert or update of estado
on account_private.access for each row
execute function account_private.sync_approved_auth();

-- Repair previously approved accounts without approving pending/rejected users.
update auth.users u
set email_confirmed_at = now()
from account_private.access a
where a.user_id = u.id and a.estado = 'aprobada'
  and u.email_confirmed_at is null and nullif(btrim(u.email), '') is not null;

notify pgrst,'reload schema';
commit;
