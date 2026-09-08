"""Reproducible neutral propulsion hardware. Only owned outputs; no simulation algorithms."""
from pathlib import Path
import bpy,json,math,sys
from mathutils import Matrix,Vector
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf,Gf
OUT=Path(__file__).resolve().parent;contract=json.loads((OUT/'interface.json').read_text())
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)
bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1

def material(name,rgb,emission=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);m['emission']=emission;return m
panelmat=material('PanelGray',(.23,.27,.26));rim=material('Bezel',(.036,.045,.043));black=material('DialBlack',(.006,.008,.007));ivory=material('ScaleIvory',(.90,.90,.76),.15);white=material('PointerIvory',(.98,.96,.78),.2);digitmat=material('ELDigits',(.83,.93,.63),.27);rear=material('RearHousing',(.09,.11,.105));red=material('InactivePowerLens',(.075,.009,.007));silver=material('FastenerSteel',(.37,.40,.40))
def node(name,parent=None,loc=(0,0,0)):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;return o

def mesh(name,verts,faces,mat,parent,loc=(0,0,0)):
 d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;d.materials.append(mat);return o

def box(name,size,loc,mat,parent):
 x,y,z=[v/2 for v in size];return mesh(name,[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)],[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],mat,parent,loc)

def label(name,text,loc,size,parent,mat=ivory):
 if not text:return None
 c=bpy.data.curves.new(name,'FONT');c.body=text;c.size=size;c.align_x='CENTER';c.align_y='CENTER';c.extrude=.000012;c.resolution_u=3;o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;c.materials.append(mat);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False);return bpy.context.view_layer.objects.active

def ring(name,w,h,iw,ih,parent):
 g=node(name,parent)
 for suffix,sz,pos in [('L',((w-iw)/2,h,.0018),(-(w+iw)/4,0,.001)),('R',((w-iw)/2,h,.0018),((w+iw)/4,0,.001)),('T',(iw,(h-ih)/2,.0018),(0,(h+ih)/4,.001)),('B',(iw,(h-ih)/2,.0018),(0,-(h+ih)/4,.001))]:box(name+suffix,sz,pos,rim,g)
 return g

def needle(name,parent,park):
 g=node(name,parent,park);verts=[(-.0016,-.001,0),(-.0016,.001,0),(.0022,0,0),(-.0016,-.001,.0002),(-.0016,.001,.0002),(.0022,0,.0002)];mesh('Blade',verts,[(2,1,0),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],white,g);return g
root=node('PropulsionInstruments');fixed=node('ClusterSupport',root)
box('UpperPanelBacking',(.086,.134,.002),(0,0,-.001),panelmat,fixed)
label('MainPropulsionTitle','MAIN PROPULSION',(0,.063,.0014),.003,fixed)
for i,(x,y) in enumerate([(-.040,.063),(.040,.063),(-.040,-.063),(.040,-.063)]):
 bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.0011,depth=.0005,location=(x,y,.0013));o=bpy.context.object;o.name='PanelScrew'+str(i);o.parent=fixed;o.data.materials.append(silver);o.select_set(False);box('ScrewSlot'+str(i),(.0015,.00016,.00006),(x,y,.00158),black,fixed)
parts={};needles={};segments={}
for name in ('Thrust','Temperature','Pressure','ThrustToWeight'):
 r=contract['instruments'][name];w,h,_=r['face_size_m'];g=node(name,root,r['translation_m']);parts[name]=g;f=node('Fixed',g);ng=node('Needles',g)
 box('Housing',(w,h,.014),(0,0,-.007),rear,f);ring('Bezel',w,h,w-.003,h-.003,f);box('DialFace',(w-.003,h-.003,.001),(0,0,.0005),black,f)
 title={'Thrust':'THRUST','Temperature':'TEMP','Pressure':'PRESS','ThrustToWeight':'T/W'}[name];label('Title',title,(0,h/2-.005,.00125),.0028 if name!='ThrustToWeight' else .004,f)
 channels=list(r['needles']);lo,hi=r['domain'];span=r['needles'][channels[0]]['scale_y_m'];nticks=30 if name=='Pressure' else (18 if name=='Temperature' else (20 if name=='Thrust' else 30))
 for c in channels:
  row=r['needles'][c];x=row['valid_translation_x_m'];label('Channel'+c,{'Engine':'ENG','Command':'CMD','Fuel':'FUEL','Oxidizer':'OXID','Axial':''}[c],(x,h/2-.011,.00125),.0017,f)
  for i in range(nticks+1):
   y=span[0]+i/nticks*(span[1]-span[0]);v=lo+i/nticks*(hi-lo)
   major=i%(5 if name in ('Pressure','ThrustToWeight') else 2)==0
   box(c+'Tick'+str(i),(.0014 if major else .0008,.00013,.00008),(x+.0036,y,.0012),ivory,f)
   if major:label(c+'Number'+str(i),str(int(v)) if abs(v-round(v))<1e-8 else f'{v:g}',(x-.0027,y,.00127),.0019 if name!='ThrustToWeight' else .0034,f)
  needles[(name,c)]=needle(c,ng,row['parked_translation_m'])
 unit={'Thrust':'%','Temperature':'F','Pressure':'PSIA','ThrustToWeight':''}[name];label('Unit',unit,(0,-h/2+.0048,.00127),.0022,f)
 # Inactive power-loss lenses only where handbook assigns an electrical lamp. T/W is mechanical.
 if name in ('Thrust','Pressure'):box('PowerFailureLens',(.003,.0012,.00025),(0,h/2-.001,.002),red,f)
for name in ('Quantity','Helium'):
 r=contract['instruments'][name];w,h,_=r['face_size_m'];g=node(name,root,r['translation_m']);parts[name]=g;f=node('Fixed',g);dg=node('Digits',g)
 box('Housing',(w,h,.014),(0,0,-.007),rear,f);ring('Bezel',w,h,w-.003,h-.003,f);box('DarkWindow',(w-.003,h-.003,.001),(0,0,.0005),black,f)
 label('Title','QUANTITY' if name=='Quantity' else 'HELIUM',(0,h/2-.004,.0013),.0023,f)
 for rowindex,rowname in enumerate(r['rows']):
  row=node(rowname,dg);y=(.004 if rowindex==0 else -.012) if name=='Quantity' else -.003
  if name=='Quantity':label(rowname+'Title','OXID' if rowname=='Oxidizer' else 'FUEL',(0,y+.006,.0013),.0018,f)
  count=r['digit_count_per_row'];pitch=.0065;digitw=.0045;digith=.008;thick=.00065
  positions={'A':((0,digith/2),(.0033,thick)),'B':((digitw/2,digith/4),(thick,.0031)),'C':((digitw/2,-digith/4),(thick,.0031)),'D':((0,-digith/2),(.0033,thick)),'E':((-digitw/2,-digith/4),(thick,.0031)),'F':((-digitw/2,digith/4),(thick,.0031)),'G':((0,0),(.0033,thick))}
  for i in range(count):
   digit=node('Digit'+str(i+1),row,((i-(count-1)/2)*pitch,y,0))
   for s,(xy,sz) in positions.items():segments[(name,rowname,i,s)]=box('Segment'+s,(*sz,.00013),(*xy,r['parked_segment_z_m']),digitmat,digit)
# Scale mapping is metadata only; no source signal is invented in neutral export.
bpy.context.view_layer.update()
def export():
 stage=Usd.Stage.CreateNew(str(OUT/'PropulsionInstruments.usda'));UsdGeom.SetStageMetersPerUnit(stage,1);UsdGeom.SetStageUpAxis(stage,'Y');mats={}
 for m in bpy.data.materials:
  u=UsdShade.Material.Define(stage,'/Materials/'+m.name);s=UsdShade.Shader.Define(stage,'/Materials/'+m.name+'/Surface');s.CreateIdAttr('UsdPreviewSurface');s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3]));s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.8)
  if m.get('emission'):s.CreateInput('emissiveColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*[v*m['emission'] for v in m.diffuse_color[:3]]))
  u.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface');mats[m.name]=u
 def emit(o,path):
  path+='/'+o.name.split('.')[0];u=UsdGeom.Mesh.Define(stage,path) if o.type=='MESH' else UsdGeom.Xform.Define(stage,path);m=o.matrix_local;UsdGeom.Xformable(u).AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
  if o.type=='MESH':
   o.data.calc_loop_triangles();pts=[Gf.Vec3f(*v.co) for v in o.data.vertices];u.CreatePointsAttr(pts);u.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles));u.CreateFaceVertexIndicesAttr([v for t in o.data.loop_triangles for v in t.vertices]);u.CreateSubdivisionSchemeAttr('none');u.CreateDoubleSidedAttr(True);u.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(pts));UsdShade.MaterialBindingAPI.Apply(u.GetPrim()).Bind(mats[o.data.materials[0].name])
  for c in sorted(o.children,key=lambda x:x.name):emit(c,path)
 emit(root,'');stage.SetDefaultPrim(stage.GetPrimAtPath('/PropulsionInstruments'));stage.GetRootLayer().Save();stage.GetRootLayer().Export(str(OUT/'PropulsionInstruments.usdc'))
 path=OUT/'PropulsionInstruments.usdz'
 if path.exists():path.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'PropulsionInstruments.usdc')),str(path))
export();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'PropulsionInstruments.blend'))
if '--preview' in sys.argv:
 scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1000;scene.render.resolution_y=1400;scene.render.resolution_percentage=100;scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=False;scene.display.shading.show_cavity=True;scene.world.color=(.07,.07,.07)
 d=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',d);bpy.context.collection.objects.link(cam);cam.location=(0,-.075,.35);d.type='ORTHO';d.ortho_scale=.32;scene.camera=cam
 review=OUT/'review';review.mkdir(exist_ok=True)
 review_label=label('ReviewOnlyNeutral','NEUTRAL - SIGNALS UNAVAILABLE',(0,.078,.02),.003,None)
 scene.render.filepath=str(review/'neutral-unavailable.png');bpy.ops.render.render(write_still=True)
 vals={('Thrust','Engine'):50,('Thrust','Command'):52,('Temperature','Fuel'):65,('Temperature','Oxidizer'):68,('Pressure','Fuel'):220,('Pressure','Oxidizer'):230,('ThrustToWeight','Axial'):1.6}
 for k,o in needles.items():
  r=contract['instruments'][k[0]];v=vals[k];n=r['needles'][k[1]];lo,hi=r['domain'];y0,y1=n['scale_y_m'];o.location=(n['valid_translation_x_m'],y0+(v-lo)/(hi-lo)*(y1-y0),n['valid_translation_z_m'])
 masks={0:'ABCDEF',1:'BC',2:'ABDEG',3:'ABCDG',4:'BCFG',5:'ACDFG',6:'ACDEFG',7:'ABC',8:'ABCDEFG',9:'ABCDFG'};demo={('Quantity','Oxidizer'):'73',('Quantity','Fuel'):'74',('Helium','Pressure'):'2400'}
 for (instrument,row,i,s),o in segments.items():o.location.z=.002 if s in masks[int(demo[instrument,row][i])] else -.003
 review_label.hide_render=True
 label('ReviewOnlySynthetic','SYNTHETIC REVIEW VALUES - NOT LIVE',(0,.078,.02),.003,None)
 scene.render.filepath=str(review/'synthetic-layout-example.png');bpy.ops.render.render(write_still=True)
print('PROPULSION BUILD COMPLETE')
