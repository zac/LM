"""blender -b --factory-startup --python Assets/Cockpit/Components/Cabin/build.py
Native Z-up authoring; direct USD export physically transforms every local basis.
No add-ons, textures, network, heavy render or app code dependencies.
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
 stage=Usd.Stage.CreateNew(str(OUT/'Cabin.usda')); UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1)
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
   prim.CreatePointsAttr(points); prim.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles)); prim.CreateFaceVertexIndicesAttr([i for t in o.data.loop_triangles for i in t.vertices]); prim.CreateSubdivisionSchemeAttr('none'); prim.CreateDoubleSidedAttr(True); prim.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(points))
   prim.CreateNormalsAttr([Gf.Vec3f(*(C.inverted().to_3x3()@t.normal)) for t in o.data.loop_triangles]); prim.SetNormalsInterpolation('uniform')
   UsdShade.MaterialBindingAPI.Apply(prim.GetPrim()).Bind(mats[o.data.materials[0].name])
  prim.GetPrim().SetCustomDataByKey('qualification',o.get('qualification','proposed'))
  for child in sorted(o.children,key=lambda c:c.name): emit(child,path)
 emit(root,''); stage.SetDefaultPrim(stage.GetPrimAtPath('/Cabin')); stage.GetRootLayer().Save(); stage.GetRootLayer().Export(str(OUT/'Cabin.usdc'))
 target=OUT/'Cabin.usdz'
 if target.exists(): target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'Cabin.usdc')),str(target))
# Helpers above are retained from Cabin baseline 0936446 / original eb4efc1.
# Model below is a replaceable visual liner, not a pressure-vessel drawing.
def surface(name,points,mat,parent):
 # Triangulate potentially warped boundary; outward solid extrusion behind each face.
 from mathutils.geometry import tessellate_polygon
 pts=[Vector(p) for p in points]
 for i,tri in enumerate(tessellate_polygon([pts])):
  if isinstance(tri[0],int):tri=[pts[j] for j in tri]
  n=(tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
  center=sum(tri,Vector())/3
  # Interior reference ensures inward visible face; thickness extends outside cabin.
  if n.dot(Vector((0,1.1,0))-center)<0:n=-n
  prism(name+'_%02d'%i,tri,n,.025,mat,parent)
def main():
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 for m in list(bpy.data.materials):bpy.data.materials.remove(m)
 scene=bpy.context.scene; scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
 scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1100;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
 scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True;scene.display.shading.background_type='WORLD';scene.world.color=(.045,.06,.08)
 liner=material('WarmGrayLiner',(.58,.59,.55));deckmat=material('Deck',(.31,.34,.33));rail=material('Structure',(.43,.46,.45));hatchmat=material('Hatch',(.66,.67,.61));dark=material('Recess',(.10,.12,.12));tread=material('DeckGrip',(.46,.43,.34))
 root=node('Cabin');shell=node('Shell',parent=root);mounts=node('Mounts',parent=root);optical=node('Optical',parent=root)
 groups={n:node(n,parent=shell) for n in ['Cutaway_Forward','Cutaway_CDR','Cutaway_LMP','Cutaway_Ceiling','Cutaway_Aft','Cutaway_Deck','Supports','Hatches']}
 baseline=json.loads((OUT/'evidence/baseline-0936446/mounts.json').read_text())
 manifest=dict(baseline);manifest['schema']='lmkit.cabin.mounts.v2';manifest['configuration']='descent-ready, closed static hatch surfaces';manifest['geometry_interface']='interface-v2.json'
 # Stable mount hierarchy; no planning blanks, instrument meshes, surrounds or panes.
 for name,row in baseline['mounts'].items():
  parent=mounts
  if name in ['Mount_FDAI','Mount_DSKY']:
   parent=bpy.data.objects['Mount_Panel_1' if name=='Mount_FDAI' else 'Mount_Panel_4']
   desired=pose(row['position'],rx(row['rotation_x_degrees']))
   row_parent=baseline['mounts'][parent.name]
   n=node(name,parent=parent);n.matrix_local=pose(row_parent['position'],rx(row_parent['rotation_x_degrees'])).inverted()@desired
  else:n=node(name,row['position'],rx(row['rotation_x_degrees']),parent)
 for side,sgn in [('CDR',-1),('LMP',1)]:node(side+'_Eye',(sgn*.5588,1.78,-.38),parent=optical)
 for name,row in baseline['optical'].items():
  nn=Vector(row['normal']);right=Vector(row['right']);up=nn.cross(right).normalized()
  datum=node(name,row['position'],Matrix((right,up,nn)).transposed(),optical)
  datum['qualification']='legacy comparison mount only; WindowsLPD owns optical review and all glazing'
  if name.startswith('CDR'):node('LPD_'+name.split('_')[-1],parent=datum)
 R=1.1684;floor=.1225;fore=-.48;aft=1.15;central=.43;roof=1.1+math.sqrt(R*R-central*central)
 # Continuous deck, retaining original named standing deck as inset.
 box('Cabin_Deck',(1.397,.045,.9144),(0,.1,-.07),deckmat,groups['Cutaway_Deck'])
 for side,sgn in [('CDR',-1),('LMP',1)]:
  box(side+'_Deck_Outboard',((R-.6985),.045,aft-fore),(sgn*(R+.6985)/2,.1,(aft+fore)/2),deckmat,groups['Cutaway_Deck'])
 box('Deck_Aft_Extension',(1.397,.045,aft-.3872),(0,.1,(aft+.3872)/2),deckmat,groups['Cutaway_Deck'])
 # Forward deck follows oblique front wall boundary exactly.
 surface('Deck_Nose',[(-R,floor,fore),(-central,floor,-1.02),(central,floor,-1.02),(R,floor,fore),(.6985,floor,fore),(.6985,floor,-.5272),(-.6985,floor,-.5272),(-.6985,floor,fore)],deckmat,groups['Cutaway_Deck'])
 # Circumferential liner with flat central roof insert for transfer hatch.
 angle=math.asin(central/R)
 arc=[(R*math.sin(angle+(math.pi/2-angle)*i/12),1.1+R*math.cos(angle+(math.pi/2-angle)*i/12)) for i in range(13)]
 for side,sgn in [('CDR',-1),('LMP',1)]:
  group=groups['Cutaway_'+side]
  box(side+'_Lower_Liner',(.025,1.1-floor,aft-fore),(sgn*(R+.0125),(1.1+floor)/2,(aft+fore)/2),liner,group)
  for i in range(12):
   a,b=arc[i],arc[i+1]
   surface(side+'_Crown_%02d'%i,[(sgn*a[0],a[1],fore),(sgn*b[0],b[1],fore),(sgn*b[0],b[1],aft),(sgn*a[0],a[1],aft)],liner,groups['Cutaway_Ceiling'] if i<6 else group)
  # Continuous front cheek panels around open construction triangle.
  pts=baseline['optical'][side+'_Window_Inner']['corners'];A,B,D=pts
  low=(sgn*central,floor,-1.02);high=(sgn*central,roof,-1.02)
  edge=[(sgn*x,y,fore) for x,y in reversed(arc)]
  surface(side+'_Front_Lower',[low,(sgn*R,floor,fore),(sgn*R,1.1,fore),A,D],liner,groups['Cutaway_Forward'])
  surface(side+'_Front_Inboard',[low,D,B,high],liner,groups['Cutaway_Forward'])
  surface(side+'_Front_Upper',[B,A,(sgn*R,1.1,fore)]+edge[1:]+[high],liner,groups['Cutaway_Forward'])
 # Trim the finite wall thickness to the provisional eye/construction rays.
 # This prevents oblique cheek thickness from closing the nominal aperture edge.
 import bmesh
 for side in ['CDR','LMP']:
  eye=Vector((-.5588 if side=='CDR' else .5588,1.78,-.38));pts=[Vector(p) for p in baseline['optical'][side+'_Window_Inner']['corners']]
  verts=[eye+(p-eye)*k for k in [.35,3] for p in pts]
  cutter=mesh(side+'_Ray_Aperture_Cutter',verts,[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],rail,None)
  bm=bmesh.new();bm.from_mesh(cutter.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(cutter.data);bm.free()
  bpy.context.view_layer.update()
  for o in list(groups['Cutaway_Forward'].children_recursive):
   if o.type!='MESH' or not o.name.startswith(side+'_Front'):continue
   mod=o.modifiers.new('Clear_construction_aperture','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
   bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
  bpy.data.objects.remove(cutter,do_unlink=True)
 # Center forward backing, hatch opening left clear of liner.
 h=.8128;hy=.55;hz=-1.02
 for sgn in [-1,1]:
  box('Hatch_Jamb_'+('N1' if sgn<0 else '1'),(central-h/2,h,.035),(sgn*(central+h/2)/2,hy,hz-.0175),rail,groups['Cutaway_Forward'])
 box('Forward_Above_Hatch',(2*central,roof-(hy+h/2),.025),(0,(roof+hy+h/2)/2,hz-.0125),liner,groups['Cutaway_Forward'])
 box('Forward_Threshold',(2*central,hy-h/2-floor,.025),(0,(hy-h/2+floor)/2,hz-.0125),rail,groups['Cutaway_Forward'])
 node('Forward_Hatch_Opening',(0,hy,hz),parent=mounts)
 leaf=node('Forward_Hatch_Closed',(0,hy,hz),parent=groups['Hatches']);box('Forward_Hatch_Leaf',(h,h,.032),(0,0,-.016),hatchmat,leaf)
 # Shallow concentric surface relief: no hinge/pivot or latch-operation claims.
 box('Forward_Hatch_Inner_Field',(h-.12,h-.12,.018),(0,0,.009),liner,leaf)
 for sgn in [-1,1]:box('Forward_Hatch_Rib_'+str(sgn).replace('-','N'),(.035,h-.1,.023),(sgn*.23,0,.018),rail,leaf)
 # Aft bulkhead shaped to section; coarse raised engine cover is explicitly approximate.
 contour=[(-R,floor,aft),(R,floor,aft),(R,1.1,aft)]+[(x,y,aft) for x,y in reversed(arc[:-1])]+[(-x,y,aft) for x,y in arc]+[(-R,floor,aft)]
 surface('Aft_Bulkhead',contour[:-1],liner,groups['Cutaway_Aft'])
 box('Aft_Engine_Cover_Approximate',(.63,.32,.55),(0,floor+.16,aft-.275),rail,groups['Cutaway_Aft'])
 # Roof is a rectangle with a separately addressable closed circular transfer hatch.
 rad=.4064;cz=.65
 ring=[(rad*math.cos(2*math.pi*i/48),roof,cz+rad*math.sin(2*math.pi*i/48)) for i in range(48)]
 # Fan annulus to rectangular border, parameterized by radial rectangle intersection.
 outer=[]
 for p in ring:
  dx,dz=p[0],p[2]-cz;t=min(central/abs(dx) if abs(dx)>1e-8 else 1e9,((aft-cz) if dz>0 else (cz-fore))/abs(dz) if abs(dz)>1e-8 else 1e9)
  outer.append((dx*t,roof,cz+dz*t))
 # Use polygon boolean-free ring; rectangle corners added in angular order below.
 angles=sorted(set([2*math.pi*i/48 for i in range(48)]+[math.atan2(z-cz,x)%(2*math.pi) for x in [-central,central] for z in [fore,aft]]))
 for i,a in enumerate(angles):
  b=angles[(i+1)%len(angles)]
  def rr(t):
   dx,dz=math.cos(t),math.sin(t);k=min(central/max(abs(dx),1e-12),((aft-cz) if dz>0 else (cz-fore))/max(abs(dz),1e-12));return (dx*k,roof,cz+dz*k)
  surface('Roof_Hatch_Surround_%02d'%i,[(rad*math.cos(a),roof,cz+rad*math.sin(a)),rr(a),rr(b),(rad*math.cos(b),roof,cz+rad*math.sin(b))],liner,groups['Cutaway_Ceiling'])
 top=node('Transfer_Hatch_Closed',(0,roof,cz),parent=groups['Hatches'])
 prism('Transfer_Hatch_Leaf',[(rad*math.cos(a),0,rad*math.sin(a)) for a in angles],(0,-1,0),.032,hatchmat,top)
 box('Transfer_Hatch_Stiffener',(.56,.025,.05),(0,-.02,0),rail,top)
 # Front roof bridge between flattened crown and central forward surface.
 surface('Forward_Roof_Bridge',[(-central,roof,-1.02),(central,roof,-1.02),(central,roof,fore),(-central,roof,fore)],liner,groups['Cutaway_Ceiling'])
 # Mount support rails are behind existing CommanderPanels envelope, not copied surrounds.
 for x in [-.40,.40]:beam('Center_Stack_Support_'+str(x).replace('-','N').replace('.','_'),(x,.99,-1.0),(x,1.95,-1.0),.025,rail,groups['Supports'])
 for sgn,side in [(-1,'CDR'),(1,'LMP')]:
  for z in [-.35,.35]:beam(side+'_Side_Support_'+str(z).replace('-','N').replace('.','_'),(sgn*1.11,.16,z),(sgn*1.11,1.30,z),.022,rail,groups['Supports'])
 for i in range(10):
  z=-.43+i*.14
  for side,sgn in [('CDR',-1),('LMP',1)]:box(side+'_Deck_Grip_%02d'%i,(.56,.0015,.021),(sgn*.48,floor+.00075,z),tread,groups['Cutaway_Deck'])
 # Exact accepted docking aperture from committed WindowsLPD contract.
 win=json.loads((OUT/'evidence/foundation/windows-interface-80c9b2d.json').read_text());dock=win['docking']
 rot=Matrix((dock['right'],Vector(dock['normal_toward_cabin']).cross(Vector(dock['right'])),dock['normal_toward_cabin'])).transposed()
 cutter=box('Docking_Aperture_Cutter',(*dock['shell_hole_size_m'],.30),dock['center'],rail,None,rot)
 bpy.context.view_layer.update()
 for o in list(groups['Cutaway_Ceiling'].children_recursive):
  if o.type!='MESH' or not o.name.startswith('CDR_Crown'):continue
  mod=o.modifiers.new('Docking_aperture','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
  bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 bpy.data.objects.remove(cutter,do_unlink=True)
 # Remove coincident slivers from exact boolean intersections before USD triangulation.
 for o in bpy.data.objects:
  if o.type!='MESH':continue
  bm=bmesh.new();bm.from_mesh(o.data)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
  bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
  bmesh.ops.triangulate(bm,faces=list(bm.faces))
  bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
 node('Docking_Window_Opening',dock['center'],rot,mounts)
 manifest['docking_opening']=dock
 bpy.context.view_layer.update()
 manifest['hatches']={'Forward_Hatch_Closed':{'position':[0,hy,hz],'state':'closed static','qualified_hinge':False},'Transfer_Hatch_Closed':{'position':[0,roof,cz],'state':'closed static','diameter':2*rad,'qualified_hinge':False}}
 manifest['cutaway_groups']={k:'/Cabin/Shell/'+k for k in groups if k.startswith('Cutaway')};manifest['mount_migration']='Panel and instrument world poses unchanged; optical nodes comparison only; Forward_Hatch_Opening moved -.07 Z'
 oldstage=Usd.Stage.Open(str(OUT/'evidence/baseline-0936446/Cabin.usda'))
 oldpaths={p.GetName():str(p.GetPath()) for p in oldstage.Traverse() if p.IsA(UsdGeom.Mesh)}
 newnames={o.name for o in bpy.data.objects if o.type=='MESH'}
 migration={'baseline':'09364460e8be570338f3d39a07067fe2bee0b044','interface':'interface-v2.json','removed_visual_nodes':[{"name":n,"old_path":p} for n,p in oldpaths.items() if n not in newnames],'retained_metadata':'All original Mounts and Optical node names/paths; Optical are comparison-only, no meshes','new_cutaways':manifest['cutaway_groups'],'installation':'Replace complete Cabin root once. Install WindowsLPD and PanelInventory separately. Do not reinstall old Cabin panes/reservations/glareshields. Existing instruments/CommanderPanels remain independent. No collider/input binding implied.'}
 migration['retained_visual_names']=[{'name':n,'old_path':oldpaths[n],'new_path':'/Cabin/Shell/'+('Cutaway_Deck/' if n=='Cabin_Deck' else 'Cutaway_Forward/')+n,'note':'Same useful name; hierarchy or construction may change. Replace whole root.'} for n in sorted(set(oldpaths)&newnames)]
 (OUT/'migration.json').write_text(json.dumps(migration,indent=2)+'\n')
 (OUT/'mounts.json').write_text(json.dumps(manifest,indent=2)+'\n');export(root)
 def camera(name,p,target,hide=(),ortho=None):
  hidden=[]
  for key in hide:
   group=groups[key];hidden.extend([group]+list(group.children_recursive))
  for o in hidden:o.hide_render=True
  d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=v(p);o.rotation_euler=(v(target)-o.location).to_track_quat('-Z','Y').to_euler();d.clip_start=.01;d.lens=16
  if ortho:d.type='ORTHO';d.ortho_scale=ortho
  scene.camera=o;scene.render.filepath=str(OUT/'reviews'/(name+'.png'));bpy.ops.render.render(write_still=True)
  for o in hidden:o.hide_render=False
 camera('front',(0,1.25,3.8),(0,1.2,-.5),('Cutaway_Aft',),2.8)
 camera('side',(4,1.35,.12),(0,1.1,.05),('Cutaway_LMP','Cutaway_Ceiling'),3.0)
 camera('crew-eye',(-.5588,1.78,-.38),(-.50,1.53,-1.15))
 camera('lmp-eye',(.5588,1.78,-.38),(.50,1.53,-1.15))
 camera('rear',(0,1.62,-.38),(0,1.32,1.15))
 camera('overhead',(0,1.65,-.10),(0,2.2,.50))
 camera('overhead-cutaway',(0,5,.15),(0,.5,.15),('Cutaway_Ceiling','Hatches'),3.0)
 camera('side-interior',(0,1.70,-.05),(-1.15,1.35,.10))
 scene.camera=bpy.data.objects['crew-eye'];scene.render.filepath='//reviews/crew-eye.png';scene.render.film_transparent=False
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Cabin.blend'))
if __name__=='__main__':main()
