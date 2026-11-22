#!/usr/bin/env python3
"""Run real app query-shape suite against disposable managed test identities."""
import os,secrets,subprocess,uuid
from pathlib import Path
import requests
REF='yhnxzyjbamunwoyaccqi'
if os.environ.get('PULSE_TEST_PROJECT_REF')!=REF: raise SystemExit('test project guard required')
v=next(x.split('=',1)[1].strip().strip('"\'') for x in Path('/home/user/.secrets/env').read_text().splitlines() if x.startswith('SUPABASE_ACCESS_TOKEN='));base=f'https://{REF}.supabase.co';api=f'https://api.supabase.com/v1/projects/{REF}'
r=requests.get(api+'/api-keys',headers={'Authorization':'Bearer '+v},timeout=30);r.raise_for_status();keys={x['name']:x['api_key'] for x in r.json() if x.get('name') in ('anon','service_role')};service=keys['service_role'];h={'apikey':service,'Authorization':'Bearer '+service}
users=[];password=secrets.token_urlsafe(30)
try:
 for _ in range(2):
  email='pulse-test-'+uuid.uuid4().hex+'@example.invalid'
  r=requests.post(base+'/auth/v1/admin/users',headers=h,json={'email':email,'password':password,'email_confirm':True},timeout=30);r.raise_for_status();users.append((r.json()['id'],email))
 env=os.environ.copy();env.update(SUPABASE_URL=base,SUPABASE_ANON_KEY=keys['anon'],PULSE_TEST_EMAIL_A=users[0][1],PULSE_TEST_EMAIL_B=users[1][1],PULSE_TEST_PASSWORD=password)
 result=subprocess.run(['python3','supabase/tests/90_live_app_queries_test.py'],env=env,timeout=120);exit_code=result.returncode
finally:
 if users:
  ids=','.join("'"+str(uuid.UUID(u[0]))+"'" for u in users)
  q=f"delete from public.conversations c where exists(select 1 from public.conversation_members m where m.conversation_id=c.id and m.user_id in ({ids})) and not exists(select 1 from public.conversation_members m where m.conversation_id=c.id and m.user_id not in ({ids}))"
  r=requests.post(api+'/database/query',headers={'Authorization':'Bearer '+v},json={'query':q},timeout=30)
  print('cleanup test conversations',r.status_code,flush=True)
 for uid,email in users:
  r=requests.delete(base+'/auth/v1/admin/users/'+uid,headers=h,timeout=30);print('cleanup account',r.status_code,flush=True)
raise SystemExit(exit_code)
