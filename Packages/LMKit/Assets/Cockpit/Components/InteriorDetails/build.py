"""Blender --background --factory-startup --python build.py
Optional visual-only interior overlay. Geometry is reconstructed, not surveyed.
Authoring Z-up; published USD meters, Y-up, +X right, -Z forward.
"""
import bpy,bmesh,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf,Gf
D=Path(__file__).resolve().parent
C=Matrix.Rotation(math.pi/2,4,'X')
def B(p):return C.to_3x3()@Vector(p)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
materials={}
def material(name,rgb,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*rgb,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.64
 materials[name]=(m,metal);return m
material('CableSleeveIvory',(.54,.51,.39));material('CableSleeveDark',(.09,.10,.095));material('ClampAluminum',(.38,.40,.38),.65);material('ClampLiner',(.055,.06,.05));material('TrimGray',(.43,.46,.43),.35);material('FastenerSteel',(.46,.49,.48),.7);material('FastenerSlot',(.06,.065,.06))
def node(name,parent=None):
 o=bpy.data.objects.new(name,None);scene.collection.objects.link(o);o.parent=parent;return o
root=node('InteriorDetails');root['qualification']='optional visual overlay; all dimensions provisional'
groups={}
def group(name):groups[name]=node(name,root);return groups[name]
def mesh(name,points,faces,mat,parent):
 name=name.replace('-','N').replace('.','_')
 me=bpy.data.meshes.new(name);me.from_pydata([B(p) for p in points],[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
 o=bpy.data.objects.new(name,me);scene.collection.objects.link(o);o.parent=parent;o.data.materials.append(materials[mat][0]);return o
def box(name,center,size,mat,parent):
 x,y,z=(n/2 for n in size);p=Vector(center);v=[p+Vector(q) for q in [(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)]]
 return mesh(name,v,[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],mat,parent)
def tube(name,path,radius,mat,parent,sides=8):
 pts=[Vector(p) for p in path];verts=[]
 for i,p in enumerate(pts):
  tangent=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized();seed=Vector((1,0,0))
  if abs(tangent.dot(seed))>.9:seed=Vector((0,1,0))
  u=tangent.cross(seed).normalized();v=tangent.cross(u).normalized()
  for j in range(sides):verts.append(p+radius*(u*math.cos(j*2*math.pi/sides)+v*math.sin(j*2*math.pi/sides)))
 faces=[tuple(reversed(range(sides))),tuple(range((len(pts)-1)*sides,len(pts)*sides))]
 for i in range(len(pts)-1):
  for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
 return mesh(name,verts,faces,mat,parent)
def screw(name,sign,y,z,parent):
 # Low-poly recessed slotted round screw head normal to side wall, with dark slot.
 x=sign*1.1597;tube(name,[(x,y,z),(x-sign*.002,y,z)],.0033,'FastenerSteel',parent,10)
 box(name+'_Slot',(x-sign*.00215,y,z),(.0003,.0008,.0046),'FastenerSlot',parent)
def clamp(name,sign,y,z,parent):
 # Rectangular bent strip bridges the four parallel sleeves, padded at contact.
 for off in [-.029,.029]:
  box(name+'_Foot'+str(off),(sign*1.165,y+off,z),(.004,.013,.014),'ClampAluminum',parent)
  screw(name+'_Screw'+str(off),sign,y+off,z,parent)
 box(name+'_Bridge',(sign*1.140,y,z),(.003,.055,.012),'ClampAluminum',parent)
 for off in [-.027,.027]:box(name+'_Return'+str(off),(sign*1.153,y+off,z),(.026,.003,.012),'ClampAluminum',parent)
 box(name+'_Liner',(sign*1.143,y,z),(.002,.045,.011),'ClampLiner',parent)
# Four parallel sleeves with gentle route offsets, restrained near the lower outboard liner.
for side,sign in [('CDR',-1),('LMP',1)]:
 g=group(side+'LowerCableHarness')
 # Main horizontal route deliberately well below the trays and slot envelopes.
 for n in range(4):
  offset=(n-1.5)*.011
  pts=[(sign*1.151,.245+offset,-.31),(sign*1.151,.245+offset,-.22),(sign*1.151,.248+offset,-.13),(sign*1.151,.255+offset,-.04),(sign*1.151,.265+offset,.08),(sign*1.151,.265+offset,.34),(sign*1.151,.265+offset,.58),(sign*1.151,.27+offset,.72),(sign*1.151,.285+offset,.79)]
  tube(side+'_Sleeve_%02d'%n,pts,.0042,'CableSleeveIvory' if n<3 else 'CableSleeveDark',g)
 for i,(y,z) in enumerate([(.245,-.22),(.258,0),(.265,.26),(.265,.53),(.279,.76)]):clamp(side+'_HarnessClamp_%02d'%i,sign,y,z,g)
 g=group(side+'LinerEdgeTrim')
 # Narrow L section at the wall/deck join; no new floor-spanning obstruction.
 box(side+'_DeckEdgeVertical',(sign*1.164,.15,.305),(.005,.030,1.49),'TrimGray',g)
 box(side+'_DeckEdgeFoot',(sign*1.151,.136,.305),(.027,.003,1.49),'TrimGray',g)
 # Seams near forward/aft ends, narrow raised straps with discrete screws.
 for j,z in enumerate([-.425,1.025]):
  height=.50 if j==0 else .85
  box(side+'_SeamStrap_%d'%j,(sign*1.164,.16+height/2,z),(.005,height,.014),'TrimGray',g)
  for i,y in enumerate([.19,.35,.52,.64] if j==0 else [.19,.35,.52,.69,.86,.98]):screw(side+'_SeamFastener_%d_%d'%(j,i),sign,y,z,g)
 for i,z in enumerate([-.35,-.08,.19,.46,.73,.98]):screw(side+'_DeckFastener_%02d'%i,sign,.15,z,g)
# Forward upper-side detail follows existing Cabin facets, not a hypothetical cylinder.
# Two facet-width seam bands and a pair of restrained sleeves per station.
RADIUS=1.1684;angle=math.asin(.43/RADIUS)
arc=[Vector((RADIUS*math.sin(angle+(math.pi/2-angle)*i/12),1.1+RADIUS*math.cos(angle+(math.pi/2-angle)*i/12),0)) for i in range(13)]
def beam_between(name,a,b,width,depth,normal,mat,parent):
 a,b=Vector(a),Vector(b);along=(b-a).normalized();normal=Vector(normal).normalized();across=along.cross(normal).normalized()*width/2;n=normal*depth/2
 points=[a-across-n,a-across+n,a+across-n,a+across+n,b-across-n,b-across+n,b+across-n,b+across+n]
 return mesh(name,points,[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],mat,parent)
for side,sign in [('CDR',-1),('LMP',1)]:
 g=group(side+'UpperLinerDetails')
 for facet in [3,4]:
  a,b=arc[facet].copy(),arc[facet+1].copy();a.x*=sign;b.x*=sign
  mid=(a+b)/2;out=Vector((mid.x,mid.y-1.1,0)).normalized()
  for band,z in enumerate([-.435,.465]):
   aa=a-out*.006;bb=b-out*.006;aa.z=bb.z=z
   beam_between(side+'_UpperSeam_%d_%d'%(facet,band),aa,bb,.012,.003,out,'TrimGray',g)
   for ix,fraction in enumerate([.15,.85]):
    p=aa.lerp(bb,fraction)-out*.003
    tube(side+'_UpperSeamBolt_%d_%d_%d'%(facet,band,ix),[p,p-out*.002],.0032,'FastenerSteel',g,10)
 # Centerline lies on facet 4; offset inward enough to keep sleeve/clamp clear of liner.
 a,b=arc[4].copy(),arc[5].copy();a.x*=sign;b.x*=sign
 mid=(a+b)/2;out=Vector((mid.x,mid.y-1.1,0)).normalized();along=(b-a).normalized()
 for sleeve,offset in enumerate([-.007,.007]):
  pts=[]
  for z in [-.40,-.32,-.18,0,.18,.35,.43]:
   p=mid+along*offset-out*.016;p.z=z;pts.append(p)
  tube(side+'_UpperSleeve_%d'%sleeve,pts,.0036,'CableSleeveIvory' if sleeve==0 else 'CableSleeveDark',g)
 for clampindex,z in enumerate([-.35,-.08,.20,.39]):
  ctr=mid-out*.024;ctr.z=z
  beam_between(side+'_UpperClampBridge_%d'%clampindex,ctr-along*.018,ctr+along*.018,.01,.002,out,'ClampAluminum',g)
  for ix,sgn in enumerate([-1,1]):
   end=mid+along*.018*sgn;end.z=z
   beam_between(side+'_UpperClampReturn_%d_%d'%(clampindex,ix),end-out*.005,end-out*.024,.01,.002,along,'ClampAluminum',g)
   # Stub pads and screw heads attach near the existing liner without piercing it.
   beam_between(side+'_UpperClampPad_%d_%d'%(clampindex,ix),end-out*.005,end+along*sgn*.011-out*.005,.012,.002,out,'ClampAluminum',g)
   bolt=end+along*sgn*.007-out*.008
   tube(side+'_UpperClampBolt_%d_%d'%(clampindex,ix),[bolt,bolt-out*.002],.0027,'FastenerSteel',g,10)
# Plain seam straps above the forward instrument panel stay behind all equipment.
# The supporting Cabin surface is the existing Forward_Above_Hatch plane z=-1.02.
g=group('ForwardHeaderTrim')
box('ForwardHeader_Seam',(0,2.10,-1.014),(.80,.012,.003),'TrimGray',g)
for side,sign in [('CDR',-1),('LMP',1)]:
 box(side+'_HeaderReturn',(sign*.36,1.985,-1.014),(.012,.23,.003),'TrimGray',g)
 for n,y in enumerate([1.89,2.0,2.10]):
  tube(side+'_HeaderReturnBolt_%d'%n,[(sign*.36,y,-1.011),(sign*.36,y,-1.008)],.0033,'FastenerSteel',g,10)
for n,x in enumerate([-.27,-.135,0,.135,.27]):
 tube('ForwardHeader_Bolt_%d'%n,[(x,2.1,-1.011),(x,2.1,-1.008)],.0033,'FastenerSteel',g,10)
# Phase 2: shallow cover frames and mesh inserts, following existing liner surfaces.
# Open mesh centers are actual openings; no alpha cards, texture decals or new lights.
material('LinerCream',(.67,.66,.56));material('LinerMesh',(.39,.40,.34),.15)
def plane_box(name,center,u,v,n,size,mat,parent):
 center,u,v,n=Vector(center),Vector(u),Vector(v),Vector(n);a,b,c=(f/2 for f in size)
 pts=[center+u*x*a+v*y*b+n*z*c for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
 return mesh(name,pts,[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],mat,parent)
def insert(name,center,u,v,n,width,length,parent):
 center,u,v,n=Vector(center),Vector(u),Vector(v),Vector(n)
 # Closed sheet bands around a physical open lattice: plain solid margins retain liner vocabulary.
 border=.017;thick=.002
 for side in [-1,1]:
  plane_box(name+'_CoverSide_'+str(side),center+u*side*(width-border)/2,u,v,n,(border,length,thick),'LinerCream',parent)
  plane_box(name+'_CoverEnd_'+str(side),center+v*side*(length-border)/2,u,v,n,(width-2*border,border,thick),'LinerCream',parent)
 innerw=width-2*border;innerl=length-2*border
 # Bars are 1mm wide; these are generic mesh/perforation approximations, not a surveyed hole pattern.
 countw=max(2,round(innerw/.012));countl=max(2,round(innerl/.012))
 for j in range(countw+1):
  pos=center+u*(-innerw/2+innerw*j/countw)-n*.0012
  plane_box(name+'_MeshLong_%02d'%j,pos,u,v,n,(.001,innerl,.0007),'LinerMesh',parent)
 for j in range(countl+1):
  pos=center+v*(-innerl/2+innerl*j/countl)-n*.0020
  plane_box(name+'_MeshCross_%02d'%j,pos,u,v,n,(innerw,.001,.0007),'LinerMesh',parent)
 for j,(a,b) in enumerate([(-1,-1),(-1,1),(1,-1),(1,1)]):
  pos=center+u*a*(width/2-.008)+v*b*(length/2-.008)+n*.002
  tube(name+'_CoverScrew_%d'%j,[pos,pos+n*.0018],.0027,'FastenerSteel',parent,10)
roof=1.1+math.sqrt(RADIUS*RADIUS-.43*.43)
g=group('ForwardOverheadLiner')
for side,sign in [('CDR',-1),('LMP',1)]:
 insert(side+'_OverheadCover',(sign*.255,roof-.007,-.73),(1,0,0),(0,0,1),(0,-1,0),.245,.35,g)
# Rear portions of crown facets 1/2 remain clear of the docking and transfer apertures.
for side,sign in [('CDR',-1),('LMP',1)]:
 g=group(side+'AftCrownInserts')
 a,b=arc[2].copy(),arc[3].copy();a.x*=sign;b.x*=sign
 mid=(a+b)/2;out=Vector((mid.x,mid.y-1.1,0)).normalized();u=(b-a).normalized()
 center=mid-out*.006;center.z=.67
 insert(side+'_AftLinerCover',center,u,(0,0,1),-out,.096,.48,g)
# A restrained pair of exposed header sleeves is visible above the control stack.
g=group('ForwardHeaderCableRun')
for j,y in enumerate([2.044,2.056]):
 tube('HeaderSleeve_%d'%j,[(-.33,y,-1.005),(-.20,y,-1.003),(0,y,-1.003),(.20,y,-1.003),(.33,y,-1.005)],.0032,'CableSleeveIvory' if j==0 else 'CableSleeveDark',g)
for j,x in enumerate([-.28,-.095,.095,.28]):
 plane_box('HeaderClampBridge_%d'%j,(x,2.05,-.997),(1,0,0),(0,1,0),(0,0,1),(.009,.035,.002),'ClampAluminum',g)
 for k,sgn in enumerate([-1,1]):
  plane_box('HeaderClampReturn_%d_%d'%(j,k),(x,2.05+sgn*.017,-1.005),(1,0,0),(0,1,0),(0,0,1),(.009,.002,.016),'ClampAluminum',g)
  tube('HeaderClampScrew_%d_%d'%(j,k),[(x,2.05+sgn*.023,-1.011),(x,2.05+sgn*.023,-1.008)],.0025,'FastenerSteel',g,10)
# Static fittings are attached to the closed leaf surfaces only. No hatch hinge/action claim.
def u_handle(name,a,b,n,parent):
 a,b,n=Vector(a),Vector(b),Vector(n)
 tube(name+'_Grip',[a,a+n*.035,b+n*.035,b],.006,'ClampAluminum',parent,10)
 for j,p in enumerate([a,b]):
  tube(name+'_Foot_%d'%j,[p-n*.002,p+n*.003],.012,'TrimGray',parent,12)
  tube(name+'_FootScrew_%d'%j,[p+n*.004,p+n*.006],.003,'FastenerSteel',parent,10)
g=group('ForwardHatchFittings')
# Existing leaf front field reaches z=-.993; preserve separate rib footprints at x±.23.
u_handle('ForwardHatch_ProvisionalGrip',(-.095,.47,-.987),(-.095,.62,-.987),(0,0,1),g)
for j,(x,y) in enumerate([(x,y) for x in [-.34,.34] for y in [.25,.45,.65,.85]]+[(x,y) for x in [-.16,.0,.16] for y in [.20,.90]]):
 tube('ForwardHatch_Fastener_%02d'%j,[(x,y,-.985),(x,y,-.982)],.0038,'FastenerSteel',g,10)
# Small plain boss around the handle base is deliberately unnamed as a latch subsystem.
plane_box('ForwardHatch_HandleBacking',(-.095,.545,-.990),(1,0,0),(0,1,0),(0,0,1),(.045,.195,.003),'TrimGray',g)
g=group('TransferHatchFittings')
u_handle('TransferHatch_ProvisionalGrip',(-.075,roof-.007,.45),(.075,roof-.007,.45),(0,-1,0),g)
for j in range(20):
 t=2*math.pi*j/20;point=Vector((.36*math.cos(t),roof-.004,.65+.36*math.sin(t)))
 tube('TransferHatch_Fastener_%02d'%j,[point,point+Vector((0,-.003,0))],.0035,'FastenerSteel',g,10)
# Export a minimal USD graph: no behaviors, collisions, lights, cameras or input metadata.
bpy.context.view_layer.update()
def emit_usd():
 st=Usd.Stage.CreateNew(str(D/'InteriorDetails.usda'));UsdGeom.SetStageUpAxis(st,'Y');UsdGeom.SetStageMetersPerUnit(st,1)
 bound={}
 for name,(m,metal) in materials.items():
  u=UsdShade.Material.Define(st,'/Materials/'+name);s=UsdShade.Shader.Define(st,'/Materials/'+name+'/Surface');s.CreateIdAttr('UsdPreviewSurface');s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3]));s.CreateInput('metallic',Sdf.ValueTypeNames.Float).Set(metal);s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.64);u.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface');bound[name]=u
 def emit(o,parent):
  path=parent+'/'+o.name;p=UsdGeom.Mesh.Define(st,path) if o.type=='MESH' else UsdGeom.Xform.Define(st,path)
  if o.type=='MESH':
   o.data.calc_loop_triangles();v=[Gf.Vec3f(*(C.inverted().to_3x3()@p.co)) for p in o.data.vertices];p.CreatePointsAttr(v);p.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles));p.CreateFaceVertexIndicesAttr([i for t in o.data.loop_triangles for i in t.vertices]);p.CreateSubdivisionSchemeAttr('none');p.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(v));p.CreateDoubleSidedAttr(False);UsdShade.MaterialBindingAPI.Apply(p.GetPrim()).Bind(bound[o.data.materials[0].name])
  for c in sorted(o.children,key=lambda c:c.name):emit(c,path)
 emit(root,'');st.SetDefaultPrim(st.GetPrimAtPath('/InteriorDetails'));st.GetRootLayer().Save();st.GetRootLayer().Export(str(D/'InteriorDetails.usdc'))
 target=D/'InteriorDetails.usdz'
 if target.exists():target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(D/'InteriorDetails.usdc')),str(target))
emit_usd()
# Review metadata also establishes inexpensive geometry budgets and removable groups.
entries=[];total=0
for name,g in groups.items():
 points=[];tris=0
 for o in g.children_recursive:
  if o.type=='MESH':
   o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles);points += [C.inverted().to_3x3()@v.co for v in o.data.vertices]
 total+=tris;entries.append({'name':name,'path':'/InteriorDetails/'+name,'aabb_cabin_m':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'triangles':tris,'removable':True})
meta={'schema':'lmkit.interior-details.v1','root':'/InteriorDetails','root_pose':{'translation_m':[0,0,0],'quaternion_xyzw':[0,0,0,1],'scale':[1,1,1]},'axes':'+X right, +Y up, -Z forward','meters_per_unit':1,'installation':'identity Cabin-relative; optional additive sibling; never hides slots','base_commit':'035c5b3','groups':entries,'triangles':total,'material_count':len(materials),'simulation':'none','input':'none','collisions':'none','lights':'none','dimensions':'all provisional visual reconstruction; not fabrication','hatch_fittings':'static closed-leaf visual groups; disable or reparent if a future host opens/removes either hatch','preserved_groups_evidence':'evidence/phase1-group-fingerprints.json','artifact_sha256':hashlib.sha256((D/'InteriorDetails.usdz').read_bytes()).hexdigest()}
(D/'interface.json').write_text(json.dumps(meta,indent=2)+'\n')
assert total<15000,total
bpy.ops.wm.save_as_mainfile(filepath=str(D/'InteriorDetails.blend'))
print('INTERIOR_DETAILS',total,'triangles',len(entries),'groups')
