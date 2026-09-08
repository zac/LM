"""Bake Blender's orientation wrapper into geometry and EVERY local transform.
Keep DSKY_Mount identity so integration may place it in the cabin directly.
"""
from pxr import Usd, UsdGeom, UsdUtils, Gf, Sdf, Vt

def normalize_and_package(path):
 stage=Usd.Stage.Open(str(path)); root=stage.GetPrimAtPath('/DSKY_Mount')
 basis=UsdGeom.Xformable(root).GetLocalTransformation(); inv=basis.GetInverse()
 for prim in stage.Traverse():
  if prim.IsA(UsdGeom.Xformable):
   xf=UsdGeom.Xformable(prim); local=xf.GetLocalTransformation()
   xf.ClearXformOpOrder(); xf.AddTransformOp().Set(Gf.Matrix4d(1) if prim==root else inv*local*basis)
  if prim.IsA(UsdGeom.Mesh):
   mesh=UsdGeom.Mesh(prim)
   pts=[Gf.Vec3f(basis.TransformDir(Gf.Vec3d(*v))) for v in mesh.GetPointsAttr().Get()]
   mesh.GetPointsAttr().Set(Vt.Vec3fArray(pts)); mesh.GetExtentAttr().Set(UsdGeom.PointBased.ComputeExtent(pts))
   ns=mesh.GetNormalsAttr().Get()
   if ns: mesh.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(basis.TransformDir(Gf.Vec3d(*v))) for v in ns]))
 UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1)
 stage.GetRootLayer().Save()
 binary=path.with_suffix('.usdc')
 stage.GetRootLayer().Export(str(binary))
 target=path.with_suffix('.usdz')
 if target.exists(): target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(binary)),str(target))
