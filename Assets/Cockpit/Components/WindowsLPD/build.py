"""WindowsLPD reproducible builder. Shared mesh/export helpers adapted from Cabin/build.py
at 09364460e8be570338f3d39a07067fe2bee0b044; original provenance preserved.
Run Blender headless; no simulation or external dependencies.
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
 stage=Usd.Stage.CreateNew(str(OUT/'WindowsLPD.usda')); UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1)
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
 emit(root,''); stage.SetDefaultPrim(stage.GetPrimAtPath('/WindowsLPD')); stage.GetRootLayer().Save(); stage.GetRootLayer().Export(str(OUT/'WindowsLPD.usdc'))
 target=OUT/'WindowsLPD.usdz'
 if target.exists(): target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'WindowsLPD.usdc')),str(target))
def rounded(poly,trim=.020,steps=8):
 result=[]
 for i,b in enumerate(poly):
  a,c=poly[i-1],poly[(i+1)%len(poly)]
  start=b+(a-b).normalized()*trim; end=b+(c-b).normalized()*trim
  for j in range(steps+1):
   t=j/steps; result.append((1-t)**2*start+2*t*(1-t)*b+t*t*end)
 return result

def offset(poly,d):
 # Convex polygon parallel edge intersection: actual constant-width frame band.
 center=sum(poly,Vector())/len(poly); out=[]
 for i,b in enumerate(poly):
  a,c=poly[i-1],poly[(i+1)%len(poly)]
  e1=(b-a).normalized(); e2=(c-b).normalized()
  n1=Vector((-e1.y,e1.x,0)); n2=Vector((-e2.y,e2.x,0))
  if n1.dot(center-b)>0:n1=-n1
  if n2.dot(center-b)>0:n2=-n2
  bis=(n1+n2).normalized(); out.append(b+bis*(d/bis.dot(n1)))
 return out

def ring(name,inner,outer,z,depth,mat,parent):
 k=len(inner); verts=[(p.x,p.y,h) for h in [z,z-depth] for loop in [inner,outer] for p in loop]
 faces=[]
 for i in range(k):
  j=(i+1)%k
  faces += [(i,j,k+j,k+i),(2*k+i,3*k+i,3*k+j,2*k+j),(i,2*k+i,2*k+j,j),(k+i,k+j,3*k+j,3*k+i)]
 return mesh(name,verts,faces,mat,parent)

def stroke(name,a,b,w,mat,parent):
 a,b=Vector(a),Vector(b); d=(b-a).normalized(); side=Vector((-d.y,d.x,0))*w/2
 return mesh(name,[a+side,a-side,b-side,b+side],[(0,1,2,3)],mat,parent)

def label(name,text,p,mat,parent,size=.007):
 name=name.replace('-','N'); cu=bpy.data.curves.new(name,'FONT'); cu.body=text;cu.size=size;cu.align_x='LEFT';cu.align_y='CENTER';cu.resolution_u=2
 o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o)
 bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False)
 for pt in o.data.vertices:pt.co=v(pt.co)
 o.parent=parent;o.matrix_local=pose(p);o.data.materials.append(mat);return o

def main():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for m in list(bpy.data.materials):bpy.data.materials.remove(m)
 scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
 alloy=material('Retainer_pale_metal',(.43,.45,.43)); alloy['roughness']=.48
 seal=material('Black_velvet_periphery',(.018,.020,.019))
 glass=material('Optical_glass_approximate',(.55,.62,.60));glass.diffuse_color[3]=.045;glass['roughness']=.12
 mark=material('Etched_warm_pale_approximation',(.72,.65,.43));mark['roughness']=.8
 screws=material('Fastener_heads',(.30,.31,.30))
 bus=material('Defog_busbar_silver',(.58,.59,.56))
 root=node('WindowsLPD');datums=node('Datums',parent=root)
 contract=json.loads((OUT/'interface-v1.json').read_text()); manifest={'schema':'lmkit.windows-lpd.manifest.v1','contract':'interface-v1.json','units':'meters','root':'/WindowsLPD','pane_transforms':{},'marking_owner':'WindowsLPD exclusively; disable procedural LM grids when imported','placeholder_bounds':{},'eye_positions':contract['eyes'],'qualification':'approximate visual hardware; not surveyed optics','artwork_layout':'photo-inspired physical layout, not angular-calibrated; do not use for numeric targeting','optical_baseline':'evidence/BASELINE-LMLandingPointDesignator.swift'}
 for side,eye in contract['eyes'].items():node(side+'_Eye',eye,parent=datums)
 for side in ['CDR','LMP']:
  row=contract['forward'][side+'_Window_Inner'];origin=Vector(row['position']);n=Vector(row['normal']).normalized();right=Vector(row['right']).normalized();up=n.cross(right).normalized();basis=Matrix((right,up,n)).transposed();eye=Vector(contract['eyes'][side]);corners=[Vector(p) for p in row['corners']]
  # CDR local right follows upper edge; LMP mirrored local basis remains proper rotation.
  poly=[basis.transposed()@(p-origin) for p in corners]
  module=node(side+'_FlightWindow',parent=root); hardware=node(side+'_Hardware',origin,basis,module)
  inner=rounded(offset(poly,-.003));outer=rounded(offset(poly,.032))
  ring(side+'_StructuralFrame',inner,outer,.007,.045,alloy,hardware)
  ring(side+'_BlackEdge',rounded(offset(poly,-.003)),rounded(offset(poly,.006)),.009,.003,seal,hardware)
  ring(side+'_InnerRetainer',rounded(offset(poly,.006)),rounded(offset(poly,.029)),.014,.007,alloy,hardware)
  ring(side+'_OuterRetainer',rounded(offset(poly,.002)),rounded(offset(poly,.030)),-.023,.012,alloy,hardware)
  # Independent screws, no inferred mechanical or electrical bindings.
  for edge in range(3):
   a,b=offset(poly,.018)[edge],offset(poly,.018)[(edge+1)%3]
   for j in range(1,6):
    q=a.lerp(b,j/6); q.z=.016
    pts=[(q.x+.003*math.cos(t*math.tau/12),q.y+.003*math.sin(t*math.tau/12),q.z) for t in range(12)]
    prism(side+'_Screw_%d_%d'%(edge,j),pts,(0,0,1),.002,screws,hardware)
    stroke(side+'_Slot_%d_%d'%(edge,j),q+Vector((-.002,0,.0002)),q+Vector((.002,0,.0002)),.0007,seal,hardware)
  for layer,sep in [('Inner',0),('Outer',contract['pane_separation_m'])]:
   o=origin-n*sep; pane=node(side+'_Window_'+layer,o,basis,module)
   scale=(o-eye).dot(n)/(origin-eye).dot(n)
   projected=[basis.transposed()@(eye+(p-eye)*scale-o) for p in corners]
   boundary=rounded(projected)
   prism(side+'_Glazing_'+layer,boundary,(0,0,1),.003,glass,pane)
   manifest['pane_transforms'][side+'_Window_'+layer]={'position':list(o),'right':list(right),'up':list(up),'normal':list(n),'thickness_m':.003,'glass_path':'/WindowsLPD/'+side+'_FlightWindow/'+side+'_Window_'+layer+'/'+side+'_Glazing_'+layer}
   if layer=='Inner':
    # Silver conductive edge buses indicated by TN D7439; termination locations approximate.
    for edge in [1,2]:
     a,b=projected[edge],projected[(edge+1)%3];a=a.lerp(b,.10);b=b.lerp(a,.10)
     a.z=b.z=-.0031;stroke(side+'_DefogBus_'+str(edge),a,b,.002,bus,pane)
   if side!='CDR':continue
   marks=node('LPD_'+layer,parent=pane)
   def point(elev,az=0):
    # Visual trace from photo, intentionally separate from old angular calibration.
    # Project outer artwork from inner eye rays to keep paired layers aligned.
    top=poly[0].lerp(poly[1],.58); bottom=poly[2]
    t=(elev+7)/75; q=top.lerp(bottom,t)
    q.x += az*(.0075 if elev<25 else .0040)
    world=origin+basis@q
    world=eye+(world-eye)*scale
    local=basis.transposed()@(world-o);local.z=.00012;return local
   def line(name,a,b,w=.00065):stroke(layer+'_'+name,a,b,w,mark,marks)
   # Three points ensure vertical spine follows plane (straight in this projective construction).
   line('Spine',point(-5),point(61))
   for e in range(0,61,2):
    half=1.2 if e%10==0 else .7
    line('Elevation_%02d'%e,point(e,-half),point(e,half))
    if e%10==0:label(layer+'_Label_%02d'%e,str(e),point(e,1.8),mark,marks)
   for e in [0,50]:
    line('Crossbar_%d'%e,point(e,-10),point(e,10))
    for a in [-10,-5,5,10]:
     line('CrossTick_%d_%d'%(e,a),point(e-.65,a),point(e+.65,a))
     label(layer+'_CrossLabel_%d_%d'%(e,a),str(abs(a)),point(e-1.6,a),mark,marks,.006)
 # Docking module: curved structural pane, protective outer pane and independent rim.
 d=contract['docking'];o=Vector(d['center']);right=Vector(d['right']);up=Vector(d['up']);n=Vector(d['normal_toward_cabin']);basis=Matrix((right,up,n)).transposed()
 dock=node('DockingWindow',o,basis,root);w,h=d['viewing_size_m'];poly=[Vector((-w/2,-h/2,0)),Vector((w/2,-h/2,0)),Vector((w/2,h/2,0)),Vector((-w/2,h/2,0))]
 ring('Docking_Retainer',rounded(poly,.009),rounded(offset(poly,.025),.009),.006,.024,alloy,dock)
 ring('Docking_BlackEdge',rounded(poly,.009),rounded(offset(poly,.006),.009),.007,.003,seal,dock)
 for layer,z in [('Inner',0),('Outer',-.020)]:
  pn=node('Docking_Window_'+layer,parent=dock)
  verts=[];faces=[]
  for j in range(2):
   for i in range(17):
    x=-w/2+w*i/16;sag=d['inner_curvature_radius_m']-math.sqrt(d['inner_curvature_radius_m']**2-x*x)
    verts.append((x,(-h/2 if j==0 else h/2),z+sag))
  for i in range(16):faces.append((i,i+1,18+i,17+i))
  mesh('Docking_Glazing_'+layer,verts,faces,glass,pn)
 node('Docking_Optics_Uncalibrated',parent=dock)
 bpy.context.view_layer.update()
 for obj in [root]+list(root.children_recursive):
  if obj.type=='MESH':
   coords=[C.inverted().to_3x3()@(obj.matrix_world@p.co) for p in obj.data.vertices]
   manifest['placeholder_bounds'][obj.name]={'min':[min(p[i] for p in coords) for i in range(3)],'max':[max(p[i] for p in coords) for i in range(3)]}
 (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'WindowsLPD.blend'))
 export(root)
 print('WINDOWS_EXPORT_COMPLETE',len(list(root.children_recursive)))
if __name__=='__main__':main()
