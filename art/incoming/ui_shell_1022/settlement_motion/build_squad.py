from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
P=Path(__file__).resolve().parent
root=next(p for p in P.parents if (p/'game/fonts/ui.ttf').exists())
base=Image.open(P.parent/'settlement/settlement_desktop.png').convert('RGBA')
atlas=Image.new('RGBA',(224*7,350),(19,23,30))
for i in range(4): atlas.paste(base.crop((28+i*224,288,252+i*224,638)),(i*224,0))
for i,(op,name,role,left) in enumerate([('saria','塞雷娅','重装',True),('kaltsit','凯尔希','医疗',False),('texas','德克萨斯','先锋',True)],4):
    card=Image.new('RGBA',(224,350),(19,23,30));d=ImageDraw.Draw(card);d.fontmode='1'
    d.polygon([(16,0),(210,0),(194,171),(0,171)],fill=(27,32,41))
    def text(x,y,s,n=13,col=(150,156,166)):
        d.text((x,y),s,font=ImageFont.truetype(('C:/Windows/Fonts/msyh.ttc' if '娅' in s else str(root/'game/fonts/ui.ttf')),n),fill=col,anchor='lt')
    text(25,12,f'{i+1:02}');text(151,12,role)
    sheet=Image.open(root/'art/incoming'/f'op_{op}_idle@2x.png').convert('RGBA')
    sprite=sheet.crop((0,0,sheet.height,sheet.height));sprite=sprite.crop(sprite.getbbox())
    # Retain the source pixel grid; fit using integer base-pixel scale.
    scale=max(.5,int(min(196/sprite.width,146/sprite.height)*2)/2)
    sprite=sprite.resize((round(sprite.width*scale),round(sprite.height*scale)),Image.Resampling.NEAREST)
    card.alpha_composite(sprite,(110-sprite.width//2,163-sprite.height))
    text(8,186,name,26,(244,246,246));text(145,186,'已离队' if left else '在队',11)
    text(8,225,'伤害占比',12);text(145,218,'0.0%',20,(244,246,246))
    d.rectangle((8,251,194,255),fill=(42,49,61))
    text(8,271,'击杀');text(180,271,'0',20)
    text(8,306,'参与击杀',11);text(8,324,'0',17);text(150,306,'技能次数',11);text(180,324,'0',17)
    atlas.paste(card,(i*224,0))
atlas.save(P/'squad_cards.png')
