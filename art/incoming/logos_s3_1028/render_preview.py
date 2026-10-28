"""Offline sprite animation only: not a browser capture or gameplay video."""
from pathlib import Path
from PIL import Image,ImageDraw
import math,json
R=Path(__file__).resolve().parent
m=json.loads((R/'manifest.json').read_text());sheets={}
for a in m['assets']:
    im=Image.open(R/a['file']).convert('RGBA');w,h=a['frame_size'];key=a['file'].removeprefix('fx_logos_s3_').removesuffix('@2x.png')
    sheets[key]=[im.crop((i*w,0,(i+1)*w,h)) for i in range(a['frames'])]
actor=Image.open(R/'source/logos_idle_reference.png').convert('RGBA');orbit=Image.open(R/'source/orbit_reference.png').convert('RGBA')
frames=[]
for k in range(156):
    t=k/12
    if t<.5:key='fan_open';f=min(7,int(t*16))
    elif t<11.625:key='fan_ground';f=int((t-.5)*6)%4
    else:key='fan_close';f=min(5,int((t-11.625)*16))
    im=Image.new('RGB',(800,600),'#0d1420');d=ImageDraw.Draw(im)
    d.text((20,15),'LOGOS S3 / ART PREVIEW / NOT GAMEPLAY',fill='#a8afe0')
    d.text((20,35),f'{t:.2f}s  {key}  frame {f}',fill='#767ab7')
    if t<12:im.paste(sheets[key][f],(162,36),sheets[key][f])
    if t<12:
        fade=min(1,t/.5,max(0,(12-t)/.5))
        anchors=[(340*math.cos(math.radians(a)),340*math.sin(math.radians(a))) for a in range(-44,45,4)]
        anchors += [(radius*math.cos(math.radians(a)),radius*math.sin(math.radians(a))) for a in [-50,50] for radius in [64,96,128,160,192,224,256,288]]
        anchors += [(120,20),(180,-45),(235,55),(270,-80),(210,120)]
        for j,(dx,dy) in enumerate(anchors):
            ribbon=sheets['ribbon'][(int(t*8)+j*3)%8].copy()
            sw,sh=[(20,40),(24,56),(20,40),(28,64),(24,48)][j%5]
            # Resize on the logical grid, then restore exact 2x pixels.
            ribbon=ribbon.resize((sw//2,sh//2),Image.Resampling.NEAREST).resize((sw,sh),Image.Resampling.NEAREST)
            opacity=((.80 if j%2==0 else .36)+.09*math.sin(t*1.5+j*1.9))*fade
            if j>=39: opacity=(.12+.035*math.sin(t*.9+j*1.7))*fade
            ribbon.putalpha(ribbon.getchannel('A').point(lambda a:round(a*opacity)))
            x=170+round(dx);y=300+round(dy)-[0,10,3,13][j%4]+round(math.sin(t*1.3+j*2)*4)
            im.paste(ribbon,(x-sw//2,y-sh),ribbon)
    a=actor.crop((int(t*6)%8*128,0,(int(t*6)%8+1)*128,128)).resize((64,64),Image.Resampling.NEAREST);im.paste(a,(138,240),a)
    if t<12:
        o=orbit.crop((int(t*10)%6*96,0,(int(t*10)%6+1)*96,112));im.paste(o,(122,212),o)
    d.text((560,170),'SLOW MARK / 3x DETAIL',fill='#a8afe0')
    d.rectangle((644,293,658,307),fill='#df765f')
    s=sheets['slow'][int(t*12)%4].resize((144,144),Image.Resampling.NEAREST);im.paste(s,(580,228),s)
    frames.append(im)
frames[0].save(R/'preview/animation.gif',save_all=True,append_images=frames[1:],duration=[83,83,84]*52,loop=0,optimize=True)
frames[3].save(R/'preview/open_context.png');frames[15].save(R/'preview/hold_context.png');frames[142].save(R/'preview/close_context.png')
print('13-second offline sprite preview created')
