"""1280x720 design review sheets only; no runtime UI or settings changes."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, hashlib

P=Path(__file__).resolve().parent
ROOT=next(p for p in P.parents if (p/'game/fonts/ui.ttf').exists())
BG='#13171e'; INK='#111318'; WHITE='#dfe2e6'; MUTE='#969ca6'
CYAN='#38d6f0'; YELLOW='#ffce00'; RED='#ef727d'; LINE='#39414e'
def font(n,en=False):
    return ImageFont.truetype('C:/Windows/Fonts/bahnschrift.ttf' if en else str(ROOT/'game/fonts/ui.ttf'),n)
def start():
    global im,d,boxes
    im=Image.new('RGB',(1280,720),BG);d=ImageDraw.Draw(im);d.fontmode='1';boxes=[]
def rect(b,c):d.rectangle(b,fill=c)
def poly(p,c):d.polygon(p,fill=c)
def line(p,c=LINE,w=1):d.line(p,fill=c,width=w)
def text(x,y,s,n=18,c=WHITE,en=False):
    b=d.textbbox((x,y),s,font=font(n,en),anchor='lt')
    assert 0<=b[0]<b[2]<=1280 and 0<=b[1]<b[3]<=720,(s,b)
    boxes.append({'text':s,'bbox':b})
    d.text((x,y),s,font=font(n,en),fill=c,anchor='lt')
def outline(x,y,s,n,c=LINE):
    d.text((x,y),s,font=font(n,True),fill=BG,stroke_width=1,stroke_fill=c,anchor='lt')
def dots(x,y,w,h,c):
    for yy in range(y,y+h,6):
        for xx in range(x,x+w,6):rect((xx,yy,xx+1,yy+1),c)
def corners(x,y,w,h,c=LINE):
    for p in [[(x+12,y),(x,y),(x,y+12)],[(x+w-12,y),(x+w,y),(x+w,y+12)],[(x,y+h-12),(x,y+h),(x+12,y+h)],[(x+w-12,y+h),(x+w,y+h),(x+w,y+h-12)]]:line(p,c,2)
def top(label,en):
    rect((0,0,1279,47),INK);line([(28,46),(1252,46)])
    line([(39,16),(31,24),(39,32)],WHITE,2)
    text(63,15,label,18);text(210,20,en,10,MUTE,True)
    text(1140,17,'返回  Esc',15)
def footer():
    rect((0,654,1279,719),INK);line([(28,654),(1252,654)])
def save(name,meta):
    dest=P/name;dest.mkdir(exist_ok=True)
    image=dest/f'{name}_desktop.png';im.save(image)
    meta.update(canvas=[1280,720],stage='desktop-design-review',visual_approval=False,runtime_changes=False,image_generation_used=False,sha256=hashlib.sha256(image.read_bytes()).hexdigest())
    (dest/'manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
    (dest/'layout_text_bounds.json').write_text(json.dumps(boxes,ensure_ascii=False,indent=2),encoding='utf-8')
    (dest/'review.html').write_text(f'<!doctype html><meta charset="utf-8"><title>{name}</title><style>body{{margin:0;background:#111318;display:grid;place-items:center;min-height:100vh}}img{{max-width:100%;image-rendering:pixelated}}</style><img src="{name}_desktop.png">',encoding='utf-8')
    print(str(image))

# Difficulty: a projected central selection instead of three equal cards.
start();top('选择难度','OPERATION / DIFFICULTY')
poly([(0,48),(330,48),(286,174),(0,174)],WHITE)
text(30,71,'探索条件',36,INK);text(32,124,'SELECT / 03',13,'#5c616a',True)
outline(360,76,'DIFFICULTY',55,'#303a48')
text(965,86,'行动档案',23);text(966,121,'PERSONAL RECORD',11,MUTE,True)
line([(934,76),(934,622)],LINE)
# A slim scale ties the three tiers into one system.
line([(52,211),(52,589)],'#566172',2)
for yy in range(211,590,14):line([(46,yy),(52,yy)],'#566172')
# Standard, reduced behind selection.
poly([(82,199),(886,199),(864,304),(70,304)],'#1d2630')
rect((82,200,85,249),CYAN)
text(106,211,'01',69,'#7d9ca7',True)
text(226,219,'标准',28);text(229,259,'STANDARD',11,MUTE,True)
text(435,225,'没有额外规则。',17,MUTE)
text(730,218,'×1.00',27,MUTE,True);text(734,260,'结算系数',11,MUTE)
# Deep offset backing, selected white plate and yellow side edge.
poly([(91,333),(914,333),(888,504),(64,504)],'#080c12')
poly([(76,318),(908,318),(884,489),(52,489)],YELLOW)
poly([(76,318),(887,318),(864,489),(52,489)],WHITE)
poly([(82,318),(228,318),(202,489),(52,489)],'#ced2d7')
text(89,335,'02',112,INK,True)
poly([(28,384),(42,394),(28,404)],YELLOW)
text(243,338,'困难',43,INK);text(247,392,'HARD',13,'#5c616a',True)
text(440,342,'敌人强化 · 补给受限',20,INK)
text(440,384,'敌人生命与伤害 +20%',17,'#5c616a')
text(440,415,'队长初始最大生命 −10%',17,'#5c616a')
line([(720,341),(720,459)],'#a9afb8')
text(750,344,'×1.25',30,INK,True);text(754,390,'结算系数',12,'#5c616a')
rect((744,429,838,457),INK);text(757,436,'已选择',16,YELLOW)
rect((247,458,315,461),YELLOW)
# Locked tier: clipped diagonal hatch in a discrete region, not text overlay.
poly([(82,515),(886,515),(864,620),(70,620)],'#211e26')
rect((82,516,85,563),RED)
text(106,527,'03',69,'#78616a',True)
text(226,536,'极限',28,'#a8a0aa');text(229,577,'EXTREME',11,'#817b87',True)
text(435,539,'通关「困难」后解锁',17,'#aca2ad')
text(436,579,'LOCKED',11,RED,True)
for xx in range(716,835,14):line([(xx,602),(xx+32,532)],'#40313a',2)
rect((764,550,788,571),'#85757e');line([(769,550),(769,540),(783,540),(783,550)],'#85757e',3)
# The right area stays calm; records are explicitly sample data.
text(966,191,'02',16,YELLOW,True);text(1006,188,'困难',27)
text(966,240,'本档最佳',14,MUTE);line([(966,270),(1245,270)])
text(966,296,'通关次数',14,MUTE);text(963,324,'03',65,WHITE,True);text(1065,366,'次',15,MUTE)
line([(966,410),(1245,410)])
text(966,439,'最长存活',14,MUTE);text(962,471,'10:24',52,WHITE,True)
text(966,567,'通关评级',14,MUTE);text(1164,553,'SS',35,YELLOW,True)
line([(966,610),(1245,610)])
footer();text(32,680,'↑ ↓  选择档位',15,MUTE);text(337,678,'认知塑造',19)
poly([(917,668),(1252,668),(1244,708),(909,708)],CYAN)
text(935,677,'确认难度',22,INK);text(1160,683,'Enter',12,INK,True)
line([(1225,679),(1233,687),(1225,695)],INK,2)
save('difficulty',{'selected':'困难','locked':'极限','sample_values':True,'record_sample':{'clears':3,'longest':'10:24'},'data_sources':['game/scripts/data.gd DIFF_PRESETS','Cfg.diff_best'],'design':'oversized selected band, compressed neighbours, tier accents, separate record column'})

# Settings: fixed index and restrained equipment-style controls.
start();top('设置','SYSTEM / CONFIGURATION')
poly([(0,48),(364,48),(304,651),(0,651)],WHITE)
text(30,80,'系统设置',39,INK);text(32,136,'CONFIGURATION',15,'#5c616a',True)
line([(32,179),(306,179)],'#aeb4bc')
tabs=[('画面','DISPLAY'),('声音','SOUND'),('操作','CONTROLS'),('存档','SAVE DATA')]
for i,(cn,en) in enumerate(tabs):
    y=217+i*86
    if i==0:
        poly([(19,y-14),(335,y-14),(325,y+51),(19,y+51)],INK)
        rect((19,y-14,23,y+51),CYAN)
    c=WHITE if i==0 else '#5c616a'
    text(40,y+3,f'0{i+1}',14,CYAN if i==0 else '#7c828b',True)
    text(91,y,cn,28,c);text(92,y+35,en,10,CYAN if i==0 else '#7c828b',True)

text(32,597,'RHODES ISLAND',12,'#5c616a',True)
text(32,621,'SYSTEM INTERFACE / 04',10,'#7c828b',True)
# Quiet technical linework, no generic cog wallpaper.
outline(890,76,'DISPLAY',54,'#27313d')
text(392,87,'画面',32);text(394,134,'DISPLAY SETTINGS',11,MUTE,True)
line([(392,177),(1242,177)])
corners(376,192,878,435,'#35404d')
def row(y,label,en,selected=False):
    if selected:
        rect((389,y-13,1238,y+48),'#24323e');rect((389,y-13,392,y+48),CYAN)
    text(412,y,label,21);text(413,y+29,en,10,MUTE,True)
    line([(413,y+59),(1219,y+59)],'#2e3743')
def arrow(x,y,left=False):
    step=-6 if left else 6;line([(x,y),(x+step,y+6),(x,y+12)],MUTE,2)
row(216,'画质','QUALITY',True)
for x,s,on in [(1000,'低',False),(1114,'高',True)]:
    rect((x,213,x+91,250),CYAN if on else '#131b24');text(x+34,221,s,20,INK if on else MUTE)
row(292,'全屏','FULLSCREEN')
text(1063,302,'关闭',16,MUTE);rect((1129,294,1206,326),'#303b48');rect((1135,298,1158,322),MUTE)
row(368,'窗口分辨率','RESOLUTION')
arrow(922,376,True);text(945,370,'1280 × 720',23,WHITE,True);arrow(1195,376)
row(444,'界面大小','UI SIZE')
for j in range(20):rect((814+j*16,452,824+j*16,459),CYAN if j<10 else '#3b4551')
rect((965,446,973,465),WHITE);text(1140,443,'100%',24,WHITE,True)
row(520,'战斗画面缩放','BATTLE ZOOM')
for j in range(20):rect((814+j*16,528,824+j*16,535),CYAN if j<7 else '#3b4551')
rect((915,522,923,541),WHITE);text(1140,519,'100%',24,WHITE,True)
text(412,600,'滚动查看更多画面选项',13,MUTE)
rect((1243,211,1246,593),'#343e4b');rect((1243,211,1246,355),CYAN)
footer();text(32,680,'Q / E  切换分类',14,MUTE);text(392,680,'↑ ↓  选择     ← →  调整',14,MUTE)
poly([(1004,667),(1252,667),(1244,708),(996,708)],CYAN)
text(1020,677,'返回',22,INK);text(1192,683,'Esc',12,INK,True)
save('settings',{'active_group':'画面','sample_values':True,'options_source':'game/scripts/settings_panel.gd ROWS / TABS / CLOUD_TAB','visible_keys':['quality','fullscreen','res_index','ui_size_pct','cam_zoom_pct'],'additional_rows':'scroll, preserve all existing settings','cloud_group':'only when Cloud.supported','design':'fixed light category index, dark scrollable controls, hard-edged pixel sliders'})
