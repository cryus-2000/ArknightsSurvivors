"""Read-only visual evidence: approved f0 comparison and original part ownership."""
import json,pathlib,math
from PIL import Image,ImageDraw
P=pathlib.Path(__file__).resolve().parent
ROOT=P.parents[4]
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
manifests=sorted(P.glob('*/manifest.json'))
for batch in range(math.ceil(len(manifests)/8)):
    sheet=Image.new('RGB',(1000,240*4),(23,30,38));d=ImageDraw.Draw(sheet)
    for k,mp in enumerate(manifests[batch*8:batch*8+8]):
        m=read(mp);ident=m['id'];w,h=m['frame_size'];x=(k%2)*500;y=(k//2)*240
        d.text((x+8,y+6),ident+' | approved f0 / native animation idle',fill='white')
        old=Image.open(P.parent/'remaining/f0'/('e_'+ident+'_idle_f0@2x.png')).convert('RGBA')
        body=Image.open(mp.parent/('e_'+ident+'_idle@2x.png')).convert('RGBA').crop((0,0,w*2,h*2))
        emit=Image.open(mp.parent/('e_'+ident+'_idle_emit@2x.png')).convert('RGBA').crop((0,0,w*2,h*2));body.alpha_composite(emit)
        for dx,im in [(0,old),(250,body)]:
            box=im.getbbox();im=im.crop(box)
            sheet.paste(im,(x+dx+120-im.width//2,y+225-im.height),im)
    sheet.save(P/f'lineup_{batch+1}.png')
for batch in range(math.ceil(len(manifests)/8)):
    sheet=Image.new('RGB',(1600,240*4),(23,30,38));d=ImageDraw.Draw(sheet)
    for k,mp in enumerate(manifests[batch*8:batch*8+8]):
        m=read(mp);ident=m['id'];w,h=m['frame_size'];x=(k%2)*800;y=(k//2)*240
        d.text((x+8,y+6),ident+' | idle / wound',fill='white')
        for z,act in enumerate(('idle','wound')):
            body=Image.open(mp.parent/f'e_{ident}_{act}@2x.png').convert('RGBA').crop((0,0,w*2,h*2))
            light=Image.open(mp.parent/f'e_{ident}_{act}_emit@2x.png').convert('RGBA').crop((0,0,w*2,h*2));body.alpha_composite(light)
            # Shared physical origin; do not independently align by each pose bbox.
            sheet.paste(body,(x+z*400+200-int(m['origin'][0]*2),y+225-int(m['origin'][1]*2)),body)
    sheet.save(P/f'wound_compare_{batch+1}.png')
for mp in manifests:
    m=read(mp);ident=m['id'];w,h=m['frame_size'];base=mp.parent
    raw=ROOT/'build/enemy_actions_1023'/ident;cat=read(raw/'catalog.json');ref=next(f for f in cat['frames'] if f['name']=='idle_00')
    rows=read(base/'idle_parts.json')[0]['parts']
    side=Image.new('RGB',(w*6,max(1,len(rows))*h*2),(23,30,38))
    no_equipment=Image.new('RGBA',(w,h));without_front=Image.new('RGBA',(w,h));full=Image.new('RGBA',(w,h))
    for i,row in enumerate(rows):
        source=Image.open(raw/ref['parts'][i]['file']).convert('RGBA')
        source=source.resize((source.width//4,source.height//4),Image.Resampling.NEAREST).crop(m['source_crop_1x']).resize((w*2,h*2),Image.Resampling.NEAREST)
        part=Image.open(base/row['pixel_component']).convert('RGBA').crop((0,0,w,h))
        pixel=part.resize((w*2,h*2),Image.Resampling.NEAREST)
        side.paste(source,(0,i*h*2),source);side.paste(pixel,(w*2,i*h*2),pixel)
        ImageDraw.Draw(side).text((w*4+2,i*h*2+3),row['slot'],fill='white')
        full.alpha_composite(part)
        if not any(s in row['slot'].lower() for s in ('weapon','gun','sword','spear')):no_equipment.alpha_composite(part)
        if i<len(rows)-1:without_front.alpha_composite(part)
    side.save(base/'attachment_comparison.png')
    comp=Image.new('RGB',(w*6,h*2+20),(23,30,38));ImageDraw.Draw(comp).text((2,2),'full / no equipment / last slot hidden',fill='white')
    for i,im in enumerate((full,no_equipment,without_front)):
        im=im.resize((w*2,h*2),Image.Resampling.NEAREST);comp.paste(im,(i*w*2,20),im)
    comp.save(base/'occlusion_check.png')
print('Wrote',len(manifests),'attachment/occlusion comparisons and f0 lineups')
