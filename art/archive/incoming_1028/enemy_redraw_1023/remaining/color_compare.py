"""Read-only reference / previous export / corrected export contact sheet."""
from pathlib import Path
from io import BytesIO
import json,subprocess
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parent;W=R.parents[4]
ids=['skimmer','archon','bishop','founder','ishar','path','fractal','immortal','paranoia','paranoia_phase2']
jobs={j['id']:j for j in json.loads((R/'job.json').read_text('utf8'))['jobs']}
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',n)
out=Image.new('RGB',(1200,80+230*len(ids)),'#14222e');d=ImageDraw.Draw(out)
for x,t in [(30,'原作参考'),(440,'上一稿（b1b14f02）'),(840,'本次修正')]:d.text((x,20),t,font=font(21),fill='#d5e0e6')
for row,k in enumerate(ids):
 j=jobs[k];p=R/'f0'/f'e_{k}_idle_f0.png';y=80+row*230
 original=Image.open(W/j['reference']).convert('RGBA')
 previous=Image.open(BytesIO(subprocess.check_output(['git','show','b1b14f02:'+p.relative_to(W).as_posix()],cwd=W))).convert('RGBA')
 current=Image.open(p).convert('RGBA')
 d.text((16,y),j['name']+' / '+k,font=font(16),fill='#c5d8df')
 for col,im in enumerate([original,previous,current]):
  im=im.crop(im.getbbox())
  if col==0: im.thumbnail((320,180))
  else:
   scale=max(1,min(4,320//im.width,180//im.height));im=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
  out.paste(im,(col*400+(400-im.width)//2,y+220-im.height),im)
 d.line((0,y+229,1200,y+229),fill='#354650')
out.save(R/'color_comparison.png')
