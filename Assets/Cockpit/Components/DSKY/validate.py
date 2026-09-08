"""Run in a separate Blender process after build.py; fails loudly on contract drift."""
import bpy, json, math, hashlib, sys
from pathlib import Path
from mathutils import Vector
from pxr import Usd, UsdGeom, UsdShade, UsdUtils, Gf
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT))
from build import KEYS, I, W, H
manifest=json.loads((OUT/'bindings.json').read_text())
report={'checks':[], 'limitations':['Reality Composer Pro GUI not tested','RealityKit input and Vision Pro not tested']}
def check(condition,label):
 if not condition: raise AssertionError(label)
 report['checks'].append(label)
def bounds_blender():
 vs=[o.matrix_world@Vector(v) for o in bpy.data.objects if o.type=='MESH' for v in o.bound_box]
 return [[min(v[i] for v in vs) for i in range(3)],[max(v[i] for v in vs) for i in range(3)]]
bpy.ops.wm.open_mainfile(filepath=str(OUT/'DSKY.blend'))
root=bpy.data.objects['DSKY_Mount']
check(tuple(root.scale)==(1,1,1),'Blender identity root scale')
check(len([o for o in root.children if o.name.startswith('DSKY_Key_')])==19,'19 direct key transforms')
for suffix,x,y in KEYS:
 o=bpy.data.objects['DSKY_Key_'+suffix]
 check((o.location-Vector((x*I-W/2,-.011,y*I-H/2))).length<1e-7,'Blender neutral '+suffix)
 check(o.type=='EMPTY' and any(c.type=='MESH' for c in o.children),'Independent pivot and mesh '+suffix)
check(bpy.data.objects['DSKY_Face'].parent==root and bpy.data.objects['DSKY_Display_Mount'].parent==root,'Required fixed/display direct parents')
display=bpy.data.objects['DSKY_Display_Mount']
check(all(bpy.data.objects['DSKY_Readout_'+name].parent==display and bpy.data.objects['DSKY_Readout_'+name].type=='EMPTY' for name in manifest['fields']),'Six independent readout regions')
check(all(bpy.data.objects[item['name']].parent==display for item in manifest['lamps']),'Twelve independent status/caution lamp regions')
check(bpy.data.objects['DSKY_Lamp_COMP_ACTY'].parent==display,'Separate computer activity lamp')
check(all(bpy.data.objects['DSKY_Lamp_Blank_'+str(n)].parent==display for n in [5,6]),'Two separate blank spare cells')
fixed=bpy.data.objects['DSKY_Face']; fixed_pose=fixed.matrix_world.copy()
key=bpy.data.objects['DSKY_Key_PRO']; cap=bpy.data.objects['DSKY_Cap_PRO']; rest=key.location.copy()
bpy.context.view_layer.update(); cap_rest=cap.matrix_world.translation.copy()
key.location.y+=.003; bpy.context.view_layer.update()
check((cap.matrix_world.translation-cap_rest-Vector((0,.003,0))).length<1e-7 and fixed.matrix_world==fixed_pose,'PRO cap press follows pivot while fixed face stays still')
key.location=rest; bpy.context.view_layer.update()
check(not bpy.data.libraries,'No linked Blender libraries')
check(bpy.context.scene.render.filepath.startswith('//'),'Portable relative review output path')
check(not [im for im in bpy.data.images if im.source=='FILE' and not im.packed_file],'No missing external textures')
check(not [o for o in bpy.data.objects if '.00' in o.name],'Unique stable object names')
check(all(abs(o.scale.x-1)<1e-6 and abs(o.scale.y-1)<1e-6 and abs(o.scale.z-1)<1e-6 for o in bpy.data.objects if o.type=='MESH'),'All mesh scales applied')
meshes=[o for o in bpy.data.objects if o.type=='MESH']
for o in meshes: o.data.calc_loop_triangles()
report['source']={'meshes':len(meshes),'triangles':sum(len(o.data.loop_triangles) for o in meshes),
 'materials_used':len({m.name for o in meshes for m in o.data.materials}),'textures':0,'bounds_blender':bounds_blender()}
# Flat text is intentionally open geometry; every solid must have nonzero polygon normals.
check(all(p.area>1e-14 and p.normal.length>.9 for o in meshes for p in o.data.polygons),'No zero-area faces or invalid normals')
report['exports']={}
for filename in ['DSKY.usdz','DSKY-LightingPreview.usdz']:
 stage=Usd.Stage.Open(str(OUT/filename)); rootprim=stage.GetPrimAtPath('/DSKY_Mount')
 check(bool(rootprim) and stage.GetDefaultPrim()==rootprim,filename+' default root')
 check(UsdGeom.GetStageUpAxis(stage)=='Y' and UsdGeom.GetStageMetersPerUnit(stage)==1,filename+' Y up and meters')
 xf=UsdGeom.XformCache(); m=xf.GetLocalToWorldTransform(rootprim)
 check(Gf.IsClose(m,Gf.Matrix4d(1),1e-6),filename+' identity root transform')
 for key in manifest['keys']:
  p=stage.GetPrimAtPath(key['path']); check(bool(p),filename+' path '+key['name'])
  pos=xf.GetLocalToWorldTransform(p).ExtractTranslation()
  check(Gf.IsClose(pos,Gf.Vec3d(*key['neutral_usd_m']),1e-7),filename+' local axes '+key['name'])
 check(UsdGeom.Xformable(stage.GetPrimAtPath('/DSKY_Mount/DSKY_Display_Mount')).GetLocalTransformation().ExtractTranslation()[1]>0,filename+' display above origin')
 # Asymmetric markers: VERB is left upper keyboard, ENTR right, 0 lower. No extra geometry needed.
 bbox=UsdGeom.BBoxCache(Usd.TimeCode.Default(),['default']).ComputeWorldBound(rootprim).ComputeAlignedRange()
 dims=bbox.GetSize()
 check(abs(dims[0]-W)<1e-6 and abs(dims[1]-H)<1e-6,filename+' face envelope')
 check(dims[2]<=manifest['depth_budget_m']+1e-6,filename+' depth within budget')
 usdmeshes=[p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
 check(all(UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0] for p in usdmeshes),filename+' all meshes material bound')
 check(all(all(n==3 for n in UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get()) for p in usdmeshes),filename+' triangulated')
 emissive=[p for p in stage.Traverse() if p.IsA(UsdShade.Shader) and p.GetAttribute('inputs:emissiveColor').Get() and sum(p.GetAttribute('inputs:emissiveColor').Get())>0]
 check(len(emissive)>=(3 if 'Preview' in filename else 1),filename+' emissive Preview Surface shaders')
 checker=UsdUtils.ComplianceChecker(arkit=False,skipARKitRootLayerCheck=True)
 checker.CheckCompliance(str(OUT/filename))
 errors=checker.GetErrors(); failed=checker.GetFailedChecks()
 check(not errors and not failed,filename+' OpenUSD compliance')
 report['exports'][filename]={'sha256':hashlib.sha256((OUT/filename).read_bytes()).hexdigest(),
 'bounds_usd_m':[list(bbox.GetMin()),list(bbox.GetMax())],'mesh_count':len(usdmeshes),
 'compliance_errors':errors,'compliance_failed':failed,'compliance_warnings':checker.GetWarnings()}
# Reimport in clean scene, then compare actual world positions and dimensions.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=str(OUT/'DSKY.usdz'),import_materials=True)
root=bpy.data.objects.get('DSKY_Mount'); check(root is not None,'Clean USDZ reimport')
# Blender converts Y-up back to its Z-up. Test world coordinates, not import-specific wrapper choice.
for key in manifest['keys']:
 o=bpy.data.objects.get(key['name']); p=key['neutral_usd_m']; expected=Vector((p[0],-p[2],p[1]))
 check(o is not None and (o.matrix_world.translation-expected).length<1e-6,'Reimport position '+key['name'])
check(bpy.data.objects['DSKY_Face'].parent==root,'Reimport face parent')
check(all(bpy.data.objects[k['name']].parent==root for k in manifest['keys']),'Reimport key parents')
check(all(o.data.materials for o in bpy.data.objects if o.type=='MESH'),'Reimport materials')
report['reimport_bounds_blender']=bounds_blender()
report['blender_version']=bpy.app.version_string
(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS',len(report['checks']),'checks')
