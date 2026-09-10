import bpy,json,math,hashlib,itertools
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
R=Path('/Users/zac/Projects/personal/lm/LMKit');D=R/'Assets/Cockpit/Components';O=Path('/tmp/lmkit-final-new-component-review');C=Matrix.Rotation(math.pi/2,4,'X')
bpy.ops.wm.read_factory_settings(use_empty=True)
inv=json.loads((D/'PanelInventory/inventory.json').read_text())
def pose(p):
 x,y,z,w=p['quaternion_xyzw'];return Matrix.Translation(Vector(p['translation_m']))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
def slot(sid):
 for p in inv['panels']:
  for s in p['slots']:
   if s['id']==sid:return pose(p['pose'])@pose(s['pose'])
 raise KeyError(sid)
a=json.loads((D/'AltitudeRate/interface.json').read_text());cross=json.loads((D/'CrossPointer/interface.json').read_text());controls=json.loads((D/'DescentControls/interface.json').read_text())
configs=[('InteriorDetails','InteriorDetails',Matrix.Identity(4)),('BreakerBanks','BreakerBanks',Matrix.Identity(4)),('AltitudeRate','AltitudeRate',slot(a['slot'])@pose(a['slot_local_pose'])),('CrossPointer','CrossPointer',slot(cross['mounting']['slot_id']))]
configs += [('DescentControls',item['id'],slot(item['slot'])) for item in controls['components']]
assets={};inputs={}
for folder,name,matrix in configs:
 p=D/folder/(name+'.usdz');before=set(bpy.data.objects);bpy.ops.wm.usd_import(filepath=str(p));new=set(bpy.data.objects)-before
 for ob in new:
  if ob.parent not in new:ob.matrix_world=C@matrix@C.inverted()@ob.matrix_world
 assets[name]=[o for o in new if o.type=='MESH'];inputs[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'matrix_cabin_row_major':list(map(list,matrix)),'meshes':len(assets[name])}
bpy.context.view_layer.update()
def bounds(ob):
 pts=[ob.matrix_world@Vector(p) for p in ob.bound_box];return [[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
def overlap(a,b):return all(a[0][i]<=b[1][i]+1e-7 and b[0][i]<=a[1][i]+1e-7 for i in range(3))
allmeshes=[o for group in assets.values() for o in group];bounds_cache={o:bounds(o) for o in allmeshes};trees={}
def tree(o):
 if o not in trees:
  o.data.calc_loop_triangles();trees[o]=BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[t.vertices for t in o.data.loop_triangles],all_triangles=True)
 return trees[o]
for name,objs in assets.items():
 pts=[C.inverted()@(o.matrix_world@Vector(p)) for o in objs for p in o.bound_box];inputs[name]['aabb_cabin_m']=[[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
results=[]
for one,two in itertools.combinations(assets,2):
 candidates=[];crossings=[]
 for a in assets[one]:
  for b in assets[two]:
   if overlap(bounds_cache[a],bounds_cache[b]):
    candidates.append([a.name,b.name]);pairs=tree(a).overlap(tree(b))
    if pairs:crossings.append({'a':a.name,'b':b.name,'triangle_pairs':len(pairs)})
 results.append({'a':one,'b':two,'broadphase_candidates':len(candidates),'candidates':candidates,'surface_crossings':crossings})
# Representative face-point rays from pinned commander design eye. Cross-component only.
eye=C@Vector((-.5588,1.78,-.38));occlusions=[];rays=[]
for name in ['AltitudeRate','CrossPointer','AttitudeMode','DescentRate']:
 m=Matrix(inputs[name]['matrix_cabin_row_major']);inverse=m.inverted()@C.inverted();points=[inverse@(o.matrix_world@v.co) for o in assets[name] for v in o.data.vertices]
 lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)]);center=(lo+hi)/2
 for sample,(fx,fy) in enumerate([(0,0),(-.25,0),(.25,0),(0,-.25),(0,.25)]):
  target=center.copy();target.x+=fx*(hi.x-lo.x);target.y+=fy*(hi.y-lo.y);target.z=hi.z+.001
  target=C@(m@target);direction=(target-eye).normalized();distance=(target-eye).length;hits=[]
  for peer,meshes in assets.items():
   if peer==name:continue
   for ob in meshes:
    location,normal,index,hitdist=tree(ob).ray_cast(eye,direction,distance)
    if location is not None:hits.append({'component':peer,'mesh':ob.name,'distance_m':hitdist})
  rays.append({'target_component':name,'sample':sample,'hits':hits})
  if hits:occlusions.append({'target_component':name,'sample':sample,'hits':hits})
report={'method':'Read-only Blender USDZ import; exact contracted slot transforms; new-new mesh broadphase AABB followed by BVH triangle surface overlap. Neutral authored state. No source save or render.','inputs':inputs,'inventory_sha256':hashlib.sha256((D/'PanelInventory/inventory.json').read_bytes()).hexdigest(),'results':results,'limits':['No self-intersection test within a single component','No containment or continuous motion/hand sweep proof','No original-foundation revalidation; previous fixture backing penetration remains outside scope','No material transparency/legibility/RealityKit/simulator acceptance'],'representative_face_rays':rays,'representative_face_occlusions':occlusions,'surface_crossing_pairs':sum(len(r['surface_crossings']) for r in results)}
(O/'results.json').write_text(json.dumps(report,indent=2)+'\n');print('NEW_COMPONENT_CHECK',len(results),'component pairs',report['surface_crossing_pairs'],'crossing mesh pairs')
