#!/usr/bin/env python3
"""Disposable actual JWT admin and suspension integration; designated test project only."""
import os,secrets,uuid
from pathlib import Path
import requests
REF='yhnxzyjbamunwoyaccqi'
if os.environ.get('PULSE_TEST_PROJECT_REF') != REF: raise SystemExit('test project guard required')
token=next(x.split('=',1)[1].strip().strip('"\'') for x in Path('/home/user/.secrets/env').read_text().splitlines() if x.startswith('SUPABASE_ACCESS_TOKEN='))
mgmt={'Authorization':'Bearer '+token};api=f'https://api.supabase.com/v1/projects/{REF}';base=f'https://{REF}.supabase.co'
r=requests.get(api+'/api-keys',headers=mgmt,timeout=30);r.raise_for_status();keys={x['name']:x['api_key'] for x in r.json() if x.get('name') in ('anon','service_role')};anon=keys['anon'];service=keys['service_role']
admin_h={'apikey':service,'Authorization':'Bearer '+service,'Content-Type':'application/json'}
users=[];conversation=None;code='pulse_test_'+uuid.uuid4().hex[:16]
def sql(q):
 r=requests.post(api+'/database/query',headers=mgmt,json={'query':q},timeout=30);r.raise_for_status();return r.json()
def req(method,path,headers,**kwargs):return requests.request(method,base+path,headers=headers,timeout=30,**kwargs)
def check(ok,label):
 if not ok:raise AssertionError(label)
 print('PASS',label,flush=True)
def rpc(headers,name,payload):return req('POST','/rest/v1/rpc/'+name,headers,json=payload)
try:
 for _ in range(2):
  email='pulse-test-'+uuid.uuid4().hex+'@example.invalid';password=secrets.token_urlsafe(30)
  r=req('POST','/auth/v1/admin/users',admin_h,json={'email':email,'password':password,'email_confirm':True});r.raise_for_status();uid=r.json()['id'];uuid.UUID(uid);users.append({'id':uid,'email':email,'password':password})
  r=req('POST','/auth/v1/token?grant_type=password',{'apikey':anon},json={'email':email,'password':password});r.raise_for_status();session=r.json();users[-1]['refresh']=session['refresh_token'];users[-1]['headers']={'apikey':anon,'Authorization':'Bearer '+session['access_token'],'Content-Type':'application/json','Prefer':'return=representation'}
 a,b=users;aid=a['id'];bid=b['id'];ah=a['headers'];bh=b['headers'];conversation=str(uuid.uuid4())
 sql(f"insert into public.pulse_admin_accounts(user_id) values ('{aid}');insert into public.conversations(id,kind,created_by) values ('{conversation}','direct','{aid}');insert into public.conversation_members(conversation_id,user_id,role) values ('{conversation}','{aid}','member'),('{conversation}','{bid}','member');")
 r=rpc(bh,'pulse_admin_list_users',{'p_query':'','p_limit':25,'p_offset':0});check(r.status_code in (400,401,403),'ordinary user cannot list accounts')
 r=rpc(ah,'pulse_admin_list_users',{'p_query':b['email'],'p_limit':25,'p_offset':0});check(r.ok and len(r.json())==1 and r.json()[0]['id']==bid,'admin can search account')
 args={'p_user':bid,'p_control':'send_messages','p_enabled':False}
 r=rpc(bh,'pulse_admin_set_user_control',args);check(r.status_code in (400,401,403),'ordinary user cannot change control')
 r=rpc(ah,'pulse_admin_set_user_control',args);check(r.ok,'admin disables message send')
 payload={'conversation_id':conversation,'sender_id':bid,'body':'synthetic','client_id':str(uuid.uuid4())}
 r=req('POST','/rest/v1/messages',bh,json=payload);check(not r.ok,'disabled message send enforced on API')
 args['p_enabled']=True;r=rpc(ah,'pulse_admin_set_user_control',args);check(r.ok,'admin enables message send')
 r=req('POST','/rest/v1/messages',bh,json=payload);check(r.status_code in (200,201),'re-enabled message can be sent')
 args={'p_user':bid,'p_control':'start_calls','p_enabled':False};r=rpc(ah,'pulse_admin_set_user_control',args);check(r.ok,'admin disables call start')
 r=rpc(bh,'start_call',{'p_conversation':conversation,'p_kind':'audio'});check(not r.ok and 'call_start_disabled' in r.text,'disabled call blocked by server')
 args['p_enabled']=True;r=rpc(ah,'pulse_admin_set_user_control',args);check(r.ok,'admin enables call start')
 r=rpc(ah,'pulse_admin_set_error_message',{'p_code':code,'p_message':'Synthetic test message'});check(r.ok,'admin edits server error text')
 r=rpc(bh,'pulse_error_message',{'p_code':code});check(r.ok and r.json()=='Synthetic test message','ordinary user reads server error text')
 r=rpc(ah,'pulse_admin_set_suspension',{'p_user':bid,'p_suspend':True,'p_ends_at':None,'p_reason':'managed test'});check(r.ok,'admin suspends user')
 r=req('POST','/rest/v1/messages',bh,json={**payload,'client_id':str(uuid.uuid4())});check(not r.ok,'suspended user cannot send using old access token')
 r=req('POST','/auth/v1/token?grant_type=refresh_token',{'apikey':anon},json={'refresh_token':b['refresh']});check(not r.ok,'suspension revokes refresh session')
 r=rpc(ah,'pulse_admin_set_suspension',{'p_user':bid,'p_suspend':False,'p_ends_at':None,'p_reason':None});check(r.ok,'admin releases temporary suspension')
finally:
 if conversation:
  try:sql(f"delete from public.conversations where id='{conversation}'")
  except Exception:print('WARNING conversation cleanup failed',flush=True)
 try:sql(f"delete from public.pulse_error_messages where code='{code}'")
 except Exception:print('WARNING error text cleanup failed',flush=True)
 for u in users:
  try:
   r=req('DELETE','/auth/v1/admin/users/'+u['id'],admin_h);print('cleanup account',r.status_code,flush=True)
  except Exception:print('WARNING account cleanup failed',flush=True)
