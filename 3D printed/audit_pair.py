from pathlib import Path
import zipfile,xml.etree.ElementTree as E,numpy as np,json
D=Path(__file__).resolve().parent;ns={'m':'http://schemas.microsoft.com/3dmanufacturing/core/2015/02'}
with zipfile.ZipFile(D/'BikeSense_two_pods.3mf') as z:r=E.fromstring(z.read('3D/3dmodel.model'))
objs=r.findall('m:resources/m:object',ns);items=r.findall('m:build/m:item',ns)
assert len(objs)==len(items)==12
reports=[]
for obj in objs:
 v=np.array([[float(e.attrib[a]) for a in ['x','y','z']] for e in obj.findall('.//m:vertex',ns)])
 t=np.array([[int(e.attrib[a]) for a in ['v1','v2','v3']] for e in obj.findall('.//m:triangle',ns)])
 tri=v[t];edges={}
 for f in tri:
  p=[tuple(np.round(x,4)) for x in f]
  for a,b in [(p[0],p[1]),(p[1],p[2]),(p[2],p[0])]:
   k=tuple(sorted([a,b]));edges[k]=edges.get(k,0)+1
 assert all(x==2 for x in edges.values()),obj.attrib
 vol=np.sum(np.einsum('ij,ij->i',tri[:,0],np.cross(tri[:,1],tri[:,2])))/6
 assert vol>0 and abs(v[:,2].min())<.0001
 assert (v[:,:2].min(axis=0)>5).all() and (v[:,:2].max(axis=0)<251).all(), 'Bed/brim boundary'
 reports.append({'name':obj.attrib['name'],'watertight':True,'volume_mm3':float(vol),'min':v.min(axis=0).tolist(),'max':v.max(axis=0).tolist()})
(D/'pair_print_checks.json').write_text(json.dumps({'objects':12,'build_items':12,'units':r.attrib['unit'],'checks':reports},indent=2))
print('12 watertight meshes; positive volumes; all on bed; 12 independent build items.')
