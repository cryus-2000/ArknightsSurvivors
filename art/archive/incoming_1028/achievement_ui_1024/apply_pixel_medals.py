"""Replace only SVG medal artwork; preserve all layout coordinates and IDs."""
from pathlib import Path
import json, math
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
def tag(name): return '{'+NS+'}'+name
layout=json.loads((ROOT/'packed_layout_v16.json').read_text(encoding='utf-8'))
medals=json.loads((ROOT/'achievement_set.json').read_text(encoding='utf-8'))['medals']
cells={1:0,2:1,3:2,4:3,5:4,7:5,8:6,10:7,11:8}
by_name={m['name']:m['id'] for m in medals}
by_id={m['id']:m for m in layout['medals']}
tree=ET.parse(ROOT/'packed_layout_v16.svg')
count=0
for group in list(tree.getroot()):
    title=group.find(tag('title'))
    if title is None: continue
    key=by_name[title.text];r=by_id[key]['radius'];cell=cells[key]
    # Source atlas uses a fixed grid; the viewport keeps cells independent.
    sx=209+418*(cell%3);sy=209+418*(cell//3);sr=200
    points=' '.join(f'{r*math.cos(math.radians(-90+60*i)):.3f},{r*math.sin(math.radians(-90+60*i)):.3f}' for i in range(6))
    for child in list(group):
        if child is not title:group.remove(child)
    defs=ET.SubElement(group,tag('defs'))
    clip=ET.SubElement(defs,tag('clipPath'),{'id':f'pixelclip{key}'})
    ET.SubElement(clip,tag('polygon'),{'points':points})
    body=ET.SubElement(group,tag('g'),{'clip-path':f'url(#pixelclip{key})'})
    viewport=ET.SubElement(body,tag('svg'),{'x':str(-r),'y':str(-r),'width':str(2*r),'height':str(2*r),'viewBox':f'{sx-sr} {sy-sr} {2*sr} {2*sr}'})
    ET.SubElement(viewport,tag('image'),{'href':'medals_silver_clean_1025.png','width':'1254','height':'1254','style':'image-rendering:pixelated'})
    ET.SubElement(group,tag('polygon'),{'points':points,'fill':'transparent','stroke':'transparent','stroke-width':'1'})
    count+=1
assert count==9
tree.write(ROOT/'packed_layout_v16.svg',encoding='unicode')
print('Replaced 9 medal faces; transforms and layout JSON unchanged.')
