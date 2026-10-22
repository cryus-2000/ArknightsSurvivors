"""Alternative difficulty design sheet, no runtime changes."""
from pathlib import Path
# Reuse only drawing helpers; never execute the approved settings renderer.
exec((Path(__file__).parent/'render_difficulty_settings.py').read_text(encoding='utf-8').split('# Difficulty:')[0])
import math
start();top('选择难度','OPERATION / SURVEY')
# Light instrument margin and dark cross-section. Sparse, snapped 2px geometry.
rect((0,48,266,653),WHITE)
text(30,80,'探索深度',36,INK);text(32,130,'DEPTH / SELECT',12,'#5c616a',True)
text(32,183,'难度档位',13,'#5c616a')
line([(58,239),(58,558)],'#9da5ae',2)
for y in range(239,559,10):line([(48 if y%20 else 42,y),(58,y)],'#9da5ae',2)
for y,num,cn,en,col in [(251,'01','标准','STANDARD','#347e8a'),(381,'02','困难','HARD',INK),(521,'03','极限','EXTREME','#887177')]:
    if num=='02':
        rect((20,y-35,250,y+61),INK)
        rect((20,y-35,24,y+61),YELLOW)
        text(38,y-17,num,40,YELLOW,True)
        text(106,y-13,cn,29,WHITE);text(108,y+26,en,11,YELLOW,True)
    else:
        rect((51,y-4,65,y+10),col)
        text(90,y-18,cn,27,col);text(92,y+20,en,10,col,True)
text(180,525,'LOCKED',10,'#887177',True)
text(32,603,'↑ ↓  选择档位',13,'#5c616a')
# Geological profile sweeps from shallow shelf to a dark trench.
text(302,82,'02',17,YELLOW,True);text(346,79,'困难',33)
text(304,126,'HARD / OPERATION CONDITIONS',11,MUTE,True)
outline(664,72,'02',103,'#2c3542')
line([(302,169),(865,169)])
text(305,189,'海域剖面',11,MUTE);text(728,189,'SCHEMATIC',10,MUTE,True)
# Discrete water depth bands and a crisp sea surface.
rect((302,218,864,534),'#14232f')
rect((302,288,864,534),'#13212d')
rect((302,386,864,534),'#121e29')
for x in range(302,864,2):
    y=222+2*round(math.sin((x-302)/27))
    rect((x,y,x+1,y+1),'#75b4bf')
for x,y,w in [(330,216,24),(468,218,40),(630,216,32),(802,220,26)]:
    rect((x,y,x+w,y+1),'#a3d2d5')
# All terrain lines rendered on the same 2px grid. No invented map coordinates.
def profile(x,k=0):
    u=(x-302)/560
    v=246+195/(1+math.exp(-(u-.46)*10))+math.sin(u*19)*9+k*13
    return int(v//2)*2
for k in range(6):
    pts=[(x,profile(x,k)) for x in range(302,865,2)]
    poly(pts+[(864,536),(302,536)],['#273443','#23303d','#202b37','#1c2630','#18212a','#151d26'][k])
    line(pts,'#506473' if k==0 else '#344653',2)
for y in [280,408,520]:
    for x in range(304,862,22):line([(x,y),(x+2,y)],'#293641')
# Sparse sea-life symbols; all strokes are snapped to a 2px grid.
def jelly(x,y,s=2):
    pts=[(0,5),(2,2),(5,0),(9,0),(12,2),(14,5),(14,8),(0,8)]
    poly([(x+a*s,y+b*s) for a,b in pts],'#527e91')
    line([(x+2*s,y+3*s),(x+5*s,y+s),(x+9*s,y+s)],'#9abac4',2)
    line([(x,y+8*s),(x+14*s,y+8*s)],'#7fa4b5',2)
    for a,length in [(2,13),(6,16),(10,12)]:
        line([(x+a*s,y+9*s),(x+a*s,y+11*s),(x+(a-1)*s,y+13*s),(x+(a+1)*s,y+length*s)],'#456a80',2)
jelly(670,264,2);jelly(790,370,2)
for x,y in [(594,270),(610,280),(630,266)]:
    poly([(x,y),(x+8,y-2),(x+12,y),(x+8,y+2)],'#537584')
    line([(x,y),(x-4,y-2),(x-4,y+2),(x,y)],'#537584',2)
for x,y in [(386,254),(736,434),(820,444)]:
    line([(x,y),(x,y-20),(x-8,y-28),(x-8,y-34)],'#4c6678',2)
    line([(x,y-12),(x+8,y-18),(x+8,y-28)],'#4c6678',2)
# Selected depth line crosses the sounding profile, with a bright locator.
line([(302,352),(864,352)],YELLOW,2)
rect((559,342,579,362),BG);corners(559,342,20,20,YELLOW)
rect((566,349,572,355),YELLOW)
text(730,327,'当前选择',12,YELLOW)
line([(569,365),(569,473),(600,500)],'#8e875b',2)
text(615,489,'敌人强化',19,WHITE);text(616,519,'补给受限',14,MUTE)
text(305,563,'通关「困难」后解锁极限',15,MUTE)
text(305,600,'结算系数',13,MUTE);text(410,589,'×1.25',29,YELLOW,True)
text(628,600,'通关评级',13,MUTE);text(743,589,'SS',29,WHITE,True)
# Narrow dossier: fixed readable rules and local record, not another big card.
rect((902,48,1279,653),'#1b2029')
rect((902,48,906,155),YELLOW)
text(935,83,'行动条件',27);text(937,125,'CONDITIONS / ALL',11,MUTE,True)
line([(935,169),(1244,169)])
conditions=[('敌人生命与伤害','+20%'),('Boss 生命','+15%'),('大群规模','+20%'),
    ('Boss 预警时间','-15%'),('队长初始最大生命','-10%'),('受击灯火损失','+30%'),
    ('灯油掉落','-40%'),('源石锭掉落','-25%'),('小怪控制开始','05:00'),
    ('寒霜冻结层数','2 层'),('围猎时长／圈上海嗣生命','-15%'),('灯标刷新间隔','-20%')]
for i,(a,b) in enumerate(conditions):
    y=190+i*28
    text(936,y,a,14,MUTE)
    text(1238-int(d.textlength(b,font=font(19,False))),y-2,b,19,WHITE)
text(936,534,'Boss 预警不低于 0.6 秒',12,MUTE)
line([(935,565),(1244,565)])
text(936,590,'本档通关',16,MUTE);text(1130,580,'03',39,WHITE,True);text(1200,603,'次',13,MUTE)
footer();text(31,679,'返回  Esc',17,MUTE);text(304,679,'认知塑造',19)
poly([(923,668),(1252,668),(1244,708),(915,708)],CYAN)
text(942,678,'确认难度',22,INK);text(1160,684,'Enter',12,INK,True)
line([(1225,679),(1233,687),(1225,695)],INK,2)
save('difficulty_survey',{'selected':'困难','sample_values':True,'conditions':conditions,'record_sample':{'clears':3},'design':'depth instrument and terrain section; no equal cards','terrain':'original schematic, not actual level geometry','source':'DIFF_PRESETS; record values are examples','previous_candidate':'../difficulty/difficulty_desktop.png'})
