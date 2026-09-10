from pathlib import Path
exec(Path('/private/tmp/lm-solid-console-combined/audit.py').read_text().split("R={'inputs':")[0])
p=Path('/private/tmp/lmkit-window-surrounds/Assets/Cockpit/Components/BreakerBanks/BreakerBanks.usdz');peer=load(p)
r={'breaker_input':{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()},'enclosure_inputs':{},'crossings':{}}
for k,folder in SOURCES.items():
 path=folder/(k+'.usdz');r['enclosure_inputs'][k]=hashlib.sha256(path.read_bytes()).hexdigest();r['crossings'][k]=crosses(load(path),peer)
(OUT/'breaker-report.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'crossings':{k:len(v) for k,v in r['crossings'].items()},'inputs':r['enclosure_inputs']}))
