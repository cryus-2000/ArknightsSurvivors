"""Apply the exporter visibility rule to cached strips without re-rendering bones."""
import hashlib,json,pathlib
from PIL import Image
P=pathlib.Path(__file__).resolve().parent
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
changed=0
for mp in P.glob('*/manifest.json'):
    m=read(mp);w,h=m['frame_size'];binding=m.get('glow_binding') or {};dirty=False
    for a in m['actions']:
        path=mp.parent/(a['action']+'_parts.json');frames=read(path);meta_changed=False
        stem='e_'+m['id']+'_'+a['action'];ep=mp.parent/(stem+'_emit.png');emit=Image.open(ep).convert('RGBA');before=emit.tobytes()
        for i,f in enumerate(frames):
            active=bool(binding.get('component'))
            for part in f['parts']:
                if part['slot']==binding.get('slot'):
                    im=Image.open(mp.parent/part['pixel_component']).convert('RGBA').crop((i*w,0,(i+1)*w,h))
                    if im.getbbox():active=True
            if f.get('glow_active')!=active:f['glow_active']=active;meta_changed=True
            if not active:emit.paste((0,0,0,0),(i*w,0,(i+1)*w,h))
        if emit.tobytes()!=before:
            emit.save(ep);emit.resize((emit.width*2,emit.height*2),Image.Resampling.NEAREST).save(mp.parent/(stem+'_emit@2x.png'));changed+=1;dirty=True
        if meta_changed:write(path,frames)
    if dirty:
        for a in m['assets']:a['sha256']=hashlib.sha256((P/a['file']).read_bytes()).hexdigest()
        write(mp,m)
print('Emission strips corrected:',changed)
