#!/usr/bin/env python3
"""Controlled byte-truncation experiment, not physical device power-loss testing.

Uses throwaway test data, a known synthetic key and copies only. Simulates a
partial tail write after a completed baseline frame and checks that recovery
never silently advances the cursor without all corresponding messages. A Hive
open failure is recorded as fail-closed, NOT as successful automatic recovery.
"""
import hashlib,os,selectors,signal,subprocess,tempfile
from pathlib import Path
DART='/home/user/flutter-sdk-live/flutter/bin/dart'
def launch(mode,path,marker):
 p=subprocess.Popen([DART,'run','tool/hive_crash_probe.dart',mode,str(path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
 try:
  selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
  if not selector.select(timeout=45):raise RuntimeError('writer marker timed out')
  got=p.stdout.readline().strip()
  if got!=marker:raise RuntimeError('unexpected marker '+got)
  return p
 except:
  if p.poll() is None:os.killpg(p.pid,signal.SIGKILL)
  p.wait();raise
def kill(p):
 if p.poll() is None:os.killpg(p.pid,signal.SIGKILL)
 p.wait(timeout=10)
def verify(path):
 return subprocess.run([DART,'run','tool/hive_crash_probe.dart','verify-race',str(path)],capture_output=True,text=True,timeout=40)
with tempfile.TemporaryDirectory(prefix='pulse-torn-') as root:
 root=Path(root);source=root/'source';source.mkdir()
 p=launch('write',source,'FLUSHED');kill(p)
 hive=source/'crash_probe.hive';baseline=hive.read_bytes()
 p=launch('write-race',source,'WRITING')
 # Wait for a real completed second write to get bytes we can truncate.
 if p.stdout.readline().strip()!='DONE':raise RuntimeError('second flush failed')
 kill(p);complete=hive.read_bytes()
 if len(complete)<=len(baseline):raise RuntimeError('expected second frame')
 for label,payload in [('baseline',baseline),('full',complete),('torn-1',complete[:-1]),('torn-quarter',complete[:len(baseline)+(len(complete)-len(baseline))//4]),('torn-half',complete[:len(baseline)+(len(complete)-len(baseline))//2])]:
  case=root/label;case.mkdir();f=case/'crash_probe.hive';f.write_bytes(payload)
  before=hashlib.sha256(f.read_bytes()).hexdigest();r=verify(case);after=hashlib.sha256(f.read_bytes()).hexdigest()
  if before!=after:raise RuntimeError(label+' modified the source copy')
  if r.returncode==0:
   if 'PASS cursor/data consistent' not in r.stdout:raise RuntimeError(label+' unexpected success output')
   print(label,r.stdout.strip(),flush=True)
  else:
   if label in ('baseline','full'):raise RuntimeError(label+' failed: '+r.stderr[:400])
   print(label,'FAIL-CLOSED: box not readable; original bytes preserved; automatic recovery not established',flush=True)
   recover=root/(label+'-recovery-copy');recover.mkdir();(recover/'crash_probe.hive').write_bytes(payload)
   recovered=subprocess.run([DART,'run','tool/hive_crash_probe.dart','recover-copy',str(recover)],capture_output=True,text=True,timeout=40)
   if recovered.returncode:raise RuntimeError(label+' recovery copy failed: '+recovered.stderr[:400])
   if 'RECOVERED prior complete revision 1' not in recovered.stdout:raise RuntimeError(label+' unexpected recovery')
   if hashlib.sha256(f.read_bytes()).hexdigest()!=before:raise RuntimeError(label+' original changed during recovery')
   print(label,'recovered prior revision on disposable copy; latest partial frame lost',flush=True)
