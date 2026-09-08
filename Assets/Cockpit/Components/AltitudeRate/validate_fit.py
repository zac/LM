"""Conservative panel-local face-envelope checks against pinned adjacent inventory slots.
This does not certify rear instrument mounting or continuous 3D cabin clearance.
"""
import json,pathlib,hashlib
P=pathlib.Path(__file__).resolve().parent
c=json.loads((P/'interface.json').read_text());v=json.loads((P/'validation.json').read_text());inv=json.loads((P.parent/'PanelInventory/inventory.json').read_text());panel=next(p for p in inv['panels'] if p['id']=='Panel1');slot=next(s for s in panel['slots'] if s['id']==c['slot']);pose=[a+b for a,b in zip(slot['pose']['translation_m'],c['slot_local_pose']['translation_m'])]
lo=[a+b for a,b in zip(v['bounds_min'],pose)];hi=[a+b for a,b in zip(v['bounds_max'],pose)];rows=[]
for other in panel['slots']:
 if other['id']==slot['id']:continue
 center=[a+b for a,b in zip(other['pose']['translation_m'],other['envelope_center_local_m'])];half=[x/2 for x in other['envelope_m']];blo=[a-b for a,b in zip(center,half)];bhi=[a+b for a,b in zip(center,half)]
 gaps=[max(blo[i]-hi[i],lo[i]-bhi[i],0) for i in [0,1]]
 assert any(g>0 for g in gaps),other['id']
 rows.append({'other_slot':other['id'],'xy_separation_m':gaps,'surface_overlap_in_panel_xy':False})
blank_lo=slot['envelope_center_local_m'][2]-slot['envelope_m'][2]/2;blank_hi=slot['envelope_center_local_m'][2]+slot['envelope_m'][2]/2
report={'status':'PASS provisional face envelope','panel':'Panel1','slot':slot['id'],'actual_instrument_panel_local_min_m':lo,'actual_instrument_panel_local_max_m':hi,'unchanged_slot_pose':slot['pose'],'approved_slot_local_offset':c['slot_local_pose'],'adjacent_slots':rows,'retained_blank':{'slot_local_z_bounds_m':[blank_lo,blank_hi],'instrument_visible_tape_z_m':.013,'instrument_pointer_z_m':.018,'occlusion':'blank entirely behind active tape/pointer; keep blank for deferred T/W','rear_intersection':'HousingBack intentionally intersects existing panel/blank slab while seated; hidden registration only, not qualified mechanical mounting'},'limits':['No surveyed dimensions','Provisional3mm Guidance and7.5mm Propulsion vertical gaps','No current full cabin/window ray or controller sweep test','Front/crew-eye combined Blender previews inspected; FDAI Workbench texture not a runtime appearance test'],'dependency_hashes':{n:hashlib.sha256((P.parent/n/f).read_bytes()).hexdigest() for n,f in [('PanelInventory','inventory.json'),('CommanderPanels','CommanderPanels.usdz'),('FDAI','FDAI.usdz')]}}
(P/'mounting.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
