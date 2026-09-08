"""Closed lower visual console; fixed hardware and source slots remain unchanged."""
import sys,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from geometry import *
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
sc=bpy.context.scene;sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1
material('ConsoleGray',(.32,.365,.35));material('CaseSide',(.225,.265,.255));material('LipMetal',(.47,.49,.455));material('Recess',(.065,.077,.073))
inv=json.loads((D/'evidence/inventory.json').read_text());panels={p['id']:p for p in inv['panels']};root=node('LowerConsole')
p4=node('DSKYCase',root);p4.matrix_local=panelpose(panels['Panel4']['pose'])
# Face sheet behind existing populated/blank slot faces. Four strips leave the true empty DSKY aperture.
ax=.1061748;ay0=.015-.1046;ay1=.015+.1046
for name,lo,hi in [('Left',(-.2,-.17,-.008),(-ax,.203,-.004)),('Right',(ax,-.17,-.008),(.2,.203,-.004)),('Top',(-ax,ay1,-.008),(ax,.203,-.004)),('Apron',(-ax,-.17,-.008),(ax,ay0,-.004))]:box('Face'+name,p4,lo,hi,'ConsoleGray')
# Full depth closed cavity behind the existing provisional rear housing.
box('RearClosure',p4,(-.2,-.17,-.172),(.2,.203,-.168),'CaseSide')
box('LeftReturn',p4,(-.2,-.17,-.168),(-.196,.203,-.008),'CaseSide')
box('RightReturn',p4,(.196,-.17,-.168),(.2,.203,-.008),'CaseSide')
box('TopReturn',p4,(-.196,.199,-.168),(.196,.203,-.008),'CaseSide')
box('BottomReturn',p4,(-.196,-.17,-.168),(.196,-.166,-.008),'CaseSide')
# Recessed mounting reveal bridges visible face to the dark enclosure, never overlaps DSKY.
for name,lo,hi in [('Left',(-ax-.004,ay0-.004,-.009),(-ax,ay1+.004,.002)),('Right',(ax,ay0-.004,-.009),(ax+.004,ay1+.004,.002)),('Top',(-ax,ay1,-.009),(ax,ay1+.004,.002)),('Bottom',(-ax,ay0-.004,-.009),(ax,ay0,.002))]:box('ApertureLip'+name,p4,lo,hi,'LipMetal')
# CDR console closed side/front/base surfaces; intentional ACA well remains open.
p5=node('ControllerCase',root);p5.matrix_local=panelpose(panels['Panel5']['pose'])
box('RearClosure',p5,(-.17,-.155,-.244),(.17,.155,-.240),'CaseSide')
box('OutboardWall',p5,(-.17,-.155,-.240),(-.166,.155,-.026),'CaseSide')
box('InboardWall',p5,(.166,-.155,-.240),(.17,.155,-.026),'CaseSide')
box('CrewApron',p5,(-.166,-.155,-.240),(.166,-.151,-.026),'ConsoleGray')
# Upper wall has deep clearance notch for fixed ACA housing and runtime articulation.
box('UpperReturnLeft',p5,(-.166,.151,-.240),(.005,.155,-.026),'CaseSide')
box('UpperReturnRight',p5,(.153,.151,-.240),(.166,.155,-.026),'CaseSide')
box('UpperReturnBelowACA',p5,(.005,.151,-.240),(.153,.155,-.105),'CaseSide')
# Face behind the original slots: do not reinstate blocked Panel5__Timer.
box('SlopingFaceLeft',p5,(-.162,-.147,-.028),(.005,.147,-.004),'ConsoleGray')
box('SlopingFaceRight',p5,(.153,-.147,-.028),(.162,.147,-.004),'ConsoleGray')
box('SlopingFaceLower',p5,(.005,-.147,-.028),(.153,.005,-.004),'ConsoleGray')
# Recessed seal behind retained Inventory frame; frame is neither hidden nor intersected.
box('SealLeft',p5,(-.166,-.151,-.030),(-.162,.151,-.023),'Recess')
box('SealRight',p5,(.162,-.151,-.030),(.166,.151,-.023),'Recess')
box('SealBottom',p5,(-.162,-.151,-.030),(.162,-.147,-.023),'Recess')
box('SealTopLeft',p5,(-.162,.147,-.030),(.005,.151,-.023),'Recess')
box('SealTopRight',p5,(.153,.147,-.030),(.162,.151,-.023),'Recess')
# Solid protective shoulder joins central case visually to the controller box, below reach.
# Kept separate to avoid claiming an equipment fabrication join; generous center hatch void below.
shoulder=node('CommanderShoulder',root)
box('EquipmentCheek',shoulder,(-.387,.80,-.66),(-.204,.90,-.49),'CaseSide')
# Source-inspired closed protective apron only above the central hatch; no virtual hatch cover.
box('CenterLowerApron',root,(-.196,.835,-.81),(.196,.85,-.60),'ConsoleGray')
bpy.context.view_layer.update()
contract={'schema':'lmkit.console-enclosure.v1','component_id':'LowerConsole','root':'/LowerConsole','units':'meters','parent_space':'Cabin','root_pose':pose_dict(Matrix.Identity(4)),'base_revision':'70c0914','qualification':'All enclosure dimensions and mechanical fit provisional; fixed accepted runtime mounts unchanged. Qualitative source massing only.','groups':[{'path':'/LowerConsole/'+o.name,'casts_shadows':True} for o in root.children],'suppressions':[],'protected_mounts':[],'occupancy_claims':[],'clearances':{'dsky_aperture_panel_local':{'center_xy_m':[0,.015],'size_xy_m':[2*ax,ay1-ay0],'face_front_z_m':-.004,'lip_front_z_m':.002,'rear_inside_z_m':-.168,'rear_housing_min_z_m':-.151214,'rear_clearance_m':.016786},'blocked_timer':'Panel5__Timer remains open; new face and upper wall cut around ACA envelope.','hatch_opening':'No geometry within central |x|<.20 below Cabin y .835.'},'runtime_aca':{'root_position_m':[-.49,.9075,-.37],'rotation_quaternion_xyzw':[0,0,0,1],'source':'LMCommanderStationGeometry.acaPivotPositionMeters + LMImportedACA.registration'},'runtime':'Geometry only; no collision, input, lighting, behavior, mount movement or bindings.'}
cp=Usd.Stage.Open(str(C/'CommanderPanels/CommanderPanels.usdz'))
for tail in ['Shell','RemovableBacking','Trim','Fasteners']:
 path='/CommanderPanels/Panel_4/Panel_4_'+tail;prim=cp.GetPrimAtPath(path);assert prim;contract['suppressions'].append({'component':'CommanderPanels','path':path,'pose':pose_dict(usdpose(prim))})
for component,path in [('Cabin','/Cabin/Mounts/Mount_Panel_4'),('Cabin','/Cabin/Mounts/Mount_Panel_4/Mount_DSKY'),('Cabin','/Cabin/Mounts/Mount_Panel_5'),('PanelInventory','/PanelInventory/Panels/Panel5/Panel5__Engine'),('PanelInventory','/PanelInventory/Panels/Panel5/Panel5__Timer')]:
 st=Usd.Stage.Open(str(C/component/(component+'.usdz')));contract['protected_mounts'].append({'component':component,'path':path,'pose':pose_dict(usdpose(st.GetPrimAtPath(path)))})
meshes=[o for o in root.children_recursive if o.type=='MESH'];vs=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
for o in meshes:o.data.calc_loop_triangles()
contract['bounds_m']={'min':[min(v[i] for v in vs) for i in range(3)],'max':[max(v[i] for v in vs) for i in range(3)]};corners=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box];contract['native_conservative_bounds_m']={'min':[min(v[i] for v in corners) for i in range(3)],'max':[max(v[i] for v in corners) for i in range(3)]};contract['budget']={'meshes':len(meshes),'triangles':sum(len(o.data.loop_triangles) for o in meshes),'materials':4,'textures':0}
(D/'interface.json').write_text(json.dumps(contract,indent=2)+'\n');export(root)
sc.view_settings.view_transform='Standard';sc.view_settings.look='None';sc.view_settings.exposure=.5;sc.render.engine='BLENDER_WORKBENCH';sc.render.resolution_x=1500;sc.render.resolution_y=1150;sc.render.resolution_percentage=100;sc.display.shading.light='STUDIO';sc.display.shading.color_type='MATERIAL';sc.display.shading.show_shadows=True;sc.display.shading.show_cavity=True;sc.display.shading.cavity_type='BOTH';sc.world.color=(.075,.075,.075)
bpy.ops.wm.save_as_mainfile(filepath=str(D/'LowerConsole.blend'));print('PASS BUILD',contract['budget'],contract['bounds_m'])
