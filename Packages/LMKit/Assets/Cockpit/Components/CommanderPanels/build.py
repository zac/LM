"""Headless Blender; owned output only. No instruments in production exports."""
import sys, json, math, time
from pathlib import Path
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT))
from geometry import *
COMP=OUT.parent

def ring(prefix,outer,inner,center,z,depth,mat,parent):
    # Four closed strips, genuine empty central aperture, no hidden covering face.
    ox,oy=outer; ix,iy=inner; cx,cy=center
    pieces=[]
    for name,x0,x1,y0,y1 in [('Left',-ox/2,cx-ix/2,-oy/2,oy/2),('Right',cx+ix/2,ox/2,-oy/2,oy/2),('Top',cx-ix/2,cx+ix/2,cy+iy/2,oy/2),('Bottom',cx-ix/2,cx+ix/2,-oy/2,cy-iy/2)]:
        assert x1>x0 and y1>y0
        pieces.append(box(prefix+'_'+name,(x1-x0,y1-y0,depth),((x0+x1)/2,(y0+y1)/2,z),mat,parent))
    return pieces

def screw(name,p,parent,mat):
    # Independent low-poly captive head; no thread/engagement claim.
    pts=[(math.cos(i*math.tau/16)*.003,math.sin(i*math.tau/16)*.003,z) for z in [-.001,.001] for i in range(16)]
    faces=[tuple(reversed(range(16))),tuple(range(16,32))]+[(i,(i+1)%16,(i+1)%16+16,i+16) for i in range(16)]
    return mesh(name,pts,faces,mat,parent,p)

def main():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    for m in list(bpy.data.materials): bpy.data.materials.remove(m)
    scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
    panel=material('Panel_gray',(.29,.33,.32)); frame=material('Support_gray',(.12,.15,.16)); trim=material('Edge_trim',(.055,.065,.067)); metal=material('Captive_heads',(.46,.49,.48))
    root=node('CommanderPanels'); mounts=json.loads((COMP/'Cabin/mounts.json').read_text())['mounts']
    manifest={'schema_version':1,'units':'meters','axes':'+X right +Y overhead -Z forward; local +Z toward crew','root':'/CommanderPanels','root_transform':'identity; place as identity child of Cabin, NOT under a panel mount','status':'PROVISIONAL VISUAL SUPPORTS; no mechanical fit acceptance','dependency_revision':'3ad1a999ff17aea859eaea5750f1c65e66fad673','accepted_LM_revision':'9016960683efabb491dfed16f10ea3ef90196d01','interfaces':{}}
    manifest['dimension_confidence']={'documented': {'DSKY_front_envelope_m': [0.2063496, 0.2032], 'DSKY_thread_pitch_x_m': 0.19558, 'source': 'evidence/DSKY/2003956-B.png, outline 2003956 Rev B, archive page 73', 'limit': 'Does not establish a panel cutout or current rear box'}, 'inherited_provisional': {'FDAI_front_envelope_m': [0.14805, 0.14805], 'panel_poses': 'accepted LM assembly, compatibility only', 'FDAI_seating_plane': None, 'DSKY_seating_plane': None}, 'deliberate_provisional': {'aperture_allowance_per_side_m': 0.003, 'panel_1_outboard_reduction_m': 0.085, 'backing_thickness_m': 0.004, 'rear_flange_z_m': -0.034, 'source': 'DATUM.md and evidence/DECISIONS.md; all new support dimensions are authoring choices'}, 'fit_confidence': 'Computational mesh clearance only; no flight hardware, structural join or instrument attachment qualification'}
    specs=[(1,'FDAI',(.395,.50),(-.055,-.015,.016),(.14805,.14805),.003),(4,'DSKY',(.40,.34),(0,.015,.009),(.2063496,.2032),.003)]
    for number,inst,outer,offset,envelope,gap in specs:
        rec=mounts[f'Mount_Panel_{number}']; name=f'Panel_{number}'
        mount=node(name,rec['position'],rx(rec['rotation_x_degrees']),root)
        shift=.0425 if number==1 else 0
        shell=node(name+'_Shell',(shift,0,0),parent=mount); backing=node(name+'_RemovableBacking',(shift,0,0),parent=mount); edges=node(name+'_Trim',parent=mount); bolts=node(name+'_Fasteners',(shift,0,0),parent=mount)
        aperture=tuple(x+2*gap for x in envelope)
        # Reservation-sized face sheets divided around deliberately generous aperture.
        ring(name+'_Backing',outer,aperture,(offset[0]-shift,offset[1]),-.002,.004,panel,backing)
        # Perimeter channel returns entirely behind face, open rear service access.
        ring(name+'_Return',outer,(outer[0]-.012,outer[1]-.012),(0,0),-.017,.026,frame,shell)
        ring(name+'_RearFlange',outer,(outer[0]-.024,outer[1]-.024),(0,0),-.032,.004,frame,shell)
        # Narrow split collar at aperture edge; never enters the aperture.
        collar=node(name+'_ApertureCollar',(offset[0],offset[1],0),parent=edges)
        ring(name+'_Collar',(aperture[0]+.008,aperture[1]+.008),aperture,(0,0),.0005,.001,trim,collar)
        for i,(x,y) in enumerate([(-outer[0]/2+.009,-outer[1]/2+.009),(outer[0]/2-.009,-outer[1]/2+.009),(-outer[0]/2+.009,outer[1]/2-.009),(outer[0]/2-.009,outer[1]/2-.009)]): screw(name+f'_CaptiveHead_{i+1:02d}',(x,y,.001),bolts,metal)
        interface=node(inst+'_Interface',offset,parent=mount)
        interface['qualification']='empty compatibility datum; not a mechanical contact or live binding'
        manifest['interfaces'][inst]={'panel_path':'/CommanderPanels/'+name,'panel_cabin_relative':rec,'interface_path':'/CommanderPanels/'+name+'/'+inst+'_Interface','interface_parent_local':{'translation_m':list(offset),'rotation_degrees':[0,0,0],'scale':[1,1,1]},'interface_cabin_relative':mounts['Mount_'+inst],'aperture_panel_local':{'center_xy_m':list(offset[:2]),'size_xy_m':list(aperture),'through_z_m':[-.004,.001]},'conservative_visual_front_envelope_xy_m':list(envelope),'deliberate_allowance_per_side_m':gap,'backing_z_m':[-.004,0],'support_rear_z_m':-.034,'surround_outer_size_xy_m':list(outer),'surround_center_panel_local_xy_m':[shift,0],'reservation_outboard_reduction_m':.085 if number==1 else 0,'physical_seating_plane':None,'instrument_attachment_hardware':None,'qualification':'Aperture clears full visual envelope, not a fabrication cutout. Collar is non-contact; instrument attachment unresolved.'}
    bpy.context.view_layer.update(); export(root)
    (OUT/'mounting.json').write_text(json.dumps(manifest,indent=2)+'\n')
    scene.render.engine='BLENDER_WORKBENCH'; scene.render.resolution_x=1200; scene.render.resolution_y=1000; scene.render.resolution_percentage=100
    scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_cavity=True; scene.display.shading.show_shadows=True; scene.world.color=(.08,.08,.08)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'CommanderPanels.blend'))
    print('BUILD PASS')
if __name__=='__main__': main()
