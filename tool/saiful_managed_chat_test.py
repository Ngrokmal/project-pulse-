#!/usr/bin/env python3
"""Actual JWT/RLS integration, disposable user-designated Saiful project only."""
import os, secrets, uuid
from pathlib import Path
import requests
REF='yhnxzyjbamunwoyaccqi'
if os.environ.get('PULSE_TEST_PROJECT_REF') != REF: raise SystemExit('test project guard required')
token=next(x.split('=',1)[1].strip().strip('"\'') for x in Path('/home/user/.secrets/env').read_text().splitlines() if x.startswith('SUPABASE_ACCESS_TOKEN='))
mgmt={'Authorization':'Bearer '+token}; api=f'https://api.supabase.com/v1/projects/{REF}'; base=f'https://{REF}.supabase.co'
r=requests.get(api+'/api-keys',headers=mgmt,timeout=30);r.raise_for_status()
k={x['name']:x['api_key'] for x in r.json() if x.get('name') in ('anon','service_role')}; anon=k['anon'];service=k['service_role']
admin={'apikey':service,'Authorization':'Bearer '+service,'Content-Type':'application/json'}
users=[];groups=[]
def sql(q):
 r=requests.post(api+'/database/query',headers=mgmt,json={'query':q},timeout=30);r.raise_for_status();return r.json()
def request(method,path,headers,**kw): return requests.request(method,base+path,headers=headers,timeout=30,**kw)
def check(ok,msg):
 if not ok: raise AssertionError(msg)
 print('PASS',msg,flush=True)
try:
 for _ in range(3):
  email='pulse-test-'+uuid.uuid4().hex+'@example.invalid';pwd=secrets.token_urlsafe(30)
  r=request('POST','/auth/v1/admin/users',admin,json={'email':email,'password':pwd,'email_confirm':True});r.raise_for_status();uid=r.json()['id'];uuid.UUID(uid);users.append(uid)
  r=request('POST','/auth/v1/token?grant_type=password',{'apikey':anon},json={'email':email,'password':pwd});r.raise_for_status()
  users[-1]=(uid,{'apikey':anon,'Authorization':'Bearer '+r.json()['access_token'],'Content-Type':'application/json','Prefer':'return=representation'})
 a,b,c=[u[0] for u in users]; ah,bh,ch=[u[1] for u in users]; group=str(uuid.uuid4());direct=str(uuid.uuid4());groups=[group,direct]
 sql(f"insert into public.conversations(id,kind,title,created_by) values ('{group}','group','Managed test','{a}'),('{direct}','direct',null,'{a}'); insert into public.conversation_members(conversation_id,user_id,role) values ('{group}','{a}','owner'),('{group}','{b}','member'),('{direct}','{a}','member'),('{direct}','{b}','member'); insert into public.blocks(blocker,blocked) values ('{a}','{b}');")
 def send(h,conversation,sender):
  return request('POST','/rest/v1/messages',h,json={'conversation_id':conversation,'sender_id':sender,'body':'managed synthetic','client_id':str(uuid.uuid4())})
 r=send(ah,group,a);check(r.status_code in (200,201),'blocked user can send in shared group')
 r=request('GET',f'/rest/v1/messages?conversation_id=eq.{group}&select=id',bh);check(r.status_code==200 and len(r.json())==1,'blocked member sees group message')
 r=send(bh,group,b);check(r.status_code in (200,201),'other blocked member can send in group')
 r=send(ah,direct,a);check(r.status_code in (400,401,403),'private block prevents direct message')
 r=send(bh,direct,b);check(r.status_code in (400,401,403),'private block prevents reverse direct message')
 r=request('GET',f'/rest/v1/messages?conversation_id=eq.{group}&select=id',ch);check(r.status_code==200 and len(r.json())==0,'outsider cannot read group messages')
 sql(f"update public.account_status set status='suspended' where user_id='{a}'")
 r=send(ah,group,a);check(r.status_code in (400,401,403),'suspended account cannot send with old JWT')
finally:
 for g in groups:
  try: sql(f"delete from public.conversations where id='{g}'")
  except Exception: print('WARNING conversation cleanup failed',flush=True)
 for item in users:
  uid=item[0] if isinstance(item,tuple) else item
  try:
   r=request('DELETE','/auth/v1/admin/users/'+uid,admin)
   print('cleanup account',r.status_code,flush=True)
  except Exception: print('WARNING account cleanup failed',flush=True)
