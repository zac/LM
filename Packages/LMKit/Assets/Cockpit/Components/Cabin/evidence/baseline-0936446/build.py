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
   prim.CreatePointsAttr(points); prim.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles)); prim.CreateFaceVertexIndicesAttr([i for t in o.data.loop_triangles for i in t.vertices]); prim.CreateSubdivisionSchemeAttr('none'); prim.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(points))
   prim.CreateNormalsAttr([Gf.Vec3f(*(C.inverted().to_3x3()@t.normal)) for t in o.data.loop_triangles]); prim.SetNormalsInterpolation('uniform')
   UsdShade.MaterialBindingAPI.Apply(prim.GetPrim()).Bind(mats[o.data.materials[0].name])
  prim.GetPrim().SetCustomDataByKey('qualification',o.get('qualification','proposed'))
  for child in sorted(o.children,key=lambda c:c.name): emit(child,path)
 emit(root,''); stage.SetDefaultPrim(stage.GetPrimAtPath('/Cabin')); stage.GetRootLayer().Save(); stage.GetRootLayer().Export(str(OUT/'Cabin.usdc'))
 target=OUT/'Cabin.usdz'
 if target.exists(): target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'Cabin.usdc')),str(target))
def main():
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 for m in list(bpy.data.materials): bpy.data.materials.remove(m)
 scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
 structure=material('Structure',(.55,.57,.55)); dark=material('Shield',(.025,.03,.035)); panel=material('Panel',(.27,.32,.33)); rail=material('Rail',(.57,.62,.65)); glass=material('Pane',(.13,.29,.34)); reserve=material('Reservation',(.77,.42,.12))
 root=node('Cabin'); shell=node('Shell',parent=root); mounts=node('Mounts',parent=root); optical=node('Optical',parent=root)
 box('Cabin_Deck',(1.397,.045,.9144),(0,.1,-.07),structure,shell)
 # Open aft termination: the midsection is deliberately not invented.
 R=1.1684
 for i in range(24):
  a=-math.pi/2+math.pi*(i+.5)/24
  box('Shell_Crown_%02d'%i,(2*R*math.sin(math.pi/48),.025,1.0668),(R*math.sin(a),1.1+R*math.cos(a),.0534),structure,shell,Matrix.Rotation(-a,3,'Z'))
 for sign,side in [(-1,'CDR'),(1,'LMP')]:
  box('Shell_'+side+'_Lower',(.025,1.0,1.0668),(sign*R,.6,.0534),structure,shell)
  beam(side+'_Forward_Longeron',(sign*.44,.98,-.95),(sign*1.15,1.1,-.48),.04,rail,shell)
  beam(side+'_Deck_Strut',(sign*.7,.13,-.5),(sign*1.15,1.1,-.48),.035,rail,shell)
 h=.8128; y=.55; z=-.95
 for sign in [-1,1]:
  box('Hatch_Jamb_'+str(sign).replace('-','N'),(.05,h+.1,.06),(sign*(h/2+.025),y,z),rail,shell)
  box('Hatch_Rail_'+str(sign).replace('-','N'),(h,.05,.06),(0,y+sign*(h/2+.025),z),rail,shell)
 box('Forward_Threshold_Bridge',(.8128,.025,.4228),(0,.1311,-.7386),structure,shell)
 node('Forward_Hatch_Opening',(0,y,z),parent=mounts)['qualification']='nominal .8128 square clearance; no door or hinge'
 specs=[('Panel_1',(.48,.50,.0508),(-.245,1.6,-.91),-10),('Panel_2',(.48,.50,.0508),(.245,1.6,-.91),-10),('Panel_3',(.97,.18,.04),(0,1.264,-.82),-45),('Panel_4',(.40,.34,.04),(0,1.056,-.612),-45),('Panel_5',(.34,.31,.038),(-.5588,.88,-.30),-75),('Panel_6',(.34,.31,.038),(.5588,.88,-.30),-75)]
 manifest={'units':'meters','axes':'+X right +Y overhead -Z forward','root':'/Cabin','all_mounts':'PROPOSED; not mechanical fit qualified','mounts':{}}
 for name,size,p,ang in specs:
  rot=rx(ang); face=Vector(p)+rot@Vector((0,0,size[2]/2)); n=node('Mount_'+name,face,rot,mounts)
  box(name+'_Reservation',size,(0,0,-size[2]/2),panel,n)
  manifest['mounts'][n.name]={'position':list(face),'rotation_x_degrees':ang,'envelope':size,'path':'/Cabin/Mounts/'+n.name}
  if name in ('Panel_1','Panel_4'):
   inst='FDAI' if name=='Panel_1' else 'DSKY'; offset=Vector((-.055,-.015,.016)) if inst=='FDAI' else Vector((0,.015,.009))
   mount=node('Mount_'+inst,offset,parent=n); dims=(.16,.16) if inst=='FDAI' else (.226,.223)
   # Four reservation rails, deliberately no instrument or mating cutout.
   for s in [-1,1]:
    box(inst+'_Reserve_V'+str(s).replace('-','N'),(.004,dims[1],.004),(s*dims[0]/2,0,0),reserve,mount)
    box(inst+'_Reserve_H'+str(s).replace('-','N'),(dims[0],.004,.004),(0,s*dims[1]/2,0),reserve,mount)
   manifest['mounts'][mount.name]={'position':list(face+rot@offset),'rotation_x_degrees':ang,'path':'/Cabin/Mounts/'+n.name+'/'+mount.name,'mating_plane':None,'cutout':None,'clearance_qualified':False}
 for sign,side in [(-1,'CDR'),(1,'LMP')]:
  # Tall projecting side fins visible in both installed Apollo 11 photographs.
  pts=[(sign*.49,1.86,-.96),(sign*.49,1.82,-.74),(sign*.49,1.27,-.51),(sign*.49,1.21,-.66)]
  prism(side+'_Glareshield',pts,(sign,0,0),.012,dark,shell)
  n=node('Mount_'+side+'_MiddleTier',(sign*.91,1.17,-.19),rx(-53.5),mounts)
  box(side+'_MiddleTier_Reservation',(.27,.30,.025),(0,0,-.0125),panel,n)
  manifest['mounts'][n.name]={'position':[sign*.91,1.17,-.19],'rotation_x_degrees':-53.5,'path':'/Cabin/Mounts/'+n.name,'panel_number':'unresolved; early tier basis'}
 eye=Vector((-.5588,1.78,-.38)); node('CDR_Eye',eye,parent=optical)
 inner=[eye+Vector(p) for p in [(-.4415295,0,-.1183075),(.1097963,.0494183,-.5648532),(.0175769,-.4308411,-.2009045)]]
 normal=(inner[1]-inner[0]).cross(inner[2]-inner[0]).normalized()
 if normal.dot(eye-inner[0])<0: normal=-normal
 outer=[eye+(p-eye)*normal.dot(inner[0]-normal*.02-eye)/normal.dot(p-eye) for p in inner]
 for side,mirror in [('CDR',1),('LMP',-1)]:
  for layer,pts0 in [('Inner',inner),('Outer',outer)]:
   pts=[Vector((p.x*mirror,p.y,p.z)) for p in pts0]; nn=Vector((normal.x*mirror,normal.y,normal.z)); right=(pts[1]-pts[0]).normalized(); up=nn.cross(right).normalized(); rot=Matrix((right,up,nn)).transposed()
   datum=node(side+'_Window_'+layer,pts[0],rot,optical); local=[rot.transposed()@(p-pts[0]) for p in pts]
   prism(side+'_Pane_'+layer,local,(0,0,1),.003,glass,datum)
   for i in range(3): beam(side+'_Frame_'+layer+'_'+str(i),local[i],local[(i+1)%3],.024,rail,datum)
   if side=='CDR':
    # Mount-only LPD layers: app owns calibrated markings and live guidance.
    lpd=node('LPD_'+layer,parent=datum); lpd['qualification']='distinct marking-layer mount; no artwork or simulation duplicated'
   manifest.setdefault('optical',{})[datum.name]={'position':list(pts[0]),'normal':list(nn),'right':list(right),'corners':[list(p) for p in pts]}
 # Upper and lower fascia rails join the window surrounds to the crown/deck skeleton.
 for sign,side in [(-1,'CDR'),(1,'LMP')]:
  beam(side+'_Window_Upper_Support',(sign*.45,1.85,-.97),(sign*.66,2.04,-.48),.04,structure,shell)
  beam(side+'_Window_Lower_Support',(sign*.55,1.31,-.59),(sign*.73,.98,-.50),.05,structure,shell)
 bpy.context.view_layer.update()
 (OUT/'mounts.json').write_text(json.dumps(manifest,indent=2)+'\n'); export(root)
 scene.render.engine='BLENDER_WORKBENCH'; scene.render.resolution_x=1000; scene.render.resolution_y=900; scene.render.resolution_percentage=100
 scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_shadows=True; scene.display.shading.show_cavity=True; scene.display.shading.background_type='WORLD'; scene.world.color=(.055,.055,.055)
 def camera(name,p,target,ortho=None):
  d=bpy.data.cameras.new(name); o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=v(p); o.rotation_euler=(v(target)-o.location).to_track_quat('-Z','Y').to_euler(); d.clip_start=.01; d.lens=20
  if ortho: d.type='ORTHO'; d.ortho_scale=ortho
  scene.camera=o; scene.render.filepath=str(OUT/'reviews'/(''+name+'.png')); bpy.ops.render.render(write_still=True); return o
 camera('front',(0,1.25,4),(0,1.2,-.6),2.8)
 # Section review hides only near-side shell skin; all mounts remain visible.
 near=[o for o in shell.children if o.name=='Shell_LMP_Lower' or (o.name.startswith('Shell_Crown_') and int(o.name[-2:])>=12)]
 for o in near:o.hide_render=True
 camera('side',(4,1.25,.0),(0,1.2,-.25),2.7)
 for o in near:o.hide_render=False
 # Pane surfaces hidden in Workbench only to expose optical apertures; USD uses opacity .08.
 panes=[o for o in bpy.data.objects if '_Pane_' in o.name]
 for o in panes:o.hide_render=True
 camera('crew-eye',eye,(-.45,1.6,-1.0))
 for o in panes:o.hide_render=False
 scene.camera=bpy.data.objects['front']; scene.render.filepath='//reviews/front.png'; scene.render.film_transparent=False
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Cabin.blend'))
if __name__=='__main__': main()
