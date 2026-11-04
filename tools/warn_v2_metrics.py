"""docs/221 mask method, on frozen real frames; not a gameplay TRACE check."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'build/warn_v2'
def read(name):return np.asarray(Image.open(OUT/name).convert('RGB'),dtype=np.float32)/255
report={"threshold":0.06,"roi":[180,150,1100,560],"method":"docs/221: foe=nofriend minus nofriend,nofoe; recolored=intersection with full minus nofriend","limitations":"Same frozen game state; wall-clock shaders may still differ across rendered frames. Single snapshot, not a multi-scene readability claim."}
for v in [0,1]:
    full=read(f'warn_{v}_full.png')[150:560,180:1100]
    nf=read(f'warn_{v}_nofriend.png')[150:560,180:1100]
    nff=read(f'warn_{v}_nofriend_nofoe.png')[150:560,180:1100]
    foe=np.max(np.abs(nf-nff),axis=2)>.06
    friend=np.max(np.abs(full-nf),axis=2)>.06
    both=foe&friend
    report[str(v)]={"foe_pixels":int(foe.sum()),"friend_pixels":int(friend.sum()),"recolored_pixels":int(both.sum()),"foe_recolored_ratio":float(both.sum()/max(1,foe.sum())),"foe_coverage":float(foe.mean())}
    mask=(full*255).astype('uint8');mask[foe]=[50,200,255];mask[both]=[255,100,40]
    Image.fromarray(mask).save(OUT/f'warn_{v}_mask.png')
(OUT/'metrics.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
sheet=Image.new('RGB',(2560,760),'#14202c');draw=ImageDraw.Draw(sheet)
for v in [0,1]:
    sheet.paste(Image.open(OUT/f'warn_{v}_full.png').convert('RGB'),(1280*v,40))
    draw.text((1280*v+20,15),f'render/warn_v2 = {v}',fill='white')
sheet.save(OUT/'comparison.png')
