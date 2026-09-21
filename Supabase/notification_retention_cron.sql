-- Run as postgres after production_performance.sql.
create extension if not exists pg_cron with schema pg_catalog;

-- Default cron timezone is GMT/UTC: Sunday 07:00 UTC = 03:00 Santo Domingo.
-- A named schedule updates the existing job for this owner on repeated execution.
select cron.schedule(
  'soundisco-purge-sent-outbox',
  '0 7 * * 0',
  $job$set statement_timeout = '5min'; select notification_private.purge_sent_outbox();$job$
);

select jobid, jobname, schedule, active from cron.job
where jobname = 'soundisco-purge-sent-outbox';
