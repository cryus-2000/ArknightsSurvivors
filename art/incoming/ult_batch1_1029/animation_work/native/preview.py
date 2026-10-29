from pathlib import Path
from PIL import Image, ImageDraw
import json

R=Path(__file__).resolve().parent
B=R.parent.parent
entries=json.loads((R/'entries.json').read_text(encoding='utf-8'))
front=Image.open(B/entries[0]['file']).convert('RGBA')
back=Image.open(B/entries[1]['file']).convert('RGBA')
mapping=entries[0]['front_to_back_frame_mapping']
out=Image.new('RGB',(1200,600),'#1c2733');d=ImageDraw.Draw(out)
for i in range(10):
    plate=Image.new('RGBA',(400,400))
    plate.alpha_composite(back.crop((mapping[i]*320,0,(mapping[i]+1)*320,96)),(40,302))
    plate.alpha_composite(front.crop((i*320,0,(i+1)*320,320)),(40,34))
    plate=plate.resize((240,240),Image.Resampling.NEAREST)
    x=(i%5)*240;y=(i//5)*300
    d.text((x+4,y+5),f'f{i} / back {mapping[i]} / shared foot',fill='white')
    out.paste(plate,(x,y+32),plate)
out.save(R/'contact/seaborn_combined.png')
cards=[]
for e in entries:
    im=Image.open(R/'contact'/(e['name']+'.png'))
    im.thumbnail((1200,500),Image.Resampling.NEAREST)
    cards.append((e['name'],im.copy()))
height=sum(im.height+35 for _,im in cards)
sheet=Image.new('RGB',(1240,height),'#18232e');dr=ImageDraw.Draw(sheet);y=0
for name,im in cards:
    dr.text((10,y+3),name,fill='white');sheet.paste(im,(10,y+28));y+=im.height+35
sheet.save(R/'native_animation_overview.png')
print('native contact overview and layered seaborn preview written')
