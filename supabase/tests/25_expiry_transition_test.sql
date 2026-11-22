-- LOCAL SYNTHETIC ONLY. Tests the release function, not a scheduler.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE expiry_checks (label text,ok boolean) ON COMMIT DROP;
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('a4000000-0000-4000-8000-000000000004','expiry-old@example.invalid','{}'),
 ('a5000000-0000-4000-8000-000000000005','expiry-future@example.invalid','{}'),
 ('a6000000-0000-4000-8000-000000000006','expiry-ban@example.invalid','{}'),
 ('a7000000-0000-4000-8000-000000000007','expiry-review@example.invalid','{}');
UPDATE public.account_status SET status='suspended' WHERE user_id IN ('a4000000-0000-4000-8000-000000000004','a5000000-0000-4000-8000-000000000005');
UPDATE public.account_status SET starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' WHERE user_id='a4000000-0000-4000-8000-000000000004';
UPDATE public.account_status SET starts_at=now()-interval '2 days',ends_at=now()+interval '1 day' WHERE user_id='a5000000-0000-4000-8000-000000000005';
UPDATE public.account_status SET status='banned' WHERE user_id='a6000000-0000-4000-8000-000000000006';
UPDATE public.account_status SET starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' WHERE user_id='a6000000-0000-4000-8000-000000000006';
UPDATE public.account_status SET status='under_review' WHERE user_id='a7000000-0000-4000-8000-000000000007';
UPDATE public.account_status SET starts_at=now()-interval '2 days',ends_at=now()-interval '1 day' WHERE user_id='a7000000-0000-4000-8000-000000000007';
INSERT INTO expiry_checks VALUES
 ('authenticated cannot execute release',not has_function_privilege('authenticated','public.release_expired_suspensions()','EXECUTE')),
 ('anon cannot execute release',not has_function_privilege('anon','public.release_expired_suspensions()','EXECUTE')),
 ('future suspension restricted',not public.is_account_active('a5000000-0000-4000-8000-000000000005')),
 ('expired ban restricted',not public.is_account_active('a6000000-0000-4000-8000-000000000006')),
 ('expired review restricted',not public.is_account_active('a7000000-0000-4000-8000-000000000007'));
INSERT INTO expiry_checks SELECT 'release changes exactly one row',public.release_expired_suspensions()=1;
INSERT INTO expiry_checks SELECT 'expired status persisted as active',status='active' AND NOT suspended AND ends_at IS NULL FROM public.account_status WHERE user_id='a4000000-0000-4000-8000-000000000004';
INSERT INTO expiry_checks SELECT 'future suspension unchanged',status='suspended' AND suspended FROM public.account_status WHERE user_id='a5000000-0000-4000-8000-000000000005';
INSERT INTO expiry_checks SELECT 'ban unchanged',status='banned' AND suspended FROM public.account_status WHERE user_id='a6000000-0000-4000-8000-000000000006';
INSERT INTO expiry_checks SELECT 'review unchanged',status='under_review' AND suspended FROM public.account_status WHERE user_id='a7000000-0000-4000-8000-000000000007';
INSERT INTO expiry_checks SELECT 'release idempotent',public.release_expired_suspensions()=0;
SELECT * FROM expiry_checks ORDER BY label;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM expiry_checks WHERE NOT ok) THEN RAISE EXCEPTION 'expiry transition test failed'; END IF; END $$;
ROLLBACK;
