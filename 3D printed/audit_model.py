"""Regenerate and audit nominal CAD geometry; does not certify physical strength."""
import runpy,json
from pathlib import Path
D=Path(__file__).resolve().parent;m=runpy.run_path(str(D/'build_model.py'));p=m['parts'];r=m['refs'];out={}
for a,s in r.items():
 for b,t in p.items():
  v=s.intersect(t).Volume()
  if v>0.001:out[a+' / '+b]=v
assert not out,out
out['component_envelope_interferences_mm3']=0
out['travel_check']={}
for moving in ['04_thumb_paddle','06_paddle_cap']:
 for fixed in ['01_body_clamp','03_led_faceplate','05_switch_carrier']:
  v=p[moving].translate((0,0,-.5)).intersect(p[fixed]).Volume()
  out['travel_check'][moving+' / '+fixed]=round(v,6)
  assert v<.001,(moving,fixed,v)
(D/'fit_checks.json').write_text(json.dumps(out,indent=2))
print('Component envelopes and 0.5 mm button travel checked')

from pathlib import Path
import cadquery as cq, numpy as np, json, struct
D=Path(__file__).resolve().parent;res={}
for p in sorted(D.glob('0*.stl')):
    raw=p.read_bytes();n=struct.unpack_from('<I',raw,80)[0]
    dt=np.dtype([('normal','<f4',(3,)),('v','<f4',(3,3)),('attr','<u2')])
    data=np.frombuffer(raw,dt,count=n,offset=84);v=data['v'].astype(float)
    edges={}
    for tri in v:
        tv=[tuple(np.round(x,4)) for x in tri]
        for a,b in [(tv[0],tv[1]),(tv[1],tv[2]),(tv[2],tv[0])]:
            k=tuple(sorted([a,b]));edges[k]=edges.get(k,0)+1
    bad=sum(x!=2 for x in edges.values())
    volume=np.sum(np.einsum('ij,ij->i',v[:,0],np.cross(v[:,1],v[:,2])))/6
    solid=cq.importers.importStep(str(p.with_suffix('.step'))).val()
    res[p.name]={'triangles':n,'nonmanifold_edges':bad,'signed_volume_mm3':float(volume),'step_roundtrip_valid':solid.isValid(),'step_solid_count':len(solid.Solids())}
    assert bad==0 and volume>0 and solid.isValid() and len(solid.Solids())==1,res[p.name]
asm=cq.importers.importStep(str(D/'BikeSense_assembly.step')).val()
res['assembly']={'valid':asm.isValid(),'solids':len(asm.Solids())}
assert asm.isValid() and len(asm.Solids())==6
(D/'export_checks.json').write_text(json.dumps(res,indent=2));print(json.dumps(res,indent=2))


# Assumed M3 socket bolt, OD7 x 0.5 washer, AF5.5 nut and tool envelopes.
import math, zipfile, xml.etree.ElementTree as ET
p=m['parts'];cyl=m['cyl'];cq=m['cq'];hcheck={}
for y in [-18,18]:
    shaft=cyl(1.5,20,(0,y,-11))
    head=cyl(2.8,3,(0,y,9))
    washer=cyl(3.5,.5,(0,y,8.5)).cut(cyl(1.6,.7,(0,y,8.4)))
    nut_approach=cq.Workplane('XY').polygon(6,5.5/math.cos(math.pi/6)).extrude(19.2).translate((0,y,-25)).val()
    driver=cyl(3,28,(0,y,12))
    for name,s in [('shaft',shaft),('head',head),('washer',washer),('nut_insertion',nut_approach),('driver',driver)]:
        for pn in ['01_body_clamp','02_lower_clamp']:
            v=s.intersect(p[pn]).Volume()
            assert v<.001,(y,name,pn,v)
        hcheck[str(y)+'_'+name]='clear'
# Carrier screw heads (maximum OD4 x 2 high), driver, and clearance portions.
# Thread engagement in undersized plastic pilot holes is intentional.
for y in [-43.3,-32.7]:
    head=cyl(2,2,(0,y,7))
    shaft_clearance=cyl(1,1.6,(0,y,5.4))
    driver=cyl(1.5,20,(0,y,9))
    for pn in ['01_body_clamp','03_led_faceplate','04_thumb_paddle','06_paddle_cap']:
        assert head.intersect(p[pn]).Volume()<.001,(y,'carrier screw head',pn)
    assert head.intersect(r['switch']).Volume()<.001
    assert shaft_clearance.intersect(p['05_switch_carrier']).Volume()<.001
    # Carrier screws are installed BEFORE the faceplate/plunger.
    assert driver.intersect(p['01_body_clamp']).Volume()<.001
    assert driver.intersect(r['switch']).Volume()<.001
    hcheck[str(y)+'_carrier_screw']='head, carrier clearance and assembly driver access clear'
with zipfile.ZipFile(D/'BikeSense_single_plate.3mf') as z:
    names=z.namelist();entry=next(x for x in names if x.lower().endswith('.model'))
    root=ET.fromstring(z.read(entry));ns={'m':'http://schemas.microsoft.com/3dmanufacturing/core/2015/02'}
    vertices=root.findall('.//m:vertex',ns)
    assert root.attrib.get('unit','millimeter')=='millimeter'
    assert len(vertices)>100
hcheck['print_plate_3mf']={'readable':True,'units':'mm','vertices':len(vertices),'layout':m['report']['print_plate']}
(D/'hardware_checks.json').write_text(json.dumps(hcheck,indent=2))
print('All checks passed: geometry, STL topology, STEP round-trip, nominal component fit, button travel, fasteners, tool access, 3MF layout.')
