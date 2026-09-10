"""Reproduce: /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python <this file>
Authoring and USD are Y-up meters; Blender review cameras use explicit Y-up directions.
No peer assets are embedded. All dimensions are provisional visual reservations.
"""
from pathlib import Path
import bpy, json, math, hashlib
from mathutils import Matrix,Vector
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Gf,Sdf
OUT=Path(__file__).resolve().parent
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials): bpy.data.materials.remove(m)
bpy.context.scene.unit_settings.system='METRIC'; bpy.context.scene.unit_settings.scale_length=1

def mat(name,color):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); return m
shellmat=mat('NeutralFrame',(.26,.29,.29)); blankmat=mat('BlankSurface',(.39,.43,.42)); labelmat=mat('PlanningInk',(.95,.85,.57))
def node(name,parent=None,loc=(0,0,0),rot=(0,0,0)):
 o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.parent=parent; o.location=loc; o.rotation_euler=[math.radians(a) for a in rot]; return o
def mesh(name,parent,verts,faces,material):
 d=bpy.data.meshes.new(name); d.from_pydata(verts,[],faces); d.update(); o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.parent=parent; d.materials.append(material); return o
def box(name,parent,size,loc,material):
 x,y,z=[a/2 for a in size]; verts=[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)]
 o=mesh(name,parent,verts,[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],material); o.location=loc; return o
def q(rot):
 from mathutils import Euler
 v=Euler([math.radians(a) for a in rot]).to_quaternion(); return [v.x,v.y,v.z,v.w]
def pose(loc,rot=(0,0,0),space='parent-local'):
 return {'space':space,'translation_m':list(loc),'quaternion_xyzw':q(rot),'scale':[1,1,1]}
root=node('PanelInventory'); panels=node('Panels',root); labels=node('PlanningLabels',root)
mounts=json.loads((OUT/'evidence/Cabin-interface-v1.json').read_text())['panel_mounts']
manifest={'schema':'lmkit.panel-inventory.v1','units':'meters','axes':'+X right +Y up -Z forward; panel local +Z face toward crew','root':'/PanelInventory','root_pose':pose((0,0,0),space='Cabin-relative'),'windows_datum_revision':'80c9b2d','datum_revision':'2fafa5bda020b83cb7e6dff7af1a45cf6f9b35fe','baseline_revision':'09364460e8be570338f3d39a07067fe2bee0b044','planning_label_layer':'/PanelInventory/PlanningLabels','planning_labels_default_visible':False,'mission':'Descent-ready, Apollo 11 led, later/general references explicitly tagged','panels':[],'external_occupants':[],'unresolved':['All dimensions provisional; no surveyed panel outlines','Final enclosure and window clearance awaits integrated review','Later diagram equipment/stowage not certified LM-5 descent configuration','Individual switches, breakers, hoses and hidden avionics not transcribed']}
AOH='https://www.ibiblio.org/apollo/Documents/LMA790-3-LM10-ApolloOperationsHandbookLunarModuleLM10AndSubsequent-Volume1-SubsystemsData-SearchableText.pdf'
def evidence(kind='panel'):
 if kind=='panel': return {'source_id':'C1','url':AOH,'locator':'printed 1-8 / original PDF 21; ad013 panel drawing','supporting_photo':'AS11-36-5389HR.jpg (forward context only)','applicability':'LM10+ handbook; generic News Reference drawing; LM5 numbering/layout requires mission cross-check','confidence':'high panel identity; medium region arrangement; low dimensions'}
 return {'source_id':kind,'url':'https://www.nasa.gov/wp-content/uploads/static/history/diagrams/'+kind+'.gif','locator':'complete labeled drawing; evidence/'+kind+'.gif','applicability':'1972 Apollo Program Press Information Notebook; not LM5-specific','confidence':'high named region; medium side relationship; low pose/envelope'}
def panel(pid,title,loc,rot,size,kind='panel',external=False):
 p=node(pid,panels,loc,rot); lp=node(pid+'_Labels',labels,loc,rot)
 record={'id':pid,'name':title,'parent':'/PanelInventory/Panels','node':'/PanelInventory/Panels/'+pid,'pose':pose(loc,rot,'Cabin-relative'),'envelope_m':list(size),'envelope_center_local_m':[0,0,-.015],'dimension_status':'provisional visual estimate','source':evidence(kind),'shell_external':external,'slots':[],'status':{'modeled':'blank reservation','bound':False,'validated':'pending native hierarchy check'}}
 if not external:
  frame=node('Frame',p); w,h,_=size
  if pid=='Panel2':w=.395;frame.location.x=-.0425;record['authored_frame_envelope_m']=[.395,h,.022];record['authored_frame_center_local_m']=[-.0425,0,-.011]
  # Open perimeter return, never a full backing across replaceable slots.
  for sign,suffix in [(-1,'A'),(1,'B')]:
   box('FrameV'+suffix,frame,(.007,h,.022),(sign*(w/2-.0035),0,-.011),shellmat)
   if pid=='Panel5' and sign==1:
    # Fixed ACA housing X projection [.018,.1196] plus provisional 5mm each side.
    for edge,(lo,hi) in enumerate([(-w/2+.007,.013),(.125,w/2-.007)]):
     box('FrameH_Notch'+str(edge),frame,(hi-lo,.007,.022),((lo+hi)/2,sign*(h/2-.0035),-.011),shellmat)
   else:box('FrameH'+suffix,frame,(w-.014,.007,.022),(0,sign*(h/2-.0035),-.011),shellmat)
 record['default_placeholder_node']=None; record['label_node']='/PanelInventory/PlanningLabels/'+pid+'_Labels'; record['placeholder_policy']='composite panel: replace child slots only'; record['frame_node']=None if external else record['node']+'/Frame'; manifest['panels'].append(record); return p,lp,record

def slot(paneldata,suffix,name,xy,size,external=None,z=0,source=None):
 p,lp,r=paneldata; sid=r['id']+'__'+suffix; mount=node(sid,p,(*xy,z)); w,h=size
 omitted=r['id']=='Panel5' and suffix=='Timer'
 if omitted:node('Placeholder',mount)
 else:box('Placeholder',mount,(w,h,.003),(0,0,-.0015),blankmat)
 # Label mesh lives entirely in independently switchable layer, with same panel pose.
 l=node(sid+'_Label',lp,(*xy,z+.002)); curve=bpy.data.curves.new(sid+'_Text','FONT')
 # Human readable short lines retain real panel ID and development status.
 import textwrap
 text=r['name'].split(' — ')[0]+' / '+name+(' / reserved opening' if omitted else '')
 curve.body='\n'.join(textwrap.wrap(text,22))+ ('\nexternal component' if external else '\nnot modeled')
 curve.align_x='CENTER'; curve.align_y='CENTER'; curve.size=min(.019,w/14,h/(len(curve.body.splitlines())*1.5)); curve.extrude=0
 o=bpy.data.objects.new('Text',curve); bpy.context.collection.objects.link(o); o.parent=l; curve.materials.append(labelmat)
 bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH'); o.select_set(False)
 rec={'id':sid,'name':name,'purpose':name,'parent':r['id'],'node':r['node']+'/'+sid,'pose':pose((*xy,z)),'envelope_m':[w,h,.003],'envelope_center_local_m':[0,0,-.0015],'default_placeholder_node':r['node']+'/'+sid+'/Placeholder','label_node':'/PanelInventory/PlanningLabels/'+r['id']+'_Labels/'+sid+'_Label','source':source or r['source'],'dimension_status':'provisional; not fabrication','status':{'modeled':'external' if external else False,'bound':'external-owner' if external else False,'validated':False},'replacement_policy':'successful load hides only default_placeholder_node; failure retains it; never remove panel/frame/label or peer equipment','external_occupant':external}
 rec['physical_blank_omitted']=omitted
 rec['replacement_allowed']=not omitted
 rec['installation_status']='blocked-by-ACA-clearance' if omitted else 'provisional-layout'
 if omitted:rec['replacement_policy']='DO NOT FILL: open reservation blocked by ACA housing; reconcile layout and validate clearance before any future component installation'
 if omitted:rec['omission_reason']='ACA housing crossing; logical timer slot retained, physical placement unresolved; empty placeholder Xform intentional'
 r['slots'].append(rec)
 if external: manifest['external_occupants'].append({'id':external,'slot':sid,'embed':False,'installation':'preserve existing pose and runtime identity; coordinator owns load/binding'})
 return rec
manifest['source_contract_sha256']={f:hashlib.sha256((OUT/'evidence'/f).read_bytes()).hexdigest() for f in ['Cabin-interface-v1.json','WindowsLPD-interface-v1.json','CommanderPanels-mounting.json']}
manifest['panel5_opening']={'local_top_rail_omission_x_m':[.013,.125],'fixed_housing_projection_x_m':[.018,.1196],'allowance_per_side_m':.005,'allowance_status':'provisional visual clearance, not mechanical seating or hand allowance','timer_slot_status':'blocked; no physical surface and no automatic replacement','datum_unchanged':True}
# Main mount centers are exact committed datums. Outlines and subdivisions are provisional.
for n in range(1,7):
 m=mounts['Mount_Panel_'+str(n)]; title={1:'commander flight',2:'pilot flight',3:'center systems',4:'primary guidance',5:'commander waist',6:'abort guidance'}[n]
 data=panel('Panel'+str(n),'Panel '+str(n)+' — '+title,m['position'],(m['rotation_x_degrees'],0,0),m['envelope'],external=n in (1,4))
 if n==1:
  slot(data,'FDAI','FDAI',(-.055,-.015),(.148,.148),'FDAI_CDR',.016)
  slot(data,'Warning','warning array',(.08,.213),(.24,.045))
  slot(data,'Timers','mission / event timers',(-.06,.158),(.23,.034))
  slot(data,'CrossPointer','cross-pointer',(-.07,.10),(.14,.065))
  slot(data,'Propulsion','propulsion quantities',(.177,.105),(.09,.14))
  slot(data,'RangeThrust','altitude / range / thrust',(.145,-.045),(.16,.09))
  slot(data,'Guidance','guidance / engine / abort',(.035,-.178),(.35,.115))
 elif n==2:
  slot(data,'FDAI','pilot FDAI',(.06,-.115),(.15,.15))
  slot(data,'Caution','caution array',(-.015,.193),(.30,.06))
  slot(data,'RCSECS','RCS / ECS monitoring',(-.04,.10),(.34,.10))
  slot(data,'CrossPointer','pilot cross-pointer',(.08,.005),(.075,.065))
  slot(data,'Systems','RCS valves / ECS switches',(-.13,-.075),(.17,.235))
  slot(data,'Lower','ECS / suit fans',(-.04,-.222),(.34,.032))
 elif n==3:
  for i,(s,t) in enumerate([('EngineRadar','engine / radar'),('Stability','stabilization'),('TimerHeaters','timer / heaters'),('Lighting','lighting / contact')]): slot(data,s,t,(-.36+i*.24,0),(.225,.145))
 elif n==4:
  slot(data,'DSKY','DSKY',(0,.015),(.2063496,.2032),'DSKY',.009)
  slot(data,'EnableLeft','ACA / TTCA enable',(-.155,.005),(.065,.19))
  slot(data,'EnableRight','ACA enable',(.155,.005),(.065,.19))
  slot(data,'Lower','guidance surround',(0,-.137),(.36,.043))
 elif n==5:
  slot(data,'Engine','engine start / stop',(-.08,.07),(.125,.11))
  slot(data,'Timer','mission timer',(.08,.07),(.125,.11))
  slot(data,'Translation','descent rate / +X',(-.08,-.068),(.125,.11))
  slot(data,'Lighting','lighting',(.08,-.068),(.125,.11))
 elif n==6:
  slot(data,'DEDA','DEDA',(.042,0),(.20,.25))
  slot(data,'AGS','AGS status / engine stop',(-.112,0),(.072,.25))
# Side terraces run in cabin depth, local X maps toward aft on the CDR side.
# Pose revision awaits Cabin review; orientations retain documented inclinations.
side_specs=[('Panel8','Panel 8 — commander side',(-.91,.89,-.19),(-75,90,0),(.70,.30,.03),['explosive devices','audio','heaters / vents']),('Panel11','Panel 11 — commander breakers',(-.94,1.50,-.10),(-20,90,0),(.77,.36,.03),['breaker strip 1','breaker strip 2','breaker strip 3','breaker strip 4','breaker strip 5']),('Panel12','Panel 12 — pilot communications',(.91,.89,-.19),(-75,-90,0),(.70,.30,.03),['audio','communications','antenna aiming']),('Panel14','Panel 14 — electrical power',(.99,1.18,-.15),(-53.5,-90,0),(.70,.22,.03),['power monitoring','battery distribution']),('Panel16','Panel 16 — pilot breakers',(.94,1.52,-.10),(-20,-90,0),(.77,.30,.03),['breaker strip 1','breaker strip 2','breaker strip 3','breaker strip 4']),('ORDEAL','ORDEAL',(-.96,1.10,.47),(0,90,0),(.25,.14,.03),['orbital reference controls'])]
for pid,title,loc,rot,size,names in side_specs:
 data=panel(pid,title,loc,rot,size)
 for i,name in enumerate(names):
  if pid in ('Panel11','Panel16'):
   h=(size[1]-.02)/len(names); xy=(0,(len(names)-1)/2*h-i*h); wh=(size[0]-.025,h-.008)
  else:
   w=(size[0]-.02)/len(names); xy=((i-(len(names)-1)/2)*w,0); wh=(w-.008,size[1]-.025)
  slot(data,'Region'+str(i+1),name,xy,wh)
regions=[
 ('OpticalAOT','Optical — AOT',(0,1.96,-.65),(0,0,0),(.18,.18,.03),'ad016',['alignment optical telescope']),
 ('UtilityLights','Overhead — utility lights',(.18,2.06,-.59),(-25,0,0),(.20,.07,.03),'ad013',['utility light switches']),
 ('OpticalCOAS','Optical — COAS',(-.61,1.94,-.37),(0,20,0),(.12,.16,.03),'ad016',['crew optical alignment sight']),
 ('SequenceCamera','Optical — camera',(.69,1.97,-.33),(0,-20,0),(.14,.14,.03),'ad016',['sequence camera']),
 ('ECSOxygen','ECS — oxygen',(.72,1.26,.87),(0,180,0),(.37,.34,.04),'ad017',['oxygen control module','oxygen hoses']),
 ('ECSWater','ECS — water',(.70,.62,.88),(0,180,0),(.40,.30,.04),'ad017',['water control module','water dispenser']),
 ('ECSRecirculation','ECS — recirculation',(.45,.34,.89),(0,180,0),(.30,.20,.04),'ad017',['LiOH cartridge','recirculation assembly']),
 ('ECSCartridgeStowage','ECS — cartridge stowage',(.85,.94,.86),(0,180,0),(.22,.22,.04),'ad017',['LiOH stowage']),
 ('AftGuidance','Aft — guidance electronics',(-.66,1.36,.92),(0,180,0),(.36,.30,.04),'ad017',['LGC','DSEA']),
 ('AftCDU','Aft — coupling data',(-.65,.49,.92),(0,180,0),(.35,.24,.04),'ad017',['coupling data unit']),
 ('AftStowage','Aft — equipment stowage',(-.63,.94,.95),(0,180,0),(.38,.39,.04),'ad017',['PLSS stowage','oxygen hose / PLSS']),
 ('AftWaste','Aft — waste management',(-.84,.26,.87),(0,180,0),(.23,.14,.03),'ad017',['waste management']),
 ('OverheadRelief','Overhead — hatch equipment',(.34,2.04,.55),(90,0,0),(.18,.18,.03),'ad017',['cabin relief / dump valve']),
 ('ForwardRelief','Forward — hatch equipment',(.30,.55,-.88),(0,0,0),(.15,.16,.03),'ad016',['cabin relief / dump valve']),
 ('ForwardStowageCDR','Forward — commander stowage',(-.95,.43,-.18),(0,90,0),(.32,.29,.03),'ad016',['helmet / filter stowage']),
 ('ForwardStowageLMP','Forward — pilot stowage',(.95,.43,-.18),(0,-90,0),(.32,.29,.03),'ad016',['helmet stowage'])]
for pid,title,loc,rot,size,kind,names in regions:
 data=panel(pid,title,loc,rot,size,kind)
 for i,name in enumerate(names):
  h=(size[1]-.02)/len(names); slot(data,'Region'+str(i+1),name,(0,(len(names)-1)/2*h-i*h),(size[0]-.024,h-.007))
manifest['external_occupants'] += [
 {'id':'CommanderPanels','embed':False,'slots':['Panel1','Panel4'],'asset':'CommanderPanels/CommanderPanels.usdz','pose':pose((0,0,0),space='Cabin-relative'),'role':'external shell and aperture surrounds; do not hide on instrument substitution'},
 {'id':'ACA_CDR','embed':False,'asset':'HandControllers/ACA.usdz','pose':pose((-.49,.9075,-.37),space='Cabin-relative'),'runtime_identity':'acaHandle','source':'LM11f7335 Docs/ACAIntegrationHandoff.md','status':{'modeled':True,'bound':'existing LM runtime','validated':'owner-native; integrated clearance pending'},'swept_aabb_cabin_m':[[-.558526,.9075,-.45495],[-.421474,1.170037,-.28505]],'placeholder':None,'reason':'existing functional controller and fallback owned by LM; do not duplicate'},
 {'id':'ACA_LMP','embed':False,'asset':'HandControllers/ACA.usdz','pose':None,'status':{'modeled':True,'bound':False,'validated':False},'reason':'station pose unresolved; no invented installation'},
 {'id':'TTCA_CDR_LMP','embed':False,'asset':'HandControllers/TTCA.usdz','pose':None,'status':{'modeled':True,'bound':False,'validated':False},'reason':'existing component; station registration and simulation binding unresolved'},
 {'id':'CabinStructure','embed':False,'regions':['ascent engine cover','overhead hatch and drogue clearance','forward hatch','restraints / armrests'],'reason':'structural/context geometry owner Cabin; descriptive equipment placeholders above do not replace hatch leaves'},
 {'id':'WindowsLPD','embed':False,'regions':['forward windows / shades','docking window / shade','LPD marks'],'reason':'optical worker owns representation and pose revisions'}]
# Export all visible geometry as native neutral USD, no renderer-specific materials.
def export():
 stage=Usd.Stage.CreateNew(str(OUT/'PanelInventory.usda')); UsdGeom.SetStageMetersPerUnit(stage,1); UsdGeom.SetStageUpAxis(stage,'Y'); materials={}
 for m in bpy.data.materials:
  u=UsdShade.Material.Define(stage,'/Materials/'+m.name); s=UsdShade.Shader.Define(stage,'/Materials/'+m.name+'/Surface'); s.CreateIdAttr('UsdPreviewSurface'); s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3])); s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.75); u.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface'); materials[m.name]=u
 def emit(o,path):
  path+='/'+o.name.split('.')[0]; u=UsdGeom.Mesh.Define(stage,path) if o.type=='MESH' else UsdGeom.Xform.Define(stage,path); m=o.matrix_local
  UsdGeom.Xformable(u).AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
  if o.type=='MESH':
   o.data.calc_loop_triangles(); points=[Gf.Vec3f(*v.co) for v in o.data.vertices]; u.CreatePointsAttr(points); u.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles)); u.CreateFaceVertexIndicesAttr([i for t in o.data.loop_triangles for i in t.vertices]); u.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(points)); u.CreateSubdivisionSchemeAttr('none'); u.CreateDoubleSidedAttr(True); UsdShade.MaterialBindingAPI.Apply(u.GetPrim()).Bind(materials[o.data.materials[0].name])
  for c in sorted(o.children,key=lambda c:c.name):emit(c,path)
 bpy.context.view_layer.update(); emit(root,''); stage.SetDefaultPrim(stage.GetPrimAtPath('/PanelInventory')); UsdGeom.Imageable(stage.GetPrimAtPath('/PanelInventory/PlanningLabels')).CreateVisibilityAttr().Set('invisible'); stage.GetRootLayer().Save(); stage.GetRootLayer().Export(str(OUT/'PanelInventory.usdc'))
 target=OUT/'PanelInventory.usdz'
 if target.exists():target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'PanelInventory.usdc')),str(target))
export(); (OUT/'inventory.json').write_text(json.dumps(manifest,indent=2)+'\n')
# Small workbench review renders, no simulator job or lighting bake.
scene=bpy.context.scene; scene.render.engine='BLENDER_WORKBENCH'; scene.render.resolution_x=1000; scene.render.resolution_y=800; scene.render.resolution_percentage=100
scene.world.color=(.05,.05,.05); scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_shadows=False; scene.display.shading.show_cavity=True; scene.display.shading.background_type='WORLD'
def review(name,eye,target,orthographic=None):
 d=bpy.data.cameras.new(name); c=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(c); c.location=eye; f=(Vector(target)-Vector(eye)).normalized(); up=Vector((0,1,0)) if abs(f.y)<.99 else Vector((0,0,-1)); right=f.cross(up).normalized(); up=right.cross(f); c.rotation_euler=Matrix((right,up,-f)).transposed().to_euler(); scene.camera=c; d.lens=25
 if orthographic:d.type='ORTHO'; d.ortho_scale=orthographic
 
 # Cutaway review: exclude only the equipment bank behind the observer.
 for p in panels.children:
  hide=(name.startswith(('front','commander','pilot')) and p.location.z>.55) or (name.startswith('rear') and p.location.z<.5)
  for o in p.children_recursive:o.hide_render=hide
  lp=bpy.data.objects.get(p.name+'_Labels')
  if lp:
   for o in lp.children_recursive:o.hide_render=hide or name.endswith('clean')
 scene.render.filepath=str(OUT/'review'/name)+'.png'; bpy.ops.render.render(write_still=True)
for visible in [True,False]:
 for o in labels.children_recursive:o.hide_render=not visible
 suffix='labels' if visible else 'clean'
 for name,eye,target,scale in [('front',(0,1.6,3.2),(0,1.25,-.3),2.8),('side',(-3,1.6,.3),(0,1.2,0),2.8),('commander',(-.5588,1.78,-.38),(-.05,1.30,-.8),None),('pilot',(.5588,1.78,-.38),(.1,1.35,-.8),None),('rear',(0,1.55,-1.6),(0,1.1,.9),2.5),('overhead',(0,4,.2),(0,1,.1),2.9)]: review(name+'-'+suffix,eye,target,scale)
for o in panels.children_recursive:o.hide_render=False
for o in labels.children_recursive:o.hide_render=True
label_collection=bpy.data.collections.new('PlanningLabels_INSPECTION_ONLY');scene.collection.children.link(label_collection)
for o in [labels]+list(labels.children_recursive):
 for collection in list(o.users_collection):collection.objects.unlink(o)
 label_collection.objects.link(o)
label_collection.hide_viewport=True;label_collection.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'PanelInventory.blend'))
print('BUILT',len(manifest['panels']),'panels',sum(len(p['slots']) for p in manifest['panels']),'slots')
