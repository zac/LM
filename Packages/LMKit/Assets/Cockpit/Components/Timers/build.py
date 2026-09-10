"""Timer readouts and detached control banks. Helper provenance: AltitudeRate/build.py
at LMKit035c5b3, derived from WindowsLPD/Cabin physical-axis exporter.
No clock simulation is implemented here. See interface.json/EVIDENCE.md.
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
from pxr import Usd, UsdGeom, UsdShade, UsdUtils, Gf, Sdf
OUT=Path(__file__).resolve().parent
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
def v(p): return C.to_3x3()@Vector(p)
def pose(p=(0,0,0),r=None):
 m=Matrix.Translation(Vector(p))
 if r is not None: m=m@r.to_4x4()
 return C@m@C.inverted()
def material(name,color):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); return m
def node(name,p=(0,0,0),r=None,parent=None):
 o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.parent=parent
 o.matrix_local=pose(p,r); o['qualification']='approximate visual reconstruction; see EVIDENCE.md'; return o
def mesh(name,verts,faces,mat,parent,p=(0,0,0),r=None):
 name=name.replace('-','N'); data=bpy.data.meshes.new(name); data.from_pydata([v(x) for x in verts],[],faces); data.update()
 o=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(o); o.parent=parent; o.matrix_local=pose(p,r); o.data.materials.append(mat)
 o['qualification']='provisional visual geometry'; return o
def box(name,size,p,mat,parent,r=None):
 x,y,z=[n/2 for n in size]
 return mesh(name,[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)],[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],mat,parent,p,r)
def beam(name,a,b,width,mat,parent):
 a,b=Vector(a),Vector(b); d=b-a
 return box(name,(width,d.length,width),(a+b)/2,mat,parent,Vector((0,1,0)).rotation_difference(d.normalized()).to_matrix())
def rx(deg): return Matrix.Rotation(math.radians(deg),3,'X')
def prism(name,points,normal,thick,mat,parent):
 pts=[Vector(p) for p in points]; n=Vector(normal)*thick
 # orient source face toward normal; closed solid with outward normals
 if (pts[1]-pts[0]).cross(pts[2]-pts[0]).dot(n)<0: pts.reverse()
 k=len(pts); verts=pts+[p-n for p in pts]
 faces=[tuple(range(k)),tuple(reversed(range(k,2*k)))]+[(i,(i+k)%k+k,(i+1)%k+k,(i+1)%k) for i in range(k)]
 return mesh(name,verts,faces,mat,parent)
def export(root):
 name=root.name
 stage=Usd.Stage.CreateNew(str(OUT/(name+'.usda'))); UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1)
 mats={}
 for m in bpy.data.materials:
  path='/Materials/'+m.name; u=UsdShade.Material.Define(stage,path); s=UsdShade.Shader.Define(stage,path+'/Surface'); s.CreateIdAttr('UsdPreviewSurface')
  s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3])); s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(m.get('roughness',.5))
  s.CreateInput('opacity',Sdf.ValueTypeNames.Float).Set(m.diffuse_color[3])
  u.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface'); mats[m.name]=u
 def emit(o,path):
  path=path+'/'+o.name
  prim=UsdGeom.Mesh.Define(stage,path) if o.type=='MESH' else UsdGeom.Xform.Define(stage,path)
  m=C.inverted()@o.matrix_local@C
  UsdGeom.Xformable(prim).AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
  if o.type=='MESH':
   o.data.calc_loop_triangles(); points=[Gf.Vec3f(*(C.inverted().to_3x3()@p.co)) for p in o.data.vertices]
   prim.CreatePointsAttr(points); prim.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles)); prim.CreateFaceVertexIndicesAttr([i for t in o.data.loop_triangles for i in t.vertices]); prim.CreateSubdivisionSchemeAttr('none'); prim.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(points))
   prim.CreateNormalsAttr([Gf.Vec3f(*(C.inverted().to_3x3()@t.normal)) for t in o.data.loop_triangles]); prim.SetNormalsInterpolation('uniform')
   UsdShade.MaterialBindingAPI.Apply(prim.GetPrim()).Bind(mats[o.data.materials[0].name])
  prim.GetPrim().SetCustomDataByKey('qualification',o.get('qualification','proposed'))
  for child in sorted(o.children,key=lambda c:c.name): emit(child,path)
 emit(root,''); stage.SetDefaultPrim(stage.GetPrimAtPath('/'+name)); stage.GetRootLayer().Save(); stage.GetRootLayer().Export(str(OUT/(name+'.usdc')))
 target=OUT/(name+'.usdz')
 if target.exists(): target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/(name+'.usdc'))),str(target))
def text(name,string,position,size,mat,parent,align='CENTER'):
 cu=bpy.data.curves.new(name,'FONT');cu.body=string;cu.size=size;cu.align_x=align;cu.align_y='CENTER';cu.resolution_u=2
 o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False)
 for pt in o.data.vertices:pt.co=v(pt.co)
 o.parent=parent;o.matrix_local=pose(position);o.data.materials.append(mat);return o

def initialize():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for m in list(bpy.data.materials):bpy.data.materials.remove(m)
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
 colors={'Timer_EL_Off':(.018,.027,.021),'Bezel_Dark':(.026,.032,.029),'Face_Gray':(.25,.275,.26),'Legend_Ivory':(.75,.76,.69),'Metal':(.44,.46,.43),'Rubber':(.015,.018,.016),'Lens_Clear':(.7,.75,.7)}
 mats={n:material(n,c) for n,c in colors.items()}
 for m in mats.values():m['roughness']=.75
 mats['Lens_Clear'].diffuse_color[3]=.012;mats['Lens_Clear']['roughness']=.18
 return mats

def numeral_segment(name,p,length,width,vertical,mat,parent):
 # Six-vertex EL segment, separate mesh and source-correct seven-segment mechanism.
 L=length/2;W=width/2;verts=[(-L+W,-W,0),(L-W,-W,0),(L,0,0),(L-W,W,0),(-L+W,W,0),(-L,0,0)]
 if vertical:verts=[(-y,x,z) for x,y,z in verts]
 return mesh(name,verts,[(0,1,2,3,4,5)],mat,parent,p)

def screw(name,x,y,mat,parent):
 prism(name,[(x+.0016*math.cos(t*math.tau/12),y+.0016*math.sin(t*math.tau/12),.004) for t in range(12)],(0,0,1),.0012,mat,parent)

def make_readout(a,m):
 root=node(a['root']);fixed=node(a['root']+'_Fixed',parent=root);w,h,d=a['size_m']
 box(a['root']+'_Housing',(.116 if a['root']=='MissionTimer' else w-.003,h-.003,.015),(0,0,-.006),m['Bezel_Dark'],fixed)
 box(a['root']+'_MountingFace',(w,h,.003),(0,0,.001),m['Face_Gray'],fixed)
 box(a['root']+'_ReadoutBacking',(w-.012,.017,.001),(0,-.001,.003),m['Bezel_Dark'],fixed)
 for x in [-w/2+.003,w/2-.003]:
  for y in [-h/2+.003,h/2-.003]:screw(a['root']+'_Fastener_'+str(round(x*1000))+'_'+str(round(y*1000)),x,y,m['Metal'],fixed)
 readout=node(a['root']+'_Readout',parent=root)
 for dg in a['digits']:
  group=node(dg['name'],dg['position_m'],parent=readout)
  for segment,(x,y,vertical,length) in {'A':(0,.005,False,.0064),'B':(.0034,.0025,True,.0045),'C':(.0034,-.0025,True,.0045),'D':(0,-.005,False,.0064),'E':(-.0034,-.0025,True,.0045),'F':(-.0034,.0025,True,.0045),'G':(0,0,False,.0064)}.items():
   numeral_segment(dg['segments'][segment],(x,y,0),length,.00085,vertical,m['Timer_EL_Off'],group)
 if a['root']=='MissionTimer':
  for label,x in [('HOURS',-.029),('MIN',.0055),('SEC',.0345)]:text(a['root']+'_Legend_'+label,label,(x,.011,.003),.0028,m['Legend_Ivory'],fixed)
  fork=node(a['power_failure_indicator'],(-.051,-.001,.0045),parent=root)
  for nm,loc,size in [('L',(-.001,.001,0),(.0005,.005,.0001)),('R',(.001,.001,0),(.0005,.005,.0001)),('Bar',(0,-.0015,0),(.0025,.0005,.0001)),('Stem',(0,-.003,0),(.0005,.003,.0001))]:box(a['root']+'_Fork_'+nm,size,loc,m['Timer_EL_Off'],fork)
 else:
  for label,x in [('MIN',-.0185),('SEC',.0165)]:text(a['root']+'_Legend_'+label,label,(x,.011,.003),.0028,m['Legend_Ivory'],fixed)
 text(a['root']+'_Name','MISSION TIMER' if a['root']=='MissionTimer' else 'EVENT TIMER',(0,-.012,.003),.0027,m['Legend_Ivory'],fixed)
 lens=node(a['protective_lens'],parent=root);box(a['root']+'_LensMesh',(w-.011,.018,.0006),(0,-.001,.0053),m['Lens_Clear'],lens)
 return root

def make_controls(a,m):
 root=node(a['root']);fixed=node(a['root']+'_Fixed',parent=root);w,h,d=a['size_m'];box(a['root']+'_Plate',(w,h,.003),(0,0,0),m['Face_Gray'],fixed)
 text(a['root']+'_Heading','MISSION TIMER' if a['root'].startswith('Mission') else 'EVENT TIMER',(0,.027,.002),.004,m['Legend_Ivory'],fixed)
 for x in [-w/2+.004,w/2-.004]:
  for y in [-h/2+.004,h/2-.004]:screw(a['root']+'_Screw_'+str(round(x*1000))+'_'+str(round(y*1000)),x,y,m['Metal'],fixed)
 for c in a['controls']:
  x,y,z=c['position_m'];piv=node(c['pivot'],(x,y,z),parent=root)
  # Neutral lever along +Z; negative Xrotation throws top(+Y), positive throws down(-Y).
  beam(c['stem'],(0,0,0),(0,0,.016),.0028,m['Metal'],piv)
  box(c['id']+'_Grip',(.0055,.0055,.005),(0,0,.017),m['Legend_Ivory'],piv)
  prism(c['id']+'_Nut',[(x+.0048*math.cos(t*math.tau/6),y+.0048*math.sin(t*math.tau/6),.0025) for t in range(6)],(0,0,1),.002,m['Metal'],fixed)
  title='HOURS' if 'Hours' in c['id'] else 'MIN' if 'Minutes' in c['id'] else 'SEC' if 'Seconds' in c['id'] else 'RESET/COUNT' if 'ResetCount' in c['id'] else 'TIMER CONT'
  text(c['id']+'_Title',title,(x,.019,.002),.0031,m['Legend_Ivory'],fixed)
  text(c['id']+'_TopLabel',c['positions'][0],(x,.009,.002),.0032,m['Legend_Ivory'],fixed)
  if c['positions'][1]!='CENTER':text(c['id']+'_CenterLabel',c['positions'][1],(x+.010,y,.002),.003,m['Legend_Ivory'],fixed,align='LEFT')
  text(c['id']+'_BottomLabel',c['positions'][2],(x,-.022,.002),.0032,m['Legend_Ivory'],fixed)
 return root

def main():
 c=json.loads((OUT/'interface.json').read_text())
 for a in c['assets']:
  m=initialize();root=make_readout(a,m) if a['kind']=='readout' else make_controls(a,m)
  bpy.context.view_layer.update();bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(root.name+'.blend')));export(root);print('EXPORTED',root.name)
if __name__=='__main__':main()
