"""Y-up meter authoring and native USD export; adapted from BreakerBanks at70c0914."""
import bpy,json,math
from pathlib import Path
from mathutils import Matrix,Vector,Quaternion
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf,Gf
D=Path(__file__).resolve().parent
C=D.parent
M={}
def material(name,color,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.72;M[name]=m;return m
def node(name,parent=None,position=(0,0,0),q=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;o.location=position
 if q:o.rotation_mode='QUATERNION';o.rotation_quaternion=Quaternion((q[3],*q[:3]))
 return o
def box(name,parent,lo,hi,mat):
 bpy.ops.mesh.primitive_cube_add();o=bpy.context.object;o.name=name;o.dimensions=Vector(hi)-Vector(lo);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.parent=parent;o.location=(Vector(hi)+Vector(lo))/2;o.data.materials.append(M[mat]);mod=o.modifiers.new('SmallEdgeBreak','BEVEL');mod.width=min(.00065,min(o.dimensions)*.1);mod.segments=1;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name);return o
def panelpose(p):
 return Matrix.Translation(Vector(p['translation_m']))@Quaternion((p['quaternion_xyzw'][3],*p['quaternion_xyzw'][:3])).to_matrix().to_4x4()
def usdpose(p,cache=None):
 u=(cache or UsdGeom.XformCache()).GetLocalToWorldTransform(p);return Matrix([[u[j][i] for j in range(4)] for i in range(4)])
def pose_dict(m):
 p,q,s=m.decompose();return {'position_m':list(p),'rotation_quaternion_xyzw':[q.x,q.y,q.z,q.w],'scale':list(s)}
def export(root):
 stage=Usd.Stage.CreateNew(str(D/'LowerConsole.usda'));UsdGeom.SetStageUpAxis(stage,'Y');UsdGeom.SetStageMetersPerUnit(stage,1)
 for n,m in M.items():
  u=UsdShade.Material.Define(stage,'/Materials/'+n);s=UsdShade.Shader.Define(stage,'/Materials/'+n+'/Surface');s.CreateIdAttr('UsdPreviewSurface');s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3]));s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.72);u.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface')
 def emit(o,parent):
  path=parent+'/'+o.name.replace('.','_');u=UsdGeom.Mesh.Define(stage,path) if o.type=='MESH' else UsdGeom.Xform.Define(stage,path);m=o.matrix_local;u.AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
  if o.type=='MESH':
   o.data.calc_loop_triangles();pts=[Gf.Vec3f(*v.co) for v in o.data.vertices];u.CreatePointsAttr(pts);u.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles));u.CreateFaceVertexIndicesAttr([i for t in o.data.loop_triangles for i in t.vertices]);u.CreateNormalsAttr([Gf.Vec3f(*t.normal) for t in o.data.loop_triangles]);u.SetNormalsInterpolation('uniform');u.CreateSubdivisionSchemeAttr('none');u.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(pts));UsdShade.MaterialBindingAPI.Apply(u.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath('/Materials/'+o.data.materials[0].name)))
  for c in o.children:emit(c,path)
  return u
 u=emit(root,'');stage.SetDefaultPrim(u.GetPrim());stage.GetRootLayer().Save();stage.GetRootLayer().Export(str(D/'LowerConsole.usdc'));target=D/'LowerConsole.usdz'
 if target.exists():target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(D/'LowerConsole.usdc')),str(target))
def import_meshes(path,transform=None,omit=()):
 stage=Usd.Stage.Open(str(path));cache=UsdGeom.XformCache();objects=[];transform=transform or Matrix.Identity(4)
 for p in stage.Traverse():
  name=str(p.GetPath())
  if not p.IsA(UsdGeom.Mesh) or any(name==s or name.startswith(s+'/') for s in omit):continue
  mesh=UsdGeom.Mesh(p);counts=mesh.GetFaceVertexCountsAttr().Get();idx=mesh.GetFaceVertexIndicesAttr().Get();faces=[];at=0
  for n in counts:faces.append(tuple(idx[at:at+n]));at+=n
  data=bpy.data.meshes.new(name);data.from_pydata([tuple(v) for v in mesh.GetPointsAttr().Get()],[],faces);data.update();o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.matrix_world=transform@usdpose(p,cache);objects.append(o)
  bound=UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0];color=(.4,.4,.4)
  if bound:
   for child in bound.GetPrim().GetChildren():
    if child.IsA(UsdShade.Shader):
     col=UsdShade.Shader(child).GetInput('diffuseColor').Get()
     if col is not None:color=tuple(col)
  key='Review_'+str(tuple(round(c,3) for c in color)).replace('.','_');mat=M.get(key) or material(key,color);o.data.materials.append(mat)
 return objects
