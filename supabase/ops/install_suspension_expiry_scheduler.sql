-- OPERATIONS SCRIPT, not an automatic migration.
-- Run only after security review, on a project where pg_cron is installed and
-- loaded, as the intended trusted job owner. Verify scheduler health afterwards.
-- Expected cadence is once per minute, not exact-to-the-second. Old build 57
-- needs this persisted status transition; access tokens/sessions are NOT revived.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    RAISE EXCEPTION 'pg_cron is not installed; scheduler has not been configured';
  END IF;
  IF to_regprocedure('public.release_expired_suspensions()') IS NULL THEN
    RAISE EXCEPTION 'release_expired_suspensions() is not installed';
  END IF;
  IF has_function_privilege('anon','public.release_expired_suspensions()','EXECUTE') OR
     has_function_privilege('authenticated','public.release_expired_suspensions()','EXECUTE') THEN
    RAISE EXCEPTION 'untrusted role can invoke expiry release';
  END IF;
END $$;
SELECT cron.schedule(
  'pulse-release-expired-suspensions',
  '* * * * *',
  'select public.release_expired_suspensions();'
);
COMMIT;
