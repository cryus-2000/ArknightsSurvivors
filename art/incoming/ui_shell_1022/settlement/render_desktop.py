"""Desktop victory review candidate only. Native UI + approved 128px f0 assets.
No AI images or game edits. Includes original decorative asset candidates.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops
import json, hashlib
import draw_ornaments

P=Path(__file__).resolve().parent
ROOT=next(p for p in P.parents if (p/'game/fonts/ui.ttf').exists())
W,H=1280,720
# hh_style.gd constants, retained exactly.
C={'DARK':(19,23,30),'DARK2':(27,32,41),'DARK3':(36,42,53),
   'LIGHT':(223,226,230),'LIGHT2':(206,210,215),'INK':(17,19,24),
   'INK2':(92,97,106),'MUTE':(150,156,166),'YEL':(255,206,0),
   'CYB':(56,214,240),'RIB':(24,120,214),'SIL':(118,123,132)}
WHITE=(244,246,246); PURPLE=(188,151,255); GREEN=(47,211,160)
F={}; placements=[]; text_boxes=[]
def font(size,en=False):
    k=(size,en)
    if k not in F:F[k]=ImageFont.truetype('C:/Windows/Fonts/bahnschrift.ttf' if en else str(ROOT/'game/fonts/ui.ttf'),size)
    return F[k]
im=Image.new('RGBA',(W,H),C['DARK']); d=ImageDraw.Draw(im); d.fontmode='1'
def rect(box,c):d.rectangle(box,fill=c)
def line(points,c,width=1):d.line(points,fill=c,width=width)
def poly(points,c,outline=None):d.polygon(points,fill=c,outline=outline)
def txt(x,y,s,size=18,c=WHITE,en=False):
    f=font(size,en); box=d.textbbox((x,y),s,font=f,anchor='lt')
    assert box[0]>=0 and box[1]>=0 and box[2]<=W and box[3]<=H,(s,box)
    text_boxes.append({'text':s,'bbox':list(box),'size':size})
    d.text((x,y),s,font=f,fill=c,anchor='lt')
def right(x,y,s,size=18,c=WHITE,en=False):
    txt(int(x-d.textlength(s,font=font(size,en))),y,s,size,c,en)
def outlined(x,y,s,size,c,bg):
    d.text((x,y),s,font=font(size,True),fill=bg,stroke_width=1,stroke_fill=c,anchor='lt')
def corner(x,y,w,h,c):
    for a,b in [([(x+10,y),(x,y),(x,y+10)],0), ([(x+w-10,y),(x+w,y),(x+w,y+10)],0),
                ([(x,y+h-10),(x,y+h),(x+10,y+h)],0), ([(x+w-10,y+h),(x+w,y+h),(x+w,y+h-10)],0)]:line(a,c,2)
def arrow(x,y,c):line([(x,y),(x+7,y+7),(x,y+14)],c,2)
def stipple(x,y,w,h,c):
    # Intentional repeating 2px halftone patch, not random grain or single-pixel noise.
    for yy in range(y,y+h,6):
        for xx in range(x,x+w,6):
            if (xx-x)//6+(yy-y)//6<w//6:rect((xx,yy,xx+1,yy+1),c)

def ornament(name,xy,clip=None,opacity=1):
    global d
    layer=Image.new('RGBA',(W,H))
    asset=Image.open(P/'decor'/name).convert('RGBA')
    if opacity!=1:asset.putalpha(asset.getchannel('A').point(lambda a:round(a*opacity)))
    layer.alpha_composite(asset,xy)
    if clip:
        mask=Image.new('L',(W,H));ImageDraw.Draw(mask).polygon(clip,fill=255)
        layer.putalpha(ImageChops.multiply(layer.getchannel('A'),mask))
    im.alpha_composite(layer)
    d=ImageDraw.Draw(im);d.fontmode='1'

# Full-width graphic framing, restrained diagonal planes behind cards.
poly([(1068,44),(1184,44),(1044,648),(928,648)],(23,28,36))
poly([(726,44),(754,44),(614,648),(586,648)],(23,28,36))
ornament('topography_sparse@2x.png',(0,0))
rect((0,0,1279,43),C['INK'])
rect((28,14,31,30),C['CYB'])
txt(44,13,'作战结算',18,C['LIGHT'])
txt(150,18,'OPERATION / REPORT',10,C['MUTE'],True)
right(1250,16,'方舟幸存者',15,C['LIGHT'])
line([(0,44),(1279,44)],(48,55,66))

# Result band: light left editorial block, dark reward block, reserved rating.
poly([(0,46),(736,46),(700,207),(0,207)],C['LIGHT2'])
poly([(0,46),(716,46),(680,207),(0,207)],C['LIGHT'])
ornament('navigation_watermark@2x.png',(426,-94),[(0,46),(716,46),(680,207),(0,207)],.33)
# Paired editorial rules are aligned with the result text, without framing it in another box.
txt(32,64,'01 / RESULT',10,C['INK2'],True)
txt(29,85,'探索完成',56,C['INK'])
outlined(33,147,'OPERATION COMPLETE',23,C['INK2'],C['LIGHT'])
txt(33,183,'结局一 · 平凡即是喜乐',13,C['INK2'])
txt(382,158,'探索用时',12,C['INK2']);txt(382,178,'10:24',21,C['INK'],True)
txt(518,158,'难度档',12,C['INK2']);txt(518,180,'困难',18,C['INK'])
txt(582,184,'潮位 VIII',11,C['INK2'])
txt(754,80,'本局获得',14,C['MUTE'])
txt(754,116,'生机细胞',13,C['MUTE']);txt(754,140,'+28',32,WHITE,True)
txt(944,116,'寻访凭证',13,C['MUTE']);txt(944,140,'×4',32,C['CYB'],True)
line([(754,188),(786,188)],C['MUTE'],2)
line([(944,188),(976,188)],C['CYB'],2)
corner(1148,76,100,116,(66,74,85))
txt(1171,86,'RATING',10,C['MUTE'],True)
txt(1163,107,'SS',51,WHITE,True)
rect((1180,162,1216,164),C['CYB'])
txt(1174,174,'探索完成',12,C['LIGHT'])

# Team header; aggregate statistics retain the old record's typography.
txt(32,232,'本局编队',20);txt(140,239,'SQUAD / 04',10,C['MUTE'],True)
txt(440,237,'总伤害',12,C['MUTE']);txt(500,231,'1,284,620',25,WHITE,True)
txt(720,237,'击败敌人',12,C['MUTE']);txt(792,231,'1,284',25,WHITE,True)
line([(32,269),(906,269)],(53,61,72))

team=[
 ('mizuki','水月','特种','SPECIALIST',720250,56.1,719,916,42,PURPLE),
 ('skadi','斯卡蒂','近卫','GUARD',372180,29.0,372,640,28,(94,137,232)),
 ('lumen','流明','医疗','MEDIC',77420,6.0,77,488,36,(143,217,248)),
 ('exusiai','能天使','狙击','SNIPER',114770,8.9,116,312,22,(191,95,118))]
for idx,(op,name,role,en,damage,share,kills,participation,casts,color) in enumerate(team):
    x=28+idx*224; light=idx==0
    bg=C['LIGHT'] if light else C['DARK2']; fg=WHITE
    muted=C['MUTE']; border=(57,65,78)
    # The portrait is a card; data uses an open shared baseline.
    silhouette=[(x+16,288),(x+210,288),(x+194,459),(x,459)]
    poly(silhouette,bg)
    ornament('portrait_calibration@2x.png',(x+10,300),silhouette,.65 if light else .25)
    poly([(x+16,288),(x+56,288),(x+56,291),(x+16,291)],color)
    txt(x+25,300,f'0{idx+1}',10,C['INK2'] if light else muted,True)
    if light:
        txt(x+155,482,'队长',12,PURPLE)
    else:txt(x+151,300,role,12,muted)
    # Every source is the task's approved am_latest18 f0; no regeneration.
    source=P/'source'/f'{op}_f0.png'; s=Image.open(source).convert('RGBA')
    assert s.size==(128,128)
    bb=s.getbbox();cut=s.crop(bb);scale=2
    cut=cut.resize((cut.width*scale,cut.height*scale),Image.Resampling.NEAREST)
    cx=x+110;foot=451;pos=(cx-cut.width//2,foot-cut.height)
    assert pos[0]>=x and pos[0]+cut.width<=x+212 and pos[1]>=295,(op,pos,cut.size)
    im.alpha_composite(cut,pos)
    placements.append({'id':op,'file':str(source.relative_to(P)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                       'source_bbox':list(bb),'display_bbox':[pos[0],pos[1],pos[0]+cut.width,foot],'scale':scale})
    d=ImageDraw.Draw(im);d.fontmode='1'
    txt(x+8,474,name,26,fg)
    txt(x+8,513,'伤害占比',12,muted)
    right(x+194,506,f'{share:.1f}%',26,fg,True)
    rect((x+8,539,x+194,543),(42,49,61))
    rect((x+8,539,x+8+round(186*share/100),543),color)
    txt(x+8,559,'击杀',13,muted);right(x+194,553,str(kills),25,fg,True)
    txt(x+8,594,'参与击杀',11,muted);txt(x+8,612,str(participation),17,C['LIGHT'],True)
    txt(x+150,594,'技能次数',11,muted);right(x+194,612,str(casts),17,C['LIGHT'],True)

# Minute-calibrated timeline: actual time position, labels offset independently.
txt(962,235,'关键事件',16,C['MUTE'])
line([(962,269),(1248,269)],(53,61,72))
x_axis=995;y0=304;y1=608;seconds=624
line([(x_axis,y0),(x_axis,y1)],(63,72,86))
for minute in range(11):
    y=round(y0+(y1-y0)*minute*60/seconds)
    line([(x_axis-3,y),(x_axis+3,y)],(63,72,86))
    if minute%2==0:right(981,y-4,f'{minute:02d}',9,(115,124,138),True)
events=[(0,'00:00','探索开始',C['MUTE']), (216,'03:36','中期 Boss 击破',C['MUTE']),
        (432,'07:12','中期 Boss 击破',C['MUTE']), (624,'10:24','终局 Boss 击破',C['CYB'])]
for sec,when,label,col in events:
    y=round(y0+(y1-y0)*sec/seconds)
    poly([(x_axis,y-5),(x_axis+5,y),(x_axis,y+5),(x_axis-5,y)],col)
    yy=y-23 if sec==624 else y-9
    txt(1014,yy,when,12,col,True)
    txt(1014,yy+21,label,14,col)

# Only the three requested final actions; no tabs hiding the body details.
rect((0,652,1279,719),C['INK']);line([(28,652),(1252,652)],(53,61,72))
txt(28,678,'探索已归档',15,C['MUTE'])
def button(x,w,label,key,primary=False):
    bg=C['CYB'] if primary else C['DARK2']; fg=C['INK'] if primary else C['LIGHT']
    poly([(x+8,666),(x+w,666),(x+w-8,706),(x,706)],bg,None if primary else (66,74,85))
    txt(x+24,677,label,20,fg)
    if key:right(x+w-(42 if primary else 25),682,key,12,fg,True)
button(374,250,'返回主界面','Esc')
button(642,250,'认知塑造','')
button(910,342,'寻访  ×4','Enter',True);arrow(1227,679,C['INK'])
im.convert('RGB').save(P/'settlement_desktop.png')
manifest={'stage':'desktop-victory-handoff','approved':True,'canvas':[W,H],'runtime_changes':False,
 'rating_sample':{'grade':'SS','difficulty':'困难','completed':True,'rule_approved':True,'engine_integrated':False},
 'revision':'06-rating-handoff','decorative_assets':[{'file':str(f.relative_to(P)),'size':list(Image.open(f).size),'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'pixel_grid':2} for f in sorted((P/'decor').glob('*.png'))],
 'image_generation_used':False,'sample_values':True,'palette_source':'game/scripts/screens/hh_style.gd',
 'palette':C,'fonts':{'chinese':'game/fonts/ui.ttf','latin':'Windows Bahnschrift','raster':'binary glyph mask'},
 'placements':placements,'team_sample':[{ 'id':r[0], 'damage':r[4],'share':r[5],'kills':r[6],'participation':r[7],'casts':r[8]} for r in team],
 'sha256':hashlib.sha256((P/'settlement_desktop.png').read_bytes()).hexdigest()}
(P/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(P/'layout_text_bounds.json').write_text(json.dumps(text_boxes,ensure_ascii=False,indent=2),encoding='utf-8')
# This is a single-image review page, not a working settings or results screen.
(P/'review.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>作战结算 · 桌面胜利态</title><style>body{margin:0;background:#0e1116;color:#dfe2e6;font:14px system-ui}header{padding:14px 20px;display:flex;gap:22px}span{color:#969ca6}main{display:flex;justify-content:center}img{width:min(1280px,100%);height:auto;image-rendering:pixelated}a{color:#38d6f0}</style><header><b>作战结算 · 桌面胜利态</b><span>视觉候选 · 数值为样例 · 尚未接入游戏</span><a href="settlement_desktop.png" target="_blank">1280×720 原图</a></header><main><img src="settlement_desktop.png" alt="作战结算整屏候选"></main></html>''',encoding='utf-8')
print(json.dumps({'rendered':str(P/'settlement_desktop.png'),'size':[W,H],'source_sprites':len(placements),'text_count':len(text_boxes)}))
