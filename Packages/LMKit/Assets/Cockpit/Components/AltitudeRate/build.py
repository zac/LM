"""AltitudeRate authoring and neutral USD export.
Mesh/export helpers adapted from WindowsLPD/build.py at LMKit ee3a19f;
that code preserves original Cabin helper provenance (0936446).
All dimensions and tape pitch provisional; see EVIDENCE.md and interface.json.
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
 stage=Usd.Stage.CreateNew(str(OUT/'AltitudeRate.usda')); UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1)
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
 emit(root,''); stage.SetDefaultPrim(stage.GetPrimAtPath('/AltitudeRate')); stage.GetRootLayer().Save(); stage.GetRootLayer().Export(str(OUT/'AltitudeRate.usdc'))
 target=OUT/'AltitudeRate.usdz'
 if target.exists(): target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'AltitudeRate.usdc')),str(target))
def text(name,string,position,size,mat,parent,align='CENTER'):
 cu=bpy.data.curves.new(name,'FONT');cu.body=string;cu.size=size;cu.align_x=align;cu.align_y='CENTER';cu.resolution_u=2
 o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False)
 for pt in o.data.vertices:pt.co=v(pt.co)
 o.parent=parent;o.matrix_local=pose(position);o.data.materials.append(mat);return o

def q(value,row):
 knots=row.get('q_knots',row.get('q_abs_knots'));mag=abs(value) if 'q_abs_knots' in row else value
 for (x0,y0),(x1,y1) in zip(knots,knots[1:]):
  if mag<=x1:return (y0+(mag-x0)/(x1-x0)*(y1-y0))*(-1 if value<0 else 1)
 raise ValueError(value)

def setup():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for m in list(bpy.data.materials):bpy.data.materials.remove(m)
 scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
 black=material('Tape_Black',(.012,.014,.013));black['roughness']=.85
 cream=material('Scale_Ivory',(.82,.81,.73));cream['roughness']=.85
 case=material('Case_Gray',(.24,.25,.235));case['roughness']=.75
 edge=material('Bezel_Dark',(.035,.040,.038));edge['roughness']=.68
 metal=material('Fastener_Metal',(.38,.39,.36));metal['roughness']=.62
 glass=material('Lens_Clear',(.7,.75,.7));glass.diffuse_color[3]=.015;glass['roughness']=.2
 muted=material('Muted_Legend',(.41,.43,.39));muted['roughness']=.9
 root=node('AltitudeRate');fixed=node('Fixed',parent=root)
 box('HousingBack',(.078,.140,.016),(0,0,-.007),black,fixed)
 # Broad mounting flange and separate inset aperture rails. No full plate crosses the tapes.
 for side,x in [('Left',-.0385),('Right',.0385)]:box('Flange_'+side,(.005,.145,.004),(x,0,.002),case,fixed)
 for side,y in [('Top',.0665),('Bottom',-.0665)]:box('Flange_'+side,(.077,.012,.004),(0,y,.002),case,fixed)
 for side,x in [('Left',-.0325),('Middle',-.001),('Right',.0335)]:box('Bezel_'+side,(.005,.121,.008),(x,0,.005),edge,fixed)
 for side,y in [('Top',.054),('Bottom',-.054)]:box('Mask_'+side,(.068,.014,.008),(0,y,.005),edge,fixed)
 for side,x in [('Left',-.0375),('Right',.0375)]:
  for end,y in [('Top',.0675),('Bottom',-.0675)]:
   points=[(x+.0025*math.cos(i*math.tau/12),y+.0025*math.sin(i*math.tau/12),.005) for i in range(12)]
   prism('Fastener_'+side+end,points,(0,0,1),.0015,metal,fixed)
   box('Slot_'+side+end,(.0035,.0005,.0003),(x,y,.0052),black,fixed)
 c=json.loads((OUT/'interface.json').read_text())
 for key in ['altitude','altitude_rate']:
  data=c[key];origin=data['origin_m'];cx=origin[0]
  tape=node(data['group'],origin,parent=root)
  text(data['group']+'_RangeLegend','RANGE' if key=='altitude' else 'RANGE RATE',(cx,.058,.0093),.0031,muted,fixed)
  text(data['group']+'_AltitudeLegend','ALT' if key=='altitude' else 'ALT RATE',(cx,.051,.0093),.0037,cream,fixed)
  text(data['group']+'_Units','FT' if key=='altitude' else 'FT/SEC',(cx,-.054,.0093),.0039,cream,fixed)
  # Source-backed fixed white triangle points LEFT at the moving scale's right edge.
  px=cx+.013
  mesh(data['pointer'],[(px-.004,0,.010),(px+.001,.0025,.010),(px+.001,-.0025,.010)],[(0,2,1)],cream,fixed)
  for row in data['rows']:
   displacement=q(row['value'],data)
   visible=abs(displacement)<=c['motion']['row_center_limit_m']
   n=node(row['name'],(0,displacement,0) if visible else (0,0,-.010),parent=tape)
   n['tape_value']=row['value'];n['runtime_visible_hint']=visible
   # Negative rate uses a light tape with dark marks, following reference tone inversion.
   ink=black if key=='altitude_rate' and row['value']<0 else cream
   if key=='altitude_rate' and row['value']<0:box(row['name']+'_WhiteTape',(.0254,.0041,.00015),(0,0,-.0002),cream,n)
   length=.0045 if row['major'] else .0025
   box(row['name']+'_Tick',(length,.0005,.00015),(.009-length/2,0,.0001),ink,n)
   if row['major']:
    label=str(row['value']) if key=='altitude' else ('+'+str(row['value']) if row['value']>0 else str(row['value']))
    text(row['name']+'_Numeral',label,(.002,0,.0002),.0052,ink,n,align='RIGHT')
  # Park unavailable-data shutters INSIDE the opaque housing at neutral state.
  shutter=node(data['unavailable'],(cx,0,-.005),parent=root)
  box(data['unavailable']+'_Plate',(.0255,.094,.0003),(0,0,0),edge,shutter)
  for j in range(-4,5):
   beam(data['unavailable']+'_Stripe_'+str(j+4),(-.006,j*.01-.002,.00025),(.006,j*.01+.002,.00025),.00065,muted,shutter)
  data['unavailable_active_position_m']=[cx,0,.007]
  data['unavailable_parked_position_m']=[cx,0,-.005]
  data['neutral_rows']={row['name']: {'position_m':[0,q(row['value'],data),0] if abs(q(row['value'],data))<=.043 else [0,0,-.010],'visible':abs(q(row['value'],data))<=.043} for row in data['rows']}
 # Transparent protective pane kept independently removable; never carries text.
 lens=node('ProtectiveLens',parent=root)
 box('Lens_Glass',(.064,.098,.0008),(0,0,.011),glass,lens)
 c['motion']['usd_visibility_policy']='All prim visibility inherited. Neutral unused rows parked inside opaque housing at localz=-.010; adapter positions valid rows with localz0 and disables out-of-window rows. Shutters parked inside housing; set active position on invalid.'
 c['motion']['row_authored_translation_m']='See each channel neutral_rows: valid zero neighborhood at computed Y; others [0,0,-.010]'
 (OUT/'interface.json').write_text(json.dumps(c,indent=2)+'\n')
 bpy.context.view_layer.update()
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'AltitudeRate.blend'));export(root)
 print('ALTITUDE_RATE_EXPORTED',len(list(root.children_recursive)))
if __name__=='__main__':setup()
