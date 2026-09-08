"""USD geometry helpers adapted from Cabin/build.py at 3ad1a999; physical axis conversion preserved."""
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
 o.matrix_local=pose(p,r); o['qualification']='proposed blockout; see DATUM.md'; return o
def mesh(name,verts,faces,mat,parent,p=(0,0,0),r=None):
 data=bpy.data.meshes.new(name); data.from_pydata([v(x) for x in verts],[],faces); data.update()
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
 stage=Usd.Stage.CreateNew(str(OUT/'CommanderPanels.usda')); UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1)
 mats={}
 for m in bpy.data.materials:
  path='/Materials/'+m.name; u=UsdShade.Material.Define(stage,path); s=UsdShade.Shader.Define(stage,path+'/Surface'); s.CreateIdAttr('UsdPreviewSurface')
  s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3])); s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.7)
  if m.name=='Pane': s.CreateInput('opacity',Sdf.ValueTypeNames.Float).Set(.08)
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
 emit(root,''); stage.SetDefaultPrim(stage.GetPrimAtPath('/CommanderPanels')); stage.GetRootLayer().Save(); stage.GetRootLayer().Export(str(OUT/'CommanderPanels.usdc'))
 target=OUT/'CommanderPanels.usdz'
 if target.exists(): target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'CommanderPanels.usdc')),str(target))
