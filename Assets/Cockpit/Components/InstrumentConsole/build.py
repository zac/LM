"""Solid upper console, in unchanged Cabin coordinates. Owned outputs only."""
from pathlib import Path
import bpy,json,math,hashlib
from mathutils import Matrix,Vector,Quaternion
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf,Gf
O=Path(__file__).resolve().parent;D=O.parent
inv=json.loads((O/'evidence/accepted-inventory.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1

def pose(p):
 x,y,z,w=p.get('quaternion_xyzw',[0,0,0,1]);return Matrix.Translation(Vector(p.get('translation_m',[0,0,0])))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
def mat(name,rgb):
 m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);return m
paint=mat('ConsoleNeutralGray',(.36,.39,.38));edge=mat('ConsoleEdgeGray',(.28,.30,.29));seam=mat('SeamShadow',(.035,.042,.04));inside=mat('ConsoleInterior',(.12,.14,.135))
def node(name,parent=None,matrix=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent
 if matrix is not None:o.matrix_local=matrix
 return o
root=node('InstrumentConsole');faces=node('Faces',root);body=node('Enclosure',root);seams=node('Seams',root)
def mesh(name,verts,polys,parent,material,bevel=0):
 m=bpy.data.meshes.new(name);m.from_pydata(verts,[],polys);m.update();o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);o.parent=parent;o.data.materials.append(material)
 if bevel:
  bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('NarrowEdgeBevel','BEVEL');mod.width=bevel;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
 return o
def box(name,lo,hi,parent,material=paint,bevel=.0005):
 x,y,z=lo;X,Y,Z=hi
 return mesh(name,[(x,y,z),(X,y,z),(X,Y,z),(x,Y,z),(x,y,Z),(X,y,Z),(X,Y,Z),(x,Y,Z)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],parent,material,bevel)
def ring(name,cx,cy,outer,inner,z0,z1,parent,material=paint):
 # Four closed trapezoidal prisms: continuous faces with a square clear housing aperture.
 a,b=outer/2,inner/2;outerp=[(-a,-a),(a,-a),(a,a),(-a,a)];innerp=[(-b,-b),(b,-b),(b,b),(-b,b)]
 for i in range(4):
  j=(i+1)%4;xy=[outerp[i],outerp[j],innerp[j],innerp[i]];v=[(cx+x,cy+y,z) for z in [z0,z1] for x,y in xy]
  mesh(name+str(i),v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],parent,material,.00015)
def perforated_plate(name,rect,hole,parent):
 x0,x1,y0,y1=rect;cx,cy,s=hole;h=s/2;z0,z1=-.008,-.004
 for suffix,lo,hi in [('Left',(x0,y0,z0),(cx-h,y1,z1)),('Right',(cx+h,y0,z0),(x1,y1,z1)),('Lower',(cx-h,y0,z0),(cx+h,cy-h,z1)),('Upper',(cx-h,cy+h,z0),(cx+h,y1,z1))]:box(name+suffix,lo,hi,parent,bevel=0)
 # Intentional continuous plate tiles share edges; no false seams around tiles.
panels={p['id']:p for p in inv['panels'] if p['id'] in ['Panel1','Panel2','Panel3']};pn={}
for pid in ['Panel1','Panel2']:
 p=panels[pid];g=node(pid,faces,pose(p['pose']));pn[pid]=g;off=p['pose']['translation_m'][0]
 x0=(-.4 if pid=='Panel1' else .0006)-off;x1=(-.0006 if pid=='Panel1' else .4)-off
 cx,cy=(-.055,-.015) if pid=='Panel1' else (.06,-.115)
 perforated_plate(pid+'Skin',(x0,x1,-.25,.25),(cx,cy,.130),g)
 if pid=='Panel1':ring('CommanderSeat',cx,cy,.155,.130,-.004,.0118,g)
 # Four aperture tunnel walls hide the rear housing edge from oblique crew views; clear .130m bore.
 ring(pid+'ApertureTunnel',cx,cy,.137,.130,-.239,-.008,g,inside)
 # Thin framed perimeter lip, out of all accepted instrument face footprints.
 box(pid+'TopEdge',(x0,.247,-.004),(x1,.25,-.001),g,edge,.0006)
 # Shell side returns are in separate shadow group, same exact panel transform.
 b=node(pid+'Body',body,pose(p['pose']))
 outer=x0 if pid=='Panel1' else x1
 box('OutboardReturn'+pid,(outer if pid=='Panel1' else outer-.004,-.25,-.242),(outer+.004 if pid=='Panel1' else outer,.25,-.004),b,edge,.0006)
 box('TopReturn'+pid,(x0,.246,-.242),(x1,.25,-.004),b,edge,.0005)
 box('RearCover'+pid,(x0,-.25,-.244),(x1,.25,-.240),b,inside,.0005)
 # No internal center wall: the two console halves form one common cavity.
# 1.2mm narrow center joint, backed to remain visually closed.
g=node('CenterJoint',seams,pose(panels['Panel1']['pose'])@Matrix.Translation(Vector((.245,0,0))))
box('CenterSeam',(-.0006,-.25,-.010),(.0006,.25,-.0045),g,seam,0)
# Panel 3 keeps its accepted -45 degree datum, with continuous solid face and shallow returns.
p3=pose(panels['Panel3']['pose']);g=node('Panel3',faces,p3);pn['Panel3']=g
box('Panel3Skin',(-.485,-.09,-.008),(.485,.09,-.004),g,paint,.0006)
b=node('Panel3Body',body,p3)
box('Panel3RearCover',(-.485,-.09,-.055),(.485,.09,-.051),b,inside,.0005)
for side,x0,x1 in [('Left',-.485,-.481),('Right',.481,.485)]:box('Panel3'+side+'Return',(x0,-.09,-.051),(x1,.09,-.004),b,edge,.0005)
box('Panel3BottomReturn',(-.485,-.09,-.051),(.485,-.086,-.004),b,edge,.0005)
# Narrow panel3 section seams are painted recessed lines, not through-gaps.
s=node('Panel3Seams',seams,p3)
for i,x in enumerate([-.24,0,.24]):box('Panel3SectionJoint'+str(i),(x-.0004,-.082,-.0043),(x+.0004,.082,-.0039),s,seam,0)
# Solid bridge closes the inherited vertical gap between upper panels and sloping Panel3.
p1=pose(panels['Panel1']['pose']);top=p1@Vector((.245,-.25,-.004));bottom=p3@Vector((0,.09,-.004))
# Bridge grows gently to Panel3 width; front quad plus closed rear offset.
front=[(-.4,top.y,top.z),(.4,top.y,top.z),(.485,bottom.y,bottom.z),(-.485,bottom.y,bottom.z)];verts=front+[(x,y,z-.006) for x,y,z in front]
mesh('UpperToSlopingBridge',verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],faces,paint,.0004)
# Close underside of upper cavity up to its back panel, leaving downstream Panel4/5 to lower-console worker.
rearbottom=p1@Vector((.245,-.25,-.240))
verts=[(-.4,top.y,top.z),(.4,top.y,top.z),(.4,rearbottom.y,rearbottom.z),(-.4,rearbottom.y,rearbottom.z)]
mesh('UpperLowerClosure',verts,[(0,1,2,3)],body,inside)
bpy.context.view_layer.update()
# Self-contained USD, geometry has Cabin-space hierarchy and root identity.
st=Usd.Stage.CreateNew(str(O/'InstrumentConsole.usda'));UsdGeom.SetStageMetersPerUnit(st,1);UsdGeom.SetStageUpAxis(st,'Y');materials={}
for m in bpy.data.materials:
 u=UsdShade.Material.Define(st,'/Materials/'+m.name);sh=UsdShade.Shader.Define(st,'/Materials/'+m.name+'/Surface');sh.CreateIdAttr('UsdPreviewSurface');sh.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3]));sh.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.78);u.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(),'surface');materials[m.name]=u

def emit(o,path):
 path+='/'+o.name;u=UsdGeom.Mesh.Define(st,path) if o.type=='MESH' else UsdGeom.Xform.Define(st,path);m=o.matrix_local;UsdGeom.Xformable(u).AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
 if o.type=='MESH':
  o.data.calc_loop_triangles();pts=[Gf.Vec3f(*v.co) for v in o.data.vertices];u.CreatePointsAttr(pts);u.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles));u.CreateFaceVertexIndicesAttr([v for t in o.data.loop_triangles for v in t.vertices]);u.CreateSubdivisionSchemeAttr('none');u.CreateNormalsAttr([Gf.Vec3f(*t.normal) for t in o.data.loop_triangles for _ in range(3)]);u.SetNormalsInterpolation('faceVarying');u.CreateDoubleSidedAttr(True);u.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(pts));UsdShade.MaterialBindingAPI.Apply(u.GetPrim()).Bind(materials[o.data.materials[0].name])
 for ch in sorted(o.children,key=lambda x:x.name):emit(ch,path)
emit(root,'');st.SetDefaultPrim(st.GetPrimAtPath('/InstrumentConsole'));st.GetRootLayer().Save();st.GetRootLayer().Export(str(O/'InstrumentConsole.usdc'));u=O/'InstrumentConsole.usdz'
if u.exists():u.unlink()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(O/'InstrumentConsole.usdc')),str(u))
bpy.ops.wm.save_as_mainfile(filepath=str(O/'InstrumentConsole.blend'))
# Exact component-root-relative suppression and datum transforms from accepted USD bytes.
stages={};hashes={}
def stage(component):
 if component not in stages:
  f=D/component/(component+'.usdz');stages[component]=Usd.Stage.Open(str(f));hashes[str(f.relative_to(D))]=hashlib.sha256(f.read_bytes()).hexdigest()
 return stages[component]
def item(component,path):
 s=stage(component);p=s.GetPrimAtPath(path);assert p,path;m=UsdGeom.XformCache().GetLocalToWorldTransform(p);r=m.ExtractRotationQuat();return {'component':component,'path':path,'pose':{'position_m':list(m.ExtractTranslation()),'rotation_quaternion_xyzw':list(r.GetImaginary())+[r.GetReal()],'scale':[1,1,1]}}
suppress=[item('CommanderPanels','/CommanderPanels/Panel_1/'+p) for p in ['Panel_1_Shell','Panel_1_Trim','Panel_1_RemovableBacking']]
suppress += [item('PanelInventory','/PanelInventory/Panels/'+p+'/Frame') for p in ['Panel2','Panel3']]
for p in panels.values():suppress += [item('PanelInventory',s['default_placeholder_node']) for s in p['slots']]
protected=[]
for p in panels.values():
 protected.append(item('PanelInventory',p['node']));protected += [item('PanelInventory',s['node']) for s in p['slots']]
protected += [item('Cabin',p) for p in ['/Cabin/Mounts/Mount_Panel_1','/Cabin/Mounts/Mount_Panel_1/Mount_FDAI','/Cabin/Mounts/Mount_Panel_2','/Cabin/Mounts/Mount_Panel_3']]
contract={'schema':'lmkit.console-enclosure.v1','component_id':'InstrumentConsole','root':'/InstrumentConsole','units':'meters','parent_space':'Cabin','root_pose':{'position_m':[0,0,0],'rotation_quaternion_xyzw':[0,0,0,1],'scale':[1,1,1]},'groups':[{'path':'/InstrumentConsole/'+n,'casts_shadows':n=='Enclosure'} for n in ['Faces','Enclosure','Seams']],'suppressions':suppress,'protected_mounts':protected,'dimensions':{'upper_cabin_x_bounds_m':[-.400,.400],'upper_face_panel_local_y_bounds_m':[-.25,.25],'main_face_panel_local_z_m':-.004,'FDAI_rear_cutout_square_m':.130,'CDR_seat_panel_local_z_m':.0118,'LMP_seat_panel_local_z_m':-.004,'panel3_half_width_m':.485,'fit_status':'provisional visual seating, no fabrication or pressure-shell claim'},'availability':'structural overlay only; no occupancy or instrument signal claims','accepted_input_sha256':hashes,'source_reference':'evidence/SI-99-15229h.jpg; Smithsonian LM-2 visual reference, no measured dimensions'}
(O/'interface.json').write_text(json.dumps(contract,indent=2)+'\n')
print('CONSOLE BUILT',len([o for o in bpy.data.objects if o.type=='MESH']),'meshes')
