"""Four left-menu visual studies, sharing the existing scene and approved logo."""
from pathlib import Path
import importlib.util
import json
import math
import sys
from PIL import Image, ImageDraw

P=Path(__file__).resolve().parent
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('primitives',P.parent/'title_ui_variants_41/render.py')
u=importlib.util.module_from_spec(spec);spec.loader.exec_module(u)
u.P=P.parent/'title_scene_grouped_43'
T='#e9f0f3';M='#a2b9c8';L='#466171';C='#9de5ef';INK='#132734'
LABELS={'deploy':'集结出发','headhunt':'寻访','gallery':'图鉴','cognition':'认知塑造','trial':'试炼','settings':'设置','guide':'操作说明','quit':'退出'}
EN={'deploy':'DEPLOY','headhunt':'HEADHUNT','gallery':'ARCHIVE','cognition':'COGNITION','trial':'TRIAL'}
INFO={
 'A':{'name':'终端模块','description':'主操作反差明确，副入口用不等大的模块组织。'},
 'B':{'name':'纵向索引','description':'以字级、序号和连续基线组织入口，减少面板面积。'},
 'C':{'name':'探索徽记','description':'上方轻量图标导航，下方以独立徽记承接出发操作。'},
 'D':{'name':'错层标签','description':'菜单沿一条结构线错落排列，用局部明度反转突出主操作。'},
}
BOXES={
 'A':[(68,248,443,380),(68,398,245,503),(257,398,434,503),(68,516,434,591),(68,604,434,644)],
 'B':[(62,230,437,331),(62,351,437,419),(62,426,437,494),(62,501,437,569),(62,576,437,639)],
 'C':[(65,480,415,645),(66,224,352,279),(66,286,352,341),(66,348,352,403),(66,410,352,465)],
 'D':[(83,241,446,351),(114,369,428,430),(88,444,402,505),(126,519,440,580),(88,594,402,642)],
}
FOOT=[(68,658,125,697),(143,658,239,697),(258,658,315,697)]
IDS=list(LABELS)

def txt(im,x,y,s,size=22,col=T,face='regular',spacing=0):u.text(im,x,y,s,size,col,face,spacing)
def line(im,pts,col=L,w=1):u.line(im,pts,col,w)
def panel(im,box,fill):u.rect(im,box,fill)
def chevron(im,x,y,col=C,w=2):line(im,[(x-7,y-10),(x+3,y),(x-7,y+10)],col,w)
def arc(im,x,y,r,start,end,col=L,w=1):
    pts=[(x+r*math.cos(math.radians(a)),y+r*math.sin(math.radians(a))) for a in range(start,end+1)]
    line(im,pts,col,w)

def footer(im,selected):
    for k,b in zip(IDS[5:],FOOT):
        x,y,r,bot=b;txt(im,x+7,y+10,LABELS[k],15,T if selected==k else M)
        if selected==k:line(im,[(x+7,690),(r-8,690)],C,2)

def label(im,k,x,y,active,size=25,icon=True,en=True):
    if icon:u.icon(im,x,y+15,k,C if active else '#b6cbd6',.9)
    xx=x+31 if icon else x
    txt(im,xx,y,LABELS[k],size,T,'bold')
    if en:txt(im,xx,y+35,EN[k],9,M,'latin',2.2)
    if k=='trial':txt(im,xx+60,y+12,'测试版',10,M)

def a(im,s):
    active=s=='deploy'
    u.poly(im,[(82,260),(454,260),(440,389),(69,389)],(14,32,44,220))
    u.poly(im,[(79,248),(443,248),(431,380),(68,380)],'#c1d1d8' if active else '#a8bbc6')
    panel(im,(79,248,443,251),C if active else '#7d9cab')
    txt(im,96,272,'集结出发',43,INK,'bold')
    txt(im,100,344,'DEPLOY',11,'#365869','latin',4)
    line(im,[(334,331),(388,277),(409,277),(355,331)],'#497284',3)
    chevron(im,401,320,INK,2)
    for k,b in zip(IDS[1:3],BOXES['A'][1:3]):
        x,y,r,bot=b;active=s==k
        panel(im,b,(36,65,83,245) if active else (12,27,38,224))
        line(im,[(x,y),(r,y)],C if active else L,2 if active else 1)
        u.icon(im,x+27,y+28,k,C if active else M,1)
        txt(im,x+16,y+57,LABELS[k],25,T,'bold')
        txt(im,x+61,y+22,EN[k],8,M,'latin',1.5)
        if active:chevron(im,r-20,y+73)
    active=s=='cognition';b=BOXES['A'][3]
    panel(im,b,(36,65,83,245) if active else (12,27,38,224))
    u.icon(im,94,551,'cognition',C if active else M,1)
    txt(im,124,535,'认知塑造',25,T,'bold');txt(im,126,572,'COGNITION',8,M,'latin',2)
    chevron(im,407,552,C if active else M)
    line(im,[(68,591),(434,591)],C if active else L)
    b=BOXES['A'][4];panel(im,b,(24,44,58,225) if s=='trial' else (12,27,38,175))
    u.icon(im,94,624,'trial',C if s=='trial' else M,.65)
    txt(im,122,615,'试炼',19,T);txt(im,180,622,'测试版',10,M)
    if s=='trial':chevron(im,407,624)

def b(im,s):
    # A quiet unframed column supplies contrast without individual button cards.
    panel(im,(48,217,449,645),(7,20,29,140))
    line(im,[(62,227),(62,630)],'#344d5d',1)
    for i,k in enumerate(IDS[:5]):
        x,y,r,bot=BOXES['B'][i];active=s==k
        panel(im,(x-2,y+8,x+2,y+29),C if active else '#557180')
        txt(im,79,y+10,f'{i+1:02}',11,C if active else M,'latin',1)
        if k=='deploy':
            txt(im,109,y+6,'集结出发',43,T,'bold',.8)
            txt(im,111,y+65,'DEPLOY',10,C if active else M,'latin',5)
            chevron(im,413,y+36,C if active else M,2)
        else:
            txt(im,109,y+2,LABELS[k],27,T,'bold' if active else 'regular')
            txt(im,111,y+40,EN[k],9,M,'latin',2.4)
            if k=='trial':txt(im,178,y+15,'测试版',10,M)
            if active:chevron(im,411,y+24)
        line(im,[(109,bot-6),(429,bot-6)],'#355164',.7)
        if active:line(im,[(109,bot-6),(k=='deploy' and 318 or 210,bot-6)],C,2)

def c(im,s):
    for k,bx in zip(IDS[1:5],BOXES['C'][1:]):
        x,y,r,bot=bx;active=s==k
        if active:
            u.poly(im,[(x+2,y+3),(r-1,y+3),(r-17,bot-3),(x+2,bot-3)],(32,60,77,178))
        u.circle(im,88,y+26,20,None,C if active else '#5c7e8f',1)
        u.icon(im,88,y+26,k,C if active else '#cad9e1',.85)
        txt(im,124,y+7,LABELS[k],26,T,'serif')
        txt(im,125,y+42,EN[k],8,M,'latin',2)
        if k=='trial':txt(im,191,y+20,'测试版',10,M)
        if active:chevron(im,325,y+25,C,1.5)
    # Original navigation seal: interrupted rings and a directional path.
    active=s=='deploy';cx,cy=284,556
    for rad,start,end in [(76,197,342),(86,12,123),(67,16,126),(82,133,174)]:arc(im,cx,cy,rad,start,end,'#598c9e',.8)
    for i in range(22):
        angle=math.radians(-70+i*6.3)
        line(im,[(cx+math.cos(angle)*73,cy+math.sin(angle)*73),(cx+math.cos(angle)*82,cy+math.sin(angle)*82)],'#81becb' if active else L,1)
    line(im,[(259,604),(310,553),(310,526),(276,526)],C if active else M,2)
    line(im,[(280,577),(328,529),(328,560)],C if active else M,2)
    u.circle(im,255,608,3,C if active else M,None)
    txt(im,74,492,'集结',48,T,'serif',3);txt(im,99,548,'出发',48,T,'serif',3)
    txt(im,78,617,'DEPLOY',10,C if active else M,'latin',4)
    line(im,[(75,643),(236,643)],C if active else L,1.3)

def d(im,s):
    path=[(71,234),(54,291),(83,401),(57,475),(95,549),(58,618)]
    line(im,path,'#567585',1)
    for i,k in enumerate(IDS[:5]):
        x,y,r,bot=BOXES['D'][i];active=s==k
        # Short staggered plates follow the structural line; type remains upright.
        yy=(y+bot)/2;node=path[i+1]
        line(im,[node,(x-6,yy),(x+8,yy)],C if active else '#557180')
        u.circle(im,*node,4,C if active else '#3f5f72',None)
        if k=='deploy':
            u.poly(im,[(x+11,y+9),(r+10,y+9),(r-4,bot+9),(x-3,bot+9)],(29,53,67,225))
            u.poly(im,[(x,y),(r,y),(r-13,bot),(x-13,bot)],(17,35,47,245))
            panel(im,(x+12,y+19,r-21,y+72),'#bfced6' if active else '#91a9b8')
            txt(im,x+26,y+25,'集结出发',34,INK,'bold')
            chevron(im,r-40,y+45,INK)
            txt(im,x+27,bot-24,'DEPLOY',10,C if active else M,'latin',4)
        else:
            u.poly(im,[(x,y),(r,y),(r-10,bot),(x-10,bot)],(38,68,86,242) if active else (13,30,41,224))
            line(im,[(x,y),(r,y)],C if active else L,1.5 if active else .7)
            u.icon(im,x+25,yy,k,C if active else M,.8)
            txt(im,x+56,y+12,LABELS[k],25 if k!='trial' else 20,T,'bold')
            if k=='trial':txt(im,x+118,y+22,'测试版',10,M)
            if active:chevron(im,r-24,yy,C,1.5)

def main():
    bg=Image.open(u.P/'assets/background_native.png').convert('RGBA').resize((1920,1080),Image.Resampling.NEAREST)
    layouts={}
    for variant,fn in [('A',a),('B',b),('C',c),('D',d)]:
        layouts[variant]=[{'id':k,'label':LABELS[k]+('（测试版）' if k=='trial' else ''),'box':list(box)} for k,box in zip(IDS,BOXES[variant]+FOOT)]
        for selected in IDS:
            u.CURRENT=variant+'_'+selected;im=u.layer();u.logo(im,68,49,241)
            fn(im,selected);footer(im,selected)
            overlay=im.resize((1920,1080),Image.Resampling.LANCZOS);overlay.save(P/f'{variant}_{selected}.png')
            if selected=='deploy':Image.alpha_composite(bg,overlay).convert('RGB').save(P/f'{variant}_overview.png')
            if selected=='cognition':Image.alpha_composite(bg,overlay).convert('RGB').save(P/f'{variant}_focus.png')
    # Whole-screen contact sheet, not isolated UI fragments.
    board=Image.new('RGB',(1920,1160),'#101c25');d0=ImageDraw.Draw(board)
    for idx,k in enumerate(INFO):
        x=(idx%2)*960;y=(idx//2)*580
        d0.text((x+20,y+8),k+'  '+INFO[k]['name'],font=u.font(8,'bold'),fill='#d4e4ec')
        board.paste(Image.open(P/f'{k}_overview.png').resize((960,540),Image.Resampling.LANCZOS),(x,y+40))
    board.save(P/'comparison.png')
    (P/'layouts.json').write_text(json.dumps(layouts,ensure_ascii=False,indent=2),encoding='utf8')
    (P/'directions.json').write_text(json.dumps(INFO,ensure_ascii=False,indent=2),encoding='utf8')
    print('Rendered four full-screen directions and 32 focus states.')

if __name__=='__main__':main()
