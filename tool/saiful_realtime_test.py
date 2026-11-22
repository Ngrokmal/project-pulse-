#!/usr/bin/env python3
"""Managed Realtime + RLS + journal replay; only disposable test project."""
import json,os,secrets,time,uuid
from pathlib import Path
import requests,websocket
REF='yhnxzyjbamunwoyaccqi'
if os.environ.get('PULSE_TEST_PROJECT_REF')!=REF:raise SystemExit('test project guard required')
v=next(x.split('=',1)[1].strip().strip('"\'') for x in Path('/home/user/.secrets/env').read_text().splitlines() if x.startswith('SUPABASE_ACCESS_TOKEN='));api=f'https://api.supabase.com/v1/projects/{REF}';base=f'https://{REF}.supabase.co';mgmt={'Authorization':'Bearer '+v}
r=requests.get(api+'/api-keys',headers=mgmt,timeout=30);r.raise_for_status();keys={x['name']:x['api_key'] for x in r.json() if x.get('name') in ('anon','service_role')};anon=keys['anon'];service=keys['service_role'];admin={'apikey':service,'Authorization':'Bearer '+service};users=[];sockets=[];conv=None
def sql(q):
 r=requests.post(api+'/database/query',headers=mgmt,json={'query':q},timeout=30);r.raise_for_status();return r.json()
def check(ok,msg):
 if not ok:raise AssertionError(msg)
 print('PASS',msg,flush=True)
def sub(user,label):
 w=websocket.create_connection(f'wss://{REF}.supabase.co/realtime/v1/websocket?apikey={anon}&vsn=1.0.0',timeout=10);sockets.append(w);topic='realtime:rt_'+label+'_'+uuid.uuid4().hex
 w.send(json.dumps({'topic':topic,'event':'phx_join','payload':{'config':{'broadcast':{'self':False},'presence':{'key':''},'postgres_changes':[{'event':'INSERT','schema':'public','table':'messages','filter':'conversation_id=eq.'+conv}]},'access_token':user['jwt']},'ref':'1'}))
 while True:
  m=json.loads(w.recv())
  if m.get('event')=='phx_reply' and m.get('ref')=='1':
   check(m.get('payload',{}).get('status')=='ok',label+' joined channel');break
 while True:
  m=json.loads(w.recv())
  if m.get('event')=='system' and m.get('payload',{}).get('extension')=='postgres_changes':
   check(m.get('payload',{}).get('status')=='ok',label+' postgres subscription ready');break
 return w
def event(w,body,seconds):
 deadline=time.monotonic()+seconds
 while time.monotonic()<deadline:
  w.settimeout(max(.1,deadline-time.monotonic()))
  try:m=json.loads(w.recv())
  except websocket.WebSocketTimeoutException:return False
  print('realtime frame',m.get('event'), 'payload keys',list(m.get('payload',{}).keys()),flush=True)
  if m.get('event')=='postgres_changes' and m.get('payload',{}).get('data',{}).get('record',{}).get('body')==body:return True
 return False
def send(user,body):
 r=requests.post(base+'/rest/v1/messages',headers=user['headers'],json={'conversation_id':conv,'sender_id':user['id'],'body':body,'client_id':str(uuid.uuid4())},timeout=30);r.raise_for_status()
try:
 for _ in range(3):
  email='pulse-test-'+uuid.uuid4().hex+'@example.invalid';password=secrets.token_urlsafe(30)
  r=requests.post(base+'/auth/v1/admin/users',headers=admin,json={'email':email,'password':password,'email_confirm':True},timeout=30);r.raise_for_status();uid=r.json()['id'];uuid.UUID(uid);users.append({'id':uid})
  r=requests.post(base+'/auth/v1/token?grant_type=password',headers={'apikey':anon},json={'email':email,'password':password},timeout=30);r.raise_for_status();jwt=r.json()['access_token'];users[-1].update(jwt=jwt,headers={'apikey':anon,'Authorization':'Bearer '+jwt,'Content-Type':'application/json'})
 a,b,c=users;conv=str(uuid.uuid4());sql(f"insert into public.conversations(id,kind,title,created_by) values ('{conv}','group','Realtime test','{a['id']}');insert into public.conversation_members(conversation_id,user_id,role) values ('{conv}','{a['id']}','owner'),('{conv}','{b['id']}','member')")
 member=sub(b,'member');outsider=sub(c,'outsider');send(a,'rt-visible')
 check(event(member,'rt-visible',12),'member receives realtime insert')
 check(not event(outsider,'rt-visible',4),'outsider receives no realtime message')
 def mark(user,revision):
  return requests.post(base+'/rest/v1/rpc/pulse_mark_read_revision',headers=user['headers'],json={'p_conversation':conv,'p_revision':revision},timeout=30)
 check(mark(b,1).ok,'member acknowledges only caught-up revision')
 r=requests.get(base+'/rest/v1/conversation_members',headers=a['headers'],params={'conversation_id':'eq.'+conv,'user_id':'eq.'+b['id'],'select':'last_read_revision'},timeout=30)
 check(r.ok and r.json()[0]['last_read_revision']==1,'peer can read revision receipt for seen UI')
 check(not mark(c,1).ok,'outsider cannot acknowledge')
 check(not mark(b,999).ok,'future revision rejected')
 sql(f"update public.account_status set status='suspended' where user_id='{b['id']}'")
 send(a,'rt-suspended')
 check(not event(member,'rt-suspended',5),'suspended member receives no new realtime message')
 r=requests.post(base+'/rest/v1/rpc/pulse_message_changes_since',headers=b['headers'],json={'p_conversation':conv,'p_after':0,'p_limit':100},timeout=30)
 check(not r.ok,'suspended member denied journal access')
 check(not mark(b,1).ok,'suspended member cannot acknowledge')
 status=sql(f"select last_read_revision from public.conversation_members where conversation_id='{conv}' and user_id='{b['id']}'")
 check(status[0]['last_read_revision']==1,'new message after acknowledgement is not acknowledged')
 sql(f"update public.account_status set status='active' where user_id='{b['id']}'")
 member.close();send(a,'rt-offline')
 r=requests.post(base+'/rest/v1/rpc/pulse_message_changes_since',headers=b['headers'],json={'p_conversation':conv,'p_after':0,'p_limit':100},timeout=30);r.raise_for_status();rows=r.json()
 check(any(x.get('message',{}).get('body')=='rt-offline' for x in rows if x.get('message')),'journal retrieves message missed during disconnection')
 r=requests.post(base+'/rest/v1/rpc/pulse_message_changes_since',headers=c['headers'],json={'p_conversation':conv,'p_after':0,'p_limit':100},timeout=30);check(not r.ok,'outsider denied journal access')
finally:
 for w in sockets:
  try:w.close()
  except Exception:pass
 if conv:
  try:sql(f"delete from public.conversations where id='{conv}'")
  except Exception:print('WARNING conversation cleanup failed',flush=True)
 for user in users:
  try:r=requests.delete(base+'/auth/v1/admin/users/'+user['id'],headers=admin,timeout=30);print('cleanup account',r.status_code,flush=True)
  except Exception:print('WARNING account cleanup failed',flush=True)
