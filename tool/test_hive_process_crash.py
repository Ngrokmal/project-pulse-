#!/usr/bin/env python3
"""Process-kill tests; not a simulation of device power failure or OS caching."""
import os,selectors,signal,subprocess,tempfile,time
DART='/home/user/flutter-sdk-live/flutter/bin/dart'
def start(mode,path,marker):
 p=subprocess.Popen([DART,'run','tool/hive_crash_probe.dart',mode,path],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
 selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
 if not selector.select(timeout=30):
  os.killpg(p.pid,signal.SIGKILL);p.wait();raise RuntimeError('writer timed out')
 text=p.stdout.readline().strip()
 if text!=marker:
  os.killpg(p.pid,signal.SIGKILL);p.wait();raise RuntimeError('unexpected marker '+text)
 return p
def kill(p):
 if p.poll() is None:os.killpg(p.pid,signal.SIGKILL)
 p.wait(timeout=10)
def verify(mode,path):
 r=subprocess.run([DART,'run','tool/hive_crash_probe.dart',mode,path],capture_output=True,text=True,timeout=30)
 if r.returncode:raise RuntimeError('reopen failed closed or failed test: '+r.stderr[:800])
 print(r.stdout.strip(),flush=True)
with tempfile.TemporaryDirectory(prefix='pulse-kill-') as path:
 p=start('write',path,'FLUSHED');kill(p);verify('verify',path)
 for delay in (0,0.01,0.05,0.15,0.3,0.6):
  p=start('write-race',path,'WRITING');time.sleep(delay);kill(p);verify('verify-race',path)
  # Fresh baseline per iteration, since an interrupted write can complete.
  for f in os.listdir(path):os.remove(os.path.join(path,f))
  p=start('write',path,'FLUSHED');kill(p)
