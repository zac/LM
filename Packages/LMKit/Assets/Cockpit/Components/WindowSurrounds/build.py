"""Solid window-surround overlay. Helpers preserved from Timers at ae5fbf9,
through AltitudeRate to WindowsLPD/Cabin coordinate/export provenance.
Optical apertures and all live hardware remain owned by their components.
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
   if o.get('continuous_sheet',False):
    prim.CreateNormalsAttr([Gf.Vec3f(*(C.inverted().to_3x3()@o.data.corner_normals[i].vector)) for t in o.data.loop_triangles for i in t.loops]);prim.SetNormalsInterpolation('faceVarying')
   else:
    prim.CreateNormalsAttr([Gf.Vec3f(*(C.inverted().to_3x3()@t.normal)) for t in o.data.loop_triangles]);prim.SetNormalsInterpolation('uniform')
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


def offset_edges(poly,widths):
 center=sum(poly,Vector())/len(poly);lines=[]
 for i,a in enumerate(poly):
  e=(poly[(i+1)%3]-a).normalized();normal=Vector((-e.y,e.x,0))
  if normal.dot(center-a)>0:normal=-normal
  lines.append((normal,normal.dot(a)+widths[i]))
 out=[]
 for i in range(3):
  a,da=lines[i-1];b,db=lines[i];det=a.x*b.y-a.y*b.x
  out.append(Vector(((da*b.y-a.y*db)/det,(a.x*db-da*b.x)/det,0)))
 return out

def band(name,inner,outer,inner_z,outer_z,depth,mat,parent):
 vertices=[(p.x,p.y,z) for loop,z in [(inner,inner_z),(outer,outer_z),(inner,inner_z-depth),(outer,outer_z-depth)] for p in loop];faces=[]
 for i in range(3):
  j=(i+1)%3;faces.extend([(i,j,3+j,3+i),(6+i,9+i,9+j,6+j),(i,6+i,6+j,j),(3+i,3+j,9+j,9+i)])
 return mesh(name,vertices,faces,mat,parent)

def sheet(name,points,mat,parent):
 # Warped sheet fields are joined visually with shared front normals. Each
 # constituent closed prism is convex, avoiding ambiguous self-overlapping lofts.
 from mathutils.geometry import tessellate_polygon
 pts=[Vector(p) for p in points];tris=[];normals=[Vector() for p in pts]
 for tri in tessellate_polygon([pts]):
  ids=list(tri) if isinstance(tri[0],int) else [next(i for i,p in enumerate(pts) if (p-q).length<1e-7) for q in tri]
  aa,bb,cc=[pts[i] for i in ids];n=(bb-aa).cross(cc-aa);center=(aa+bb+cc)/3
  if n.dot(Vector((0,1.1,0))-center)<0:ids.reverse();n=-n
  tris.append(ids)
  for i in ids:normals[i]+=n
 normals=[n.normalized() for n in normals];group=node(name,parent=parent)
 for index,ids in enumerate(tris):
  triangle=[pts[i] for i in ids];n=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized();ob=prism(name+'_%02d'%index,triangle,n,.012,mat,group);ob['continuous_sheet']=True;ob['front_face_count']=1;ob['front_vertex_normals']=[float(x) for i in ids for x in v(normals[i])]
  ob.data.polygons[0].use_smooth=True
 return group

def cut_owned(cutter,targets):
 import bmesh
 bm=bmesh.new();bm.from_mesh(cutter.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 if bm.calc_volume(signed=True)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
 bm.to_mesh(cutter.data);bm.free()
 bpy.context.view_layer.update()
 for ob in list(targets):
  if ob.type!='MESH':continue
  mod=ob.modifiers.new('EquipmentClearance','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
  bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=mod.name)
 bpy.data.objects.remove(cutter,do_unlink=True)

def clear_equipment(root,mat,win):
 owned=list(root.children_recursive)
 # Final central console front footprint plus restrained3mm seam allowance.
 # Solid keep-out volumes remove wall intrusions from both front skins and cases.
 for name,size,center,rotation,localz in [('UpperConsoleClearance',(.808,.506,.34),(0,1.604410648,-.884985924),-10,-.13),('Panel3Clearance',(.976,.194,.30),(0,1.278142214,-.805857837),-45,-.12)]:
  transform=pose(center,rx(rotation))@pose((0,0,localz));cutter=box(name,size,(0,0,0),mat,None);cutter.matrix_world=transform;cut_owned(cutter,owned)
 # Preserve existing frame material volume where curved shell approaches upper edges.
 for side in ['CDR','LMP']:
  r=win['forward'][side+'_Window_Inner'];o=Vector(r['position']);n=Vector(r['normal']).normalized();right=Vector(r['right']).normalized();up=n.cross(right).normalized();basis=Matrix((right,up,n)).transposed();poly=[basis.transposed()@(Vector(p)-o) for p in r['corners']]
  framepoly=offset_edges(poly,[.034]*3);cutter=prism(side+'FrameClearance',[o+basis@Vector((p.x,p.y,.020)) for p in framepoly],n,.080,mat,None);cut_owned(cutter,list(bpy.data.objects[side+'_UpperCheek'].children_recursive))
 # Pilot contact lamp sight well: retain its current small face and fixed mount.
 # The 46mm target square gives the existing30mm housing a restrained border.
 m=json.loads((OUT.parent/'EngineControls/mounting-matrices.json').read_text());lamp=next(l for l in m['LunarContact'] if l['id']=='PilotLunarContact');mount=Matrix(lamp['Cabin_matrix_rows']);eye=Vector(win['eyes']['LMP']);target=[(mount@Vector((x,y,.005,1))).to_3d() for x,y in [(-.023,-.023),(.023,-.023),(.023,.023),(-.023,.023)]];pts=[eye+(p-eye)*t for t in [.20,1.10] for p in target]
 cutter=mesh('PilotContactSightWell',pts,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,None)
 import bmesh
 bm=bmesh.new();bm.from_mesh(cutter.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(cutter.data);bm.free();cut_owned(cutter,[o for o in owned if o.name.startswith('LMP_')])

 # Stepped breaker mounting reliefs are shallow backed pockets, not open holes.
 bstage=Usd.Stage.Open(str(OUT.parent/'BreakerBanks/BreakerBanks.usdz'));bcache=UsdGeom.BBoxCache(Usd.TimeCode.Default(),[UsdGeom.Tokens.default_]);bi=json.loads((OUT.parent/'BreakerBanks/interface.json').read_text())
 for row in bi['slots']:
  bound=bcache.ComputeWorldBound(bstage.GetPrimAtPath(row['overlay_path'])).ComputeAlignedRange();lo=Vector(bound.GetMin());hi=Vector(bound.GetMax());cutter=box('BreakerRowClearance',hi-lo+Vector((.006,.006,.006)),(lo+hi)/2,mat,None);side='CDR' if row['id'].startswith('Panel11') else 'LMP';cut_owned(cutter,[o for o in owned if o.name.startswith(side+'_LowerCheek')])
 for side,panel,sign in [('CDR','Panel11',-1),('LMP','Panel16',1)]:
  bound=bcache.ComputeWorldBound(bstage.GetPrimAtPath('/BreakerBanks/'+panel)).ComputeAlignedRange();lo=Vector(bound.GetMin());hi=Vector(bound.GetMax());center=(lo+hi)/2;center.x=sign*(max(abs(lo.x),abs(hi.x))+.014);box(side+'_BreakerReliefBacking',(.012,hi.y-lo.y+.040,hi.z-lo.z+.040),center,mat,bpy.data.objects[side])

def usd_pose(prim):
 m=UsdGeom.XformCache().GetLocalToWorldTransform(prim);t=m.ExtractTranslation();q=m.ExtractRotationQuat();return {'position_m':list(t),'rotation_quaternion_xyzw':list(q.GetImaginary())+[q.GetReal()],'scale':[1,1,1]}

def main():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for m in list(bpy.data.materials):bpy.data.materials.remove(m)
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
 paint=material('SurroundPaint_Provisional',(.49,.51,.48));paint['roughness']=.78
 edge=material('GasketCharcoal_Provisional',(.050,.056,.052));edge['roughness']=.85
 trim=material('FoldedMetalEdge_Provisional',(.36,.38,.36));trim['roughness']=.75
 root=node('WindowSurrounds');win=json.loads((OUT.parent/'WindowsLPD/interface-v1.json').read_text());groups=[];construction={}
 R=1.1684;floor=.1225;fore=-.48;aft=1.15;central=.43;roof=1.1+math.sqrt(R*R-central*central);angle=math.asin(central/R);arc=[(R*math.sin(angle+(math.pi/2-angle)*i/12),1.1+R*math.cos(angle+(math.pi/2-angle)*i/12)) for i in range(13)]
 for side,sign in [('CDR',-1),('LMP',1)]:
  group=node(side,parent=root);groups.append({'path':'/WindowSurrounds/'+side,'casts_shadows':True});r=win['forward'][side+'_Window_Inner'];o=Vector(r['position']);normal=Vector(r['normal']).normalized();right=Vector(r['right']).normalized();up=normal.cross(right).normalized();basis=Matrix((right,up,normal)).transposed();poly=[basis.transposed()@(Vector(p)-o) for p in r['corners']];local=node(side+'_RevealDatum',o,basis,group)
  inner=offset_edges(poly,[.034]*3);outer=offset_edges(poly,[.080,.045,.110]);band(side+'_SlopingReveal',inner,outer,.017,.052,.014,paint,local)
  # A restrained3mm gasket outside existing retainer; no duplicate glazing or LPD.
  band(side+'_GasketEdge',offset_edges(poly,[.0325]*3),inner,.0155,.017,.003,edge,local)
  out=[o+basis@Vector((p.x,p.y,.052)) for p in outer];A,B,D=out;low=(sign*central,floor,-1.02);high=(sign*central,roof,-1.02);arcedge=[(sign*x,y,fore) for x,y in reversed(arc)]
  sheet(side+'_LowerCheek',[low,(sign*R,floor,fore),(sign*R,1.1,fore),A,D],paint,group)
  sheet(side+'_InboardCheek',[low,D,B,high],paint,group)
  sheet(side+'_UpperCheek',[B,A,(sign*R,1.1,fore)]+arcedge[1:]+[high],paint,group)
  construction[side]={'inner_triangle_cabin_m':r['corners'],'basis_columns_cabin':[list(right),list(up),list(normal)],'reveal_start_band_m':.034,'outer_edge_widths_m':[.080,.045,.110],'inner_plane_toward_crew_m':.017,'outer_plane_toward_crew_m':.052,'metal_thickness_m':.014,'cheek_thickness_m':.012,'outer_corners_cabin_m':[list(p) for p in out],'original_shell_boundary_preserved':True}
 import bmesh
 for ob in bpy.data.objects:
  if ob.type=='MESH':
   bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
   if bm.calc_volume(signed=True)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
   bm.to_mesh(ob.data);bm.free()
  if ob.type=='MESH' and ob.get('continuous_sheet',False):
   # Explicit front-only normals: side/rear faces do not soften actual metal folds.
   front_count=ob['front_face_count'];values=ob['front_vertex_normals'];custom=[]
   for face in ob.data.polygons:
    custom.extend(Vector(values[ob.data.loops[j].vertex_index*3:ob.data.loops[j].vertex_index*3+3]) if face.index<front_count else face.normal for j in face.loop_indices)
   ob.data.normals_split_custom_set(custom)
 clear_equipment(root,paint,win)
 for ob in list(root.children_recursive):
  if ob.type=='MESH' and not len(ob.data.polygons):bpy.data.objects.remove(ob,do_unlink=True)
 bpy.context.view_layer.update()
 cabin=Usd.Stage.Open(str(OUT.parent/'Cabin/Cabin.usdz'));suppressions=[]
 for p in cabin.Traverse():
  if p.IsA(UsdGeom.Mesh) and any(p.GetName().startswith(side+'_Front_'+family+'_') for side in ['CDR','LMP'] for family in ['Lower','Inboard','Upper']):suppressions.append({'component':'Cabin','path':str(p.GetPath()),'pose':usd_pose(p)})
 windows=Usd.Stage.Open(str(OUT.parent/'WindowsLPD/WindowsLPD.usdz'));protected=[]
 for p in windows.Traverse():
  if p.GetName() in ['CDR_Window_Inner','CDR_Window_Outer','LMP_Window_Inner','LMP_Window_Outer','CDR_Eye','LMP_Eye']:protected.append({'component':'WindowsLPD','path':str(p.GetPath()),'pose':usd_pose(p)})
 c={'schema':'lmkit.console-enclosure.v1','component_id':'WindowSurrounds','root':'/WindowSurrounds','units':'meters','parent_space':'Cabin','root_pose':{'position_m':[0,0,0],'rotation_quaternion_xyzw':[0,0,0,1],'scale':[1,1,1]},'groups':groups,'suppressions':suppressions,'protected_mounts':protected,'qualification':'Source-guided approximate sheet-metal interior; no surveyed dimensions; preserve all windows and control mounts','construction':construction,'clearances':{'console_reference':'InstrumentConsole b6d2712; upperX±.404 and Panel3X±.488 keep-out with small edge allowance','pilot_contact':'46mm target-square sight well; current lamp and eye unchanged; provisional hardware relief','ACA':'Unchanged; raw USD reviewer found no original intersection; no controller clearance cut authored','existing_windows':'Retainer volume cleared only from overlapping upper cheek','breaker_banks':'Nine raw row bounds plus3mm relief; two opaque backing sheets8mm outboard of bank extremity with20mm edge overlap keep mounting seams closed'},'ownership':'Only replaces named Cabin forward cheek meshes. No WindowsLPD, handrail, instrument, or planning-blank suppression.'}
 (OUT/'interface.json').write_text(json.dumps(c,indent=2)+'\n');bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'WindowSurrounds.blend'));export(root);print('WINDOW_SURROUNDS_EXPORTED',len(suppressions),'suppressed meshes')
if __name__=='__main__':main()
