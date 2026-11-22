#!/usr/bin/env python3
"""Managed pg_cron expiry smoke test, disposable test project only."""
import os,time,uuid
from pathlib import Path
import requests
REF='yhnxzyjbamunwoyaccqi'
if os.environ.get('PULSE_TEST_PROJECT_REF')!=REF: raise SystemExit('test project guard required')
v=next(x.split('=',1)[1].strip().strip('"\'') for x in Path('/home/user/.secrets/env').read_text().splitlines() if x.startswith('SUPABASE_ACCESS_TOKEN='));url=f'https://api.supabase.com/v1/projects/{REF}/database/query';h={'Authorization':'Bearer '+v}
def sql(q):
 r=requests.post(url,headers=h,json={'query':q},timeout=30)
 if not r.ok: raise RuntimeError(f'SQL HTTP {r.status_code}: {r.text[:800]}')
 return r.json()
a=str(uuid.uuid4()); b=str(uuid.uuid4()); started=time.time()
try:
 sql(f"insert into auth.users(id,email,raw_user_meta_data) values ('{a}','expiry-{a}@example.invalid','{{}}'),('{b}','expiry-{b}@example.invalid','{{}}');update public.account_status set status='suspended' where user_id='{a}';update public.account_status set status='banned' where user_id='{b}';update public.account_status set starts_at=now()-interval '2 minutes',ends_at=now()-interval '1 minute' where user_id in ('{a}','{b}');")
 print('Created two disposable expiry cases; awaiting scheduled execution.',flush=True)
 while time.time()-started < 125:
  time.sleep(10)
  rows=sql(f"select (select status::text from public.account_status where user_id='{a}') as suspended_status,(select status::text from public.account_status where user_id='{b}') as banned_status,(select count(*) from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname='pulse-release-expired-suspensions' and d.status='succeeded' and d.start_time > now()-interval '3 minutes') as successful_runs")
  state=rows[0]
  if state['suspended_status']=='active' and state['banned_status']=='banned' and state['successful_runs']>0:
   print('PASS scheduler released expired temporary suspension, preserved ban, recorded successful run',flush=True);break
 else: raise AssertionError('scheduler did not complete successfully within deadline: '+str(state))
finally:
 sql(f"delete from auth.users where id in ('{a}','{b}') and email in ('expiry-{a}@example.invalid','expiry-{b}@example.invalid')")
 print('cleaned disposable accounts',flush=True)
