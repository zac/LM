"""Focused synthetic error-path checks; no Blender imports, asset writes or renders."""
import ast,copy,hashlib,json,subprocess,sys,tempfile
from pathlib import Path
OUT=Path(__file__).resolve().parent
SCRIPT=OUT/'validate.py'
results=[]
def run(name,args,expected):
 result=subprocess.run([sys.executable,str(SCRIPT),*map(str,args)],capture_output=True,text=True)
 assert result.returncode==expected,(name,result.returncode,result.stderr)
 results.append({'case':name,'expected_exit':expected,'actual_exit':result.returncode})
reports={name:json.loads((OUT/name).read_text()) for name in ['validation.json','clearance.json','windows-clearance.json']}
with tempfile.TemporaryDirectory(prefix='panel-validator-policy-') as temp:
 temp=Path(temp); reportdir=temp/'reports';reportdir.mkdir()
 def report_case(name,change=None,expected=1):
  data=copy.deepcopy(reports)
  if change:change(data)
  for file,value in data.items():(reportdir/file).write_text(json.dumps(value))
  run(name,['--check-reports',reportdir],expected)
 report_case('existing passing reports',expected=0)
 report_case('nonzero failure count',lambda r:r['validation.json'].__setitem__('failed',1))
 report_case('failed individual check despite zero counter',lambda r:r['validation.json']['checks'][0].__setitem__('pass',False))
 report_case('compliance errors',lambda r:r['validation.json'].__setitem__('compliance_errors',['synthetic']))
 report_case('compliance failed checks',lambda r:r['validation.json'].__setitem__('compliance_failed',['synthetic']))
 report_case('neutral ACA crossing',lambda r:r['clearance.json'].__setitem__('neutral_surface_intersections',[{'synthetic':True}]))
 report_case('sampled ACA crossing',lambda r:r['clearance.json'].__setitem__('sampled_surface_intersections',{'synthetic':1}))
 report_case('ACA conflict status',lambda r:r['clearance.json'].__setitem__('status','CONFLICT'))
 report_case('window crossing',lambda r:r['windows-clearance.json'].__setitem__('surface_intersections',[{'synthetic':True}]))
 (reportdir/'validation.json').write_text('{broken')
 run('malformed report exception',['--check-reports',reportdir],1)
 (reportdir/'validation.json').unlink()
 run('missing report exception',['--check-reports',reportdir],1)
 pointer=subprocess.check_output(['git','show','750caea3dea7feeaf5ffea15eedcf2d031cca0be:Assets/Cockpit/Components/HandControllers/ACA.usdz'],cwd=OUT)
 digest=pointer.decode().split('sha256:')[1].split()[0]
 common=Path(subprocess.check_output(['git','rev-parse','--git-common-dir'],cwd=OUT,text=True).strip())
 if not common.is_absolute():common=OUT/common
 payload=(common/'lfs/objects'/digest[:2]/digest[2:4]/digest).read_bytes()
 assert hashlib.sha256(payload).hexdigest()==digest
 hydrated=temp/'ACA.usdz';hydrated.write_bytes(payload)
 run('reviewed hydrated ACA bytes',['--check-aca',hydrated,common],0)
 pointerfile=temp/'ACA-pointer.usdz';pointerfile.write_bytes(pointer)
 run('reviewed ACA pointer and cached bytes',['--check-aca',pointerfile,common],0)
 hydrated.write_bytes(bytes([payload[0]^1])+payload[1:])
 run('changed hydrated ACA with same size',['--check-aca',hydrated,common],1)
 pointerfile.write_bytes(pointer.replace(digest.encode(),b'0'*64))
 run('different LFS pointer digest',['--check-aca',pointerfile,common],1)
 pointerfile.write_bytes(pointer)
 fakecommon=temp/'fake-git';fakeobject=fakecommon/'lfs/objects'/digest[:2]/digest[2:4]/digest;fakeobject.parent.mkdir(parents=True);fakeobject.write_bytes(hydrated.read_bytes())
 run('corrupted cached ACA behind matching pointer',['--check-aca',pointerfile,fakecommon],1)
 fakeobject.unlink()
 run('missing cached ACA exception',['--check-aca',pointerfile,fakecommon],1)
 tree=ast.parse(SCRIPT.read_text());main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main')
 calls={n.func.id for n in ast.walk(main) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name)}
 assert {'read_pinned_aca','require_passing_reports'}<=calls
 results.append({'case':'geometry main invokes digest and result gates','pass':True})
report={'scope':'synthetic policy/error-path checks only; no geometry rerun or render','ACA_revision':'750caea3dea7feeaf5ffea15eedcf2d031cca0be','ACA_sha256':digest,'ACA_bytes':len(payload),'cases':results,'result':'PASS'}
(OUT/'evidence/validator-policy-check.json').write_text(json.dumps(report,indent=2)+'\n')
print('POLICY_PASS',len(results),'cases; pinned ACA',digest)
