"""Assembly reviews import fixed live hardware and actual optional peers; review geometry never exported."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from geometry import *
bpy.ops.wm.open_mainfile(filepath=str(D/'LowerConsole.blend'));sc=bpy.context.scene;I=json.loads((D/'interface.json').read_text());P={p['id']:p for p in json.loads((D/'evidence/inventory.json').read_text())['panels']}
# Actual current package, no calibration offsets. Planning labels are diagnostic labels hidden by app.
omit=[x['path'] for x in I['suppressions']]+['/CommanderPanels/Panel_1/Panel_1_RemovableBacking','/PanelInventory/PlanningLabels','/PanelInventory/Panels/Panel4/Panel4__DSKY/Placeholder','/PanelInventory/Panels/Panel1/Panel1__FDAI/Placeholder','/PanelInventory/Panels/Panel5/Panel5__Engine/Placeholder','/PanelInventory/Panels/Panel3/Panel3__Stability/Placeholder']
for rel in ['Cabin/Cabin.usdz','CommanderPanels/CommanderPanels.usdz','PanelInventory/PanelInventory.usdz','WindowsLPD/WindowsLPD.usdz','BreakerBanks/BreakerBanks.usdz','InteriorDetails/InteriorDetails.usdz','CautionWarning/CautionWarning.usdz','PropulsionInstruments/PropulsionInstruments.usdz']:
 if (C/rel).exists():import_meshes(C/rel,omit=omit)
for pid,slot,asset in [('Panel4','Panel4__DSKY','DSKY/DSKY.usdz'),('Panel1','Panel1__FDAI','FDAI/FDAI.usdz'),('Panel5','Panel5__Engine','DescentControls/DescentRate.usdz'),('Panel5','Panel5__Engine','EngineControls/EngineButtons.usdz'),('Panel3','Panel3__Stability','DescentControls/AttitudeMode.usdz')]:
 p=P[pid];s=next(s for s in p['slots'] if s['id']==slot);tr=panelpose(p['pose'])@Matrix.Translation(Vector(s['pose']['translation_m']));import_meshes(C/asset,tr)
import_meshes(C/'HandControllers/ACA.usdz',Matrix.Translation(Vector((-.49,.9075,-.37))))
camd=bpy.data.cameras.new('AssemblyCamera');cam=bpy.data.objects.new('AssemblyCamera',camd);sc.collection.objects.link(cam);sc.camera=cam;camd.type='PERSP';camd.lens=34;camd.clip_start=.015;sc.render.image_settings.file_format='PNG'
views=[('crew-entry',(-.5588,1.78,.17),(-.18,1.08,-.61),34),('dsky-oblique',(-.38,1.48,-.12),(0,1.06,-.64),44),('controller-oblique',(-.17,1.33,.035),(-.49,.94,-.35),39)]
for name,eye,target,lens in views:
 cam.location=eye;forward=(Vector(target)-cam.location).normalized();right=forward.cross(Vector((0,1,0))).normalized();up=right.cross(forward);cam.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler();camd.lens=lens;sc.render.filepath=str(D/'review'/(name+'.png'));bpy.ops.render.render(write_still=True)
(D/'review/cameras.json').write_text(json.dumps({'basis':'Cabin Y-up meters','views':[{'name':n,'eye':p,'target':t,'lens_mm':l} for n,p,t,l in views],'note':'Actual current70c0914 package geometry; peers under concurrent enclosure work not substituted here. Workbench ignores emissive/transparency optics and is geometry inspection only.'},indent=2)+'\n')
