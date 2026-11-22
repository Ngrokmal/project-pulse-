#!/usr/bin/env python3
"""Runs real Supabase JWT + Dart Hive journal catchup in designated test project."""
import os,secrets,subprocess,uuid
from pathlib import Path
import requests
REF='yhnxzyjbamunwoyaccqi'
if os.environ.get('PULSE_TEST_PROJECT_REF')!=REF:raise SystemExit('test project guard required')
token=next(x.split('=',1)[1].strip().strip('"\'') for x in Path('/home/user/.secrets/env').read_text().splitlines() if x.startswith('SUPABASE_ACCESS_TOKEN='));api=f'https://api.supabase.com/v1/projects/{REF}';base=f'https://{REF}.supabase.co';mgmt={'Authorization':'Bearer '+token}
r=requests.get(api+'/api-keys',headers=mgmt,timeout=30);r.raise_for_status();keys={x['name']:x['api_key'] for x in r.json() if x.get('name') in ('anon','service_role')};service=keys['service_role'];admin={'apikey':service,'Authorization':'Bearer '+service};uid=None;conv=None

def sql(q):
 r=requests.post(api+'/database/query',headers=mgmt,json={'query':q},timeout=45)
 if not r.ok:raise RuntimeError('SQL failed HTTP '+str(r.status_code)+' '+r.text[:500])
 return r.json()
try:
 email='pulse-test-'+uuid.uuid4().hex+'@example.invalid';password=secrets.token_urlsafe(30)
 r=requests.post(base+'/auth/v1/admin/users',headers=admin,json={'email':email,'password':password,'email_confirm':True},timeout=30);r.raise_for_status();uid=r.json()['id'];uuid.UUID(uid);conv=str(uuid.uuid4())
 sql(f"insert into public.conversations(id,kind,title,created_by) values ('{conv}','group','Journal integration','{uid}');insert into public.conversation_members(conversation_id,user_id,role) values ('{conv}','{uid}','owner');insert into public.messages(conversation_id,sender_id,body,client_id) select '{conv}','{uid}','synthetic '||i,'managed-journal-'||i from generate_series(1,125) i;")
 env=os.environ.copy();env.update(PULSE_MANAGED_JOURNAL_TEST='1',PULSE_TEST_URL=base,PULSE_TEST_ANON=keys['anon'],PULSE_TEST_USER=email,PULSE_TEST_PASSWORD=password,PULSE_TEST_CONVERSATION=conv)
 rc=subprocess.run(['/home/user/flutter-sdk-live/flutter/bin/flutter','test','--no-pub','--dart-define=PULSE_JOURNAL_SYNC=true','test/managed_journal_integration_test.dart','-r','expanded'],env=env,timeout=120).returncode
finally:
 if conv:
  try:sql(f"delete from public.conversations where id='{conv}'");print('cleanup conversation',flush=True)
  except Exception:print('WARNING conversation cleanup failed',flush=True)
 if uid:
  try:r=requests.delete(base+'/auth/v1/admin/users/'+uid,headers=admin,timeout=30);print('cleanup account',r.status_code,flush=True)
  except Exception:print('WARNING account cleanup failed',flush=True)
raise SystemExit(rc)
