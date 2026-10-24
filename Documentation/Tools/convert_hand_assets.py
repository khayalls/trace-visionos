"""Convert the CC0 Godot XR Tools hand glTF into TRACE's fixed skin buffers.
Preserves modeled anatomy, UVs, normals, and all four authored skin influences.
No animation is imported. Runtime deformation uses measured TRACE joint positions.
Run from the TRACE project directory: python3 Documentation/Tools/convert_hand_assets.py
"""
import base64
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREFIXES = {'Thumb': 'thumb', 'Index': 'indexFinger', 'Middle': 'middleFinger', 'Ring': 'ringFinger', 'Little': 'littleFinger'}


def subdivide(mesh):
    """One Loop subdivision pass, welding only positions across UV/normal seams."""
    positions=mesh['positions']; weld={}; ids=[]; unique=[]
    for p in positions:
        key=tuple(round(v,6) for v in p)
        if key not in weld: weld[key]=len(unique); unique.append(p)
        ids.append(weld[key])
    neighbors=[set() for _ in unique]; edges={}
    triangles=[mesh['indices'][i:i+3] for i in range(0,len(mesh['indices']),3)]
    for triangle in triangles:
        a,b,c=[ids[v] for v in triangle]
        for u,v,opposite in ((a,b,c),(b,c,a),(c,a,b)):
            if u==v: continue
            neighbors[u].add(v);neighbors[v].add(u)
            edges.setdefault(tuple(sorted((u,v))),set()).add(opposite)
    boundary=[set() for _ in unique]
    for (a,b),opposites in edges.items():
        if len(opposites)==1: boundary[a].add(b);boundary[b].add(a)
    smooth=[]
    for i,p in enumerate(unique):
        if len(boundary[i])==2:
            smooth.append([0.75*p[k]+0.125*sum(unique[n][k] for n in boundary[i]) for k in range(3)])
        elif neighbors[i]:
            n=len(neighbors[i]);beta=3/16 if n==3 else 3/(8*n)
            smooth.append([(1-n*beta)*p[k]+beta*sum(unique[j][k] for j in neighbors[i]) for k in range(3)])
        else: smooth.append(p)
    mesh['positions']=[smooth[i] for i in ids]
    edge_ids={};new_indices=[]
    def midpoint(a,b):
        key=tuple(sorted((a,b)))
        if key in edge_ids: return edge_ids[key]
        geometric=tuple(sorted((ids[a],ids[b])));opposites=edges.get(geometric,set())
        p=([0.375*(positions[a][k]+positions[b][k])+0.125*sum(unique[n][k] for n in opposites) for k in range(3)] if len(opposites)==2 else [(x+y)/2 for x,y in zip(positions[a],positions[b])])
        n=[x+y for x,y in zip(mesh['normals'][a],mesh['normals'][b])];length=sum(x*x for x in n)**0.5
        influence={}
        for v in (a,b):
            for j,w in zip(mesh['jointIndices'][v],mesh['weights'][v]): influence[j]=influence.get(j,0)+w*0.5
        strongest=sorted(influence.items(),key=lambda item:item[1],reverse=True)[:4]
        while len(strongest)<4: strongest.append((0,0))
        total=sum(w for j,w in strongest)
        index=len(mesh['positions']);edge_ids[key]=index
        mesh['positions'].append([round(v,8) for v in p])
        mesh['normals'].append([round(v/length,7) for v in n])
        mesh['uvs'].append([(x+y)/2 for x,y in zip(mesh['uvs'][a],mesh['uvs'][b])])
        mesh['jointIndices'].append([j for j,w in strongest]);mesh['weights'].append([w/total for j,w in strongest])
        return index
    for a,b,c in triangles:
        ab=midpoint(a,b);bc=midpoint(b,c);ca=midpoint(c,a)
        new_indices.extend([a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca])
    mesh['indices']=new_indices

def convert(side):
    filename = 'Hand_Nails_' + ('L' if side == 'Left' else 'R') + '.gltf'
    doc = json.loads((ROOT/'Documentation/ThirdParty/HandSource'/filename).read_text())
    data = base64.b64decode(doc['buffers'][0]['uri'].split(',')[1])
    def accessor(index):
        a = doc['accessors'][index]
        v = doc['bufferViews'][a['bufferView']]
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        fmt = '<' + {5121: 'B', 5123: 'H', 5126: 'f'}[a['componentType']]*n
        stride = v.get('byteStride', struct.calcsize(fmt))
        start = v.get('byteOffset', 0) + a.get('byteOffset', 0)
        return [list(struct.unpack_from(fmt, data, start + i*stride)) for i in range(a['count'])]
    primitive = doc['meshes'][0]['primitives'][0]
    attributes = primitive['attributes']
    inv_bind = accessor(doc['skins'][0]['inverseBindMatrices'])
    node_ids = doc['skins'][0]['joints']
    def coordinate(p): return [-p[1], -p[2], p[0]]
    joint_positions = []
    for m in inv_bind:
        joint_positions.append(coordinate([-sum(m[r*4+k]*m[12+k] for k in range(3)) for r in range(3)]))
    wrist = joint_positions[0]
    def relative(p): return [round(a-b, 8) for a,b in zip(coordinate(p), wrist)]
    joints = []
    for index, node_id in enumerate(node_ids):
        node = doc['nodes'][node_id]
        parts = node['name'].split('_')
        if parts[0] in ('Wrist','Palm'):
            name,group='wrist',0
        else:
            prefix=PREFIXES[parts[0]]
            suffix=({'Metacarpal':'Knuckle','Proximal':'IntermediateBase','Distal':'IntermediateTip','Tip':'Tip'} if parts[0]=='Thumb' else {'Metacarpal':'Metacarpal','Proximal':'Knuckle','Intermediate':'IntermediateBase','Distal':'IntermediateTip','Tip':'Tip'})[parts[1]]
            name=prefix+suffix
            group=list(PREFIXES).index(parts[0])+1
        children=[node_ids.index(c) for c in node.get('children',[]) if c in node_ids]
        parent=next((i for i,n in enumerate(node_ids) if node_id in doc['nodes'][n].get('children',[])),None)
        joints.append({'name':name,'position':[round(a-b,8) for a,b in zip(joint_positions[index],wrist)],'child':children[0] if len(children)==1 else None,'parent':parent,'group':group})
    result={'version':1,'side':side.lower(),'source':filename,
            'positions':[relative(p) for p in accessor(attributes['POSITION'])],
            'normals':[[round(x,7) for x in coordinate(n)] for n in accessor(attributes['NORMAL'])],
            'uvs':[[round(u,7),round(1-v,7)] for u,v in accessor(attributes['TEXCOORD_0'])],
            'jointIndices':accessor(attributes['JOINTS_0']),
            'weights':[[round(w,7) for w in row] for row in accessor(attributes['WEIGHTS_0'])],
            'indices':[i[0] for i in accessor(primitive['indices'])], 'joints':joints}
    subdivide(result)
    (ROOT/'TRACE/HandAssets'/f'{side}Hand.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print(f'{side}: {len(result["positions"])} authored vertices; {len(result["indices"])//3} triangles; {len(joints)} skin joints')

for side in ('Left','Right'): convert(side)
