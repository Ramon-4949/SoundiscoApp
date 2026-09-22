-- Ejecutar solo despues de desplegar en Render una llave APNs Production valida.
-- Reactiva exclusivamente los avisos que Apple rechazo por usar una llave del
-- entorno equivocado. No modifica avisos enviados ni dispositivos Sandbox.

begin;

update notification_private.outbox as o
set attempts = 0,
    next_attempt = now(),
    leased_until = null,
    lease_id = null,
    last_error = null
from notification_private.devices as d
where d.installation = o.installation
  and d.environment = 'production'
  and o.sent_at is null
  and o.last_error = 'BadEnvironmentKeyInToken';

commit;

select count(*) as pushes_production_reactivados
from notification_private.outbox as o
join notification_private.devices as d
  on d.installation = o.installation
where d.environment = 'production'
  and o.sent_at is null
  and o.next_attempt <= now();
