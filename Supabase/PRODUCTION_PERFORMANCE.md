# Mantenimiento y rendimiento

## Ejecucion

Ejecutar el contenido completo de estos archivos, en orden, desde SQL Editor como postgres:

1. `production_performance.sql`: indices y funcion de limpieza.
2. `admin_dashboard_queries.sql`: resumen agregado y paginas del Home.
3. `notification_retention_cron.sql`: extension y tarea semanal.

No ejecutar de nuevo migraciones antiguas despues de estas sin revisar sus cambios.
No se modifican las reglas de SLA ni el worker de Render.

Los CREATE INDEX normales pueden bloquear escrituras. Ejecutar en horario de poco uso.
El lock_timeout cancela la primera migracion si no consigue el bloqueo en cinco segundos;
si ocurre, reintentar en otro momento. Para tablas ya grandes, crear cada indice usando
CREATE INDEX CONCURRENTLY individualmente, fuera de BEGIN/COMMIT.
IF NOT EXISTS evita repetir nombres, no detecta indices equivalentes con otro nombre:
revisar pg_indexes antes si se han creado indices manuales.

## Cron y comprobacion

La extension tambien puede habilitarse desde Integrations > Cron.
No exponer cron ni notification_private a la API ni otorgar permisos al cliente.
El job usa el propietario que lo crea: ejecutarlo como postgres.

```sql
select current_setting('cron.timezone', true);
select jobid, jobname, schedule, active
from cron.job where jobname = 'soundisco-purge-sent-outbox';

select count(*) as envios_elegibles
from notification_private.outbox
where sent_at < now() - interval '30 days'
  and (leased_until is null or leased_until < now());

select d.status, d.start_time, d.end_time, d.return_message
from cron.job_run_details d
join cron.job j on j.jobid = d.jobid
where j.jobname = 'soundisco-purge-sent-outbox'
order by d.start_time desc limit 10;
```

El horario 0 7 * * 0 corresponde al domingo a las 03:00 de Santo Domingo
cuando cron.timezone es GMT/UTC (valor predeterminado). Si fue cambiado,
adaptar el horario sin cambiar globalmente la zona de otros jobs.
Antes de la primera ejecucion no habra resultados en job_run_details.
La limpieza elimina solo envios exitosos hace mas de 30 dias; no usa la fecha
de creacion ni elimina intentos agotados, pendientes o historial de la app.
Tiene un timeout de cinco minutos: si falla por volumen, revisar y ejecutar
una limpieza inicial por lotes. No desactivar autovacuum ni usar VACUUM FULL
como tarea rutinaria.

## Contrato para iOS

La RPC existente admin_employee_performance(p_month,p_offset,p_employee)
ya devuelve agregados por empleado, con paginas de 100; no descarga todas
las confirmaciones/notas. Se conserva sin cambios.

AdminDashboardViewModel consume estas RPC y conserva en memoria solo las
paginas solicitadas:

- admin_dashboard_summary(): un objeto con total, unidades_asignadas,
  unidades_activas, completadas, vencidas y tasa_entrega (0 a 100).
- admin_assignments_page(p_offset: 0,p_limit: 50,p_estado: 'pendientes',p_busqueda: '').
  Devuelve items, has_more y next_offset. Limite maximo: 100.
  Filtros: todas, pendientes, vencidas, completadas. Pendientes incluye en_curso.
- Cada pagina incluye los hitos y responsables de esas asignaciones solamente,
  para que las tarjetas y el detalle conserven su informacion completa.
- Cargar la siguiente pagina solo al acercarse al final; reiniciar offset al
  cambiar filtro o refrescar. No recorrer todas las paginas al entrar al Home.
- No calcular metricas, totales ni graficas con una pagina. El resumen incluye
  el total y la serie de creaciones de los ultimos siete dias. La busqueda de
  titulo, ubicacion o responsable se ejecuta en el servidor.

Las RPC requieren sesion admin: desde SQL Editor sin JWT daran
"Solo administradores", intencionalmente. No quitar la comprobacion para probar.
Offset puede desplazar filas entre paginas ante inserciones concurrentes:
deduplicar por id y reiniciar tras refrescar. Para historiales muy profundos,
evolucionar a cursor (fecha_creacion,id).

Los indices aceleran accesos adecuados; COUNT sobre todo el historial aun
requiere recorrer datos. Medir planes EXPLAIN (ANALYZE, BUFFERS) y latencia
con volumen real antes de agregar mas indices o vistas materializadas.

## Pruebas

production_performance.test.mjs valida repeticion de migraciones, 1005 filas,
paginacion limitada y estable, estados, permisos y retencion. PGlite no ejecuta
pg_cron: verificar el job real con las consultas anteriores despues del despliegue.
