#!/usr/bin/env python3
"""Disposable managed integration test; never target production. No tokens logged."""
import json, os, secrets, sys, uuid
from pathlib import Path
import requests

REF='yhnxzyjbamunwoyaccqi'  # User-designated test project only.
if os.environ.get('PULSE_TEST_PROJECT_REF') != REF:
    raise SystemExit('Explicit test project guard required')
config=Path('/home/user/.secrets/env').read_text().splitlines()
token=next(x.split('=',1)[1].strip().strip('"\'') for x in config if x.startswith('SUPABASE_ACCESS_TOKEN='))
management={'Authorization':'Bearer '+token}
base=f'https://{REF}.supabase.co'
api=f'https://api.supabase.com/v1/projects/{REF}'
keys=requests.get(api+'/api-keys',headers=management,timeout=30);keys.raise_for_status()
keys={x['name']:x['api_key'] for x in keys.json() if x.get('name') in ('anon','service_role')}
service=keys['service_role'];anon=keys['anon']
admin_h={'apikey':service,'Authorization':'Bearer '+service,'Content-Type':'application/json'}
uid=None; obj=None

def sql(q):
    r=requests.post(api+'/database/query',headers=management,json={'query':q},timeout=30)
    if not r.ok: raise RuntimeError('management SQL failed: '+str(r.status_code)+' '+r.text[:300])
    return r.json()

def assert_status(r, permitted, label):
    if r.status_code not in permitted:
        raise AssertionError(f'{label}: unexpected HTTP {r.status_code}: {r.text[:250]}')
    print(label, r.status_code, flush=True)

try:
    password=secrets.token_urlsafe(32)
    email='pulse-test-'+uuid.uuid4().hex+'@example.invalid'
    r=requests.post(base+'/auth/v1/admin/users',headers=admin_h,json={'email':email,'password':password,'email_confirm':True},timeout=30)
    assert_status(r,{200,201},'create test account');uid=r.json()['id'];uuid.UUID(uid)
    r=requests.post(base+'/auth/v1/token?grant_type=password',headers={'apikey':anon,'Content-Type':'application/json'},json={'email':email,'password':password},timeout=30)
    assert_status(r,{200},'authenticate test account');jwt=r.json()['access_token']
    headers={'apikey':anon,'Authorization':'Bearer '+jwt,'Content-Type':'image/png'}
    obj=f'{uid}/managed-test-{uuid.uuid4().hex}.png'
    # The Storage API handles the object lifecycle and its protected metadata.
    url=base+'/storage/v1/object/avatars/'+obj
    r=requests.post(url,headers=headers,data=b'\x89PNG\r\n\x1a\n' + b'\x00'*24,timeout=30)
    assert_status(r,{200},'allowed upload')
    sql("insert into public.pulse_user_controls(user_id,can_change_profile_photo) values ('%s',false) on conflict(user_id) do update set can_change_profile_photo=false" % uid)
    second=base+'/storage/v1/object/avatars/'+uid+'/blocked-'+uuid.uuid4().hex+'.png'
    r=requests.post(second,headers=headers,data=b'\x89PNG\r\n\x1a\n'+b'\x00'*24,timeout=30)
    assert_status(r,{400,401,403},'disabled upload denied')
    r=requests.put(url,headers=headers,data=b'\x89PNG\r\n\x1a\n'+b'\x01'*24,timeout=30)
    assert_status(r,{400,401,403,404},'disabled update denied')
    r=requests.delete(base+'/storage/v1/object/avatars',headers={'apikey':anon,'Authorization':'Bearer '+jwt,'Content-Type':'application/json'},json={'prefixes':[obj]},timeout=30)
    assert_status(r,{200,400,401,403,404},'disabled delete request')
    remaining=sql("select count(*) as n from storage.objects where bucket_id='avatars' and name='%s'" % obj)
    if remaining[0]['n'] != 1: raise AssertionError('disabled delete removed object')
    print('disabled delete retained object',flush=True)
    sql("update public.pulse_user_controls set can_change_profile_photo=true where user_id='%s'" % uid)
    r=requests.put(url,headers=headers,data=b'\x89PNG\r\n\x1a\n'+b'\x02'*24,timeout=30)
    assert_status(r,{200},'enabled update')
    r=requests.delete(base+'/storage/v1/object/avatars',headers={'apikey':anon,'Authorization':'Bearer '+jwt,'Content-Type':'application/json'},json={'prefixes':[obj]},timeout=30)
    assert_status(r,{200},'allowed delete');obj=None
finally:
    if obj:
        r=requests.delete(base+'/storage/v1/object/avatars',headers=admin_h,json={'prefixes':[obj]},timeout=30)
        print('cleanup object',r.status_code,flush=True)
    if uid:
        r=requests.delete(base+'/auth/v1/admin/users/'+uid,headers=admin_h,timeout=30)
        print('cleanup account',r.status_code,flush=True)
        if not r.ok: print('WARNING: test account cleanup failed',flush=True)
