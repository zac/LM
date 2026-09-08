import subprocess,time,pathlib,json
u='DE0FAD53-2A01-4B96-95D3-3505E6900DA3'
out=pathlib.Path('/private/tmp/lm-commander-instruments-validation/evidence/startup-temporal-after');out.mkdir(exist_ok=True)
d=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j']));device=next(x for group in d['devices'].values() for x in group if x['udid']==u)
if device['state']=='Shutdown':subprocess.run(['xcrun','simctl','boot',u],check=True)
subprocess.run(['xcrun','simctl','bootstatus',u,'-b'],check=True)
subprocess.run(['xcrun','simctl','install',u,'/private/tmp/lm-commander-instruments-validation/build/Build/Products/Debug-xrsimulator/LM.app'],check=True)
a=['xcrun','simctl','launch','--terminate-running-process',u,'io.positron.LM','--terminal-descent-cockpit','--assembly-validation-view=control-closeup','--cockpit-startup-timing']
t0=time.monotonic();wall=time.time();result=subprocess.run(a,capture_output=True,text=True,check=True);t1=time.monotonic();(out/'launch.txt').write_text(result.stdout+result.stderr)
data={'arguments':a,'launch_wall_epoch':wall,'launch_return_seconds':t1-t0,'reference':'requested offsets measured from successful simctl launch return; actual start/end recorded','captures':[]}
for offset in [4,5,6,7,8,9,10,12,20]:
 time.sleep(max(0,t1+offset-time.monotonic()));start=time.monotonic();name=f'control-{offset:g}s.png'
 subprocess.run(['xcrun','simctl','io',u,'screenshot',str(out/name)],check=True)
 data['captures'].append({'name':name,'requested_after_return_s':offset,'actual_start_after_launch_s':start-t0,'actual_end_after_launch_s':time.monotonic()-t0})
(out/'timing.json').write_text(json.dumps(data,indent=2)+'\n')
with (out/'runtime.log').open('w') as f:subprocess.run(['xcrun','simctl','spawn',u,'log','show','--last','2m','--predicate','process == "LM" AND subsystem BEGINSWITH "io.positron.LM"','--style','compact','--info'],stdout=f,stderr=subprocess.STDOUT)
