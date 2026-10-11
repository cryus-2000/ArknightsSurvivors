# -*- coding: utf-8 -*-
"""手摆像素 Boss 头像（10-11，登场名片 boss_intro.gd CARDS[*].portrait 用；替代待机帧条第 0 帧的占位）。

与 tools/relic_icons_hand.py 同一套管线：每张头像是逐像素手摆的字符图 + 调色表，这里网格是 44×44 字符，一字符 = 1x 的 2×2 像素
（和游戏里 1 美术像素 = 2 世界像素的画法一致），渲染成 88×88 的 1x 与 176×176 的 @2x（严格 2 倍最近邻）。
规格：头肩像、透明底、二值 alpha、1 px（字符）外轮廓 #080E18、来光左侧（左亮右暗）、各 Boss 的强调色取 boss_intro.gd CARDS / vfx.BOSS_STYLE
（只做点缀：眼光 / 纹样 / 边光，人物保持本来的颜色）；参考各自的帧条 art/incoming/e_<tex>*.png 与 docs/38 的描述。
留边：上 / 左 / 右各 1 字符，肩部可以贴到底边（名片的 88 框把肩切掉一点正合适）。

用法：python tools/boss_portraits_hand.py             渲染到 build/portraits_out/png/boss_<id>.png（+ @2x），并出总表 build/portraits_out/portraits_contact.png
      python tools/boss_portraits_hand.py --view 6    另出放大自检图 build/portraits_out/_view6x.png（--only carmen,ishar 只看这些）
      python tools/boss_portraits_hand.py --live      接入到 art/incoming/portraits/boss_<id>.png 与 boss_<id>@2x.png
自检：每行 44 字符、44 行、字符都在调色表里、上 / 左 / 右 1 字符留边、alpha 只有 0/255、@2x 逐像素 = 1x 最近邻放大。
"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
INC = os.path.join(ROOT, "art", "incoming", "portraits")
OUT = os.path.join(ROOT, "build", "portraits_out")
N = 44

O = (0x08, 0x0E, 0x18)      # 轮廓
H = (0xF2, 0xF6, 0xFA)      # 白高光

# 强调色（boss_intro.gd CARDS 缺省 = vfx.BOSS_STYLE），只做点缀
ACCENT = {
	"carmen": (255, 194, 77), "iberia": (255, 115, 51), "path": (179, 204, 242), "bishop": (64, 217, 230),
	"archon": (128, 242, 153), "immortal": (166, 191, 255), "paranoia": (204, 102, 255), "knight_boss": (140, 217, 255),
	"ishar": (51, 255, 217), "izumik": (140, 255, 166),
}
NAMES = {
	"path": "塑路者", "iberia": "圣徒伊比利亚", "carmen": "圣徒卡门", "bishop": "接潮主教", "archon": "蔑死体",
	"immortal": "斥亡体", "paranoia": "偏执泡影", "ishar": "伊莎玛拉", "izumik": "伊祖米克", "knight_boss": "最后的骑士",
}
ORDER = ["path", "iberia", "carmen", "bishop", "archon", "immortal", "paranoia", "ishar", "izumik", "knight_boss"]
PORTRAITS = {}


def portrait(bid, pal, rows):
	pal = dict(pal)
	pal["#"] = O
	pal["H"] = H
	pal["A"] = ACCENT[bid]
	PORTRAITS[bid] = (pal, rows)


# ---------------------------------------------------------------- 圣徒卡门（e_saint）
# 老猎人：高礼帽（正面银十字）、白发白须、灰呢大衣翻领、暗红领巾；眉压得很低，左眼有金色点光（强调色）。来光左侧：左脸亮、右脸转暗。
SAINT_PAL = {
	"k": (44, 38, 48), "K": (26, 22, 32), "j": (80, 26, 42), "s": (206, 206, 216), "S": (150, 150, 162),
	"w": (234, 238, 242), "g": (176, 184, 198), "G": (122, 130, 148),
	"f": (236, 200, 172), "F": (204, 164, 140), "d": (154, 112, 98), "e": (40, 24, 32),
	"c": (96, 96, 106), "C": (62, 62, 72), "x": (40, 40, 50), "t": (176, 176, 188),
	"m": (152, 40, 62), "M": (100, 26, 44),
}
portrait("carmen", SAINT_PAL, [
	"............................................",
	"..............################..............",
	"............##kkkkkkkkkkkkkkkk##............",
	"...........#kkkkkkkkkkKKKKKKKKKK#...........",
	"...........#kkkkkkkksKKKKKKKKKKK#...........",
	"...........#kkkkkkksssSKKKKKKKKK#...........",
	"...........#kkkkkkkksKKKKKKKKKKK#...........",
	"...........#kkkkkkkksKKKKKKKKKKK#...........",
	"...........#kkkkkkksssSKKKKKKKKK#...........",
	"...........#kkkkkkkkkkKKKKKKKKKK#...........",
	"...........#jjjjjjjjjjjjjjjjjjjj#...........",
	"......######kkkkkkkkkkkkkkkkkkkk######......",
	"....##kkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKK##...",
	"...#kkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKKKK#...",
	"....###########wwwwwwwwwwgg############.....",
	"........#wwwwwwwfffffffffffgggg#............",
	".......#wwwwwwfddddfffffddddFFgg#...........",
	".......#wwwwwffeeefffffffeeeFFgg#...........",
	".......#wwwwfffAeffffffffeeFFFgg#...........",
	".......#wwwwfffffffffffffFFFFFGg#...........",
	".......#wwwwfffffffdFFFFFFFFFFGg#...........",
	".......#wwwwfffffffddFFFFFFFFFGG#...........",
	".......#wwwwwfffwwwwwwwwFFFFFFGG#...........",
	"........#wwwwwwwwwwwwwwwwwggGGG#............",
	"........#wwwwwwwwwwwwwwwwwwggGG#............",
	"........#wwwwwwwwwwwwwwwwwwggGG#............",
	".........#wwwwwwwwwwwwwwwwgggG#.............",
	".........#wwwwwwwwwwwwwwwgggGG#.............",
	"..........#wwwwwwwwwwwwwggggG#..............",
	"......#####wwwwwwwwwwwwggggG#####...........",
	"....##ccccc#wwwwwwwwwwgggG#CCCCC##..........",
	"...#cccccccc#wwwwwwwwggG#CCCCCCCCC#.........",
	"..#ccccccccct#wwwwwwgG#tCCCCCCCCCCC#........",
	".#cccccccccctt#wwwwG#tmmCCCCCCCCCCCC#.......",
	".#cccccccccttmm#ww#tmmmmCCCCCCCCCCCCx#......",
	".#ccccccccctmmmm####mmmmMMCCCCCCCCCCx#......",
	".#cccccccctmmmmmmmmmmmMMMMMCCCCCCCCCx#......",
	".#ccccccctmmmmmmmmmmMMMMMMMMCCCCCCCCx#......",
	".#cccccccctmmmmmmmmMMMMMMMMMtCCCCCCCx#......",
	".#ccccccccctmmmmmmMMMMMMMMMtCCCCCCCxx#......",
	".#cccccccccctmmmmMMMMMMMMMtCCCCCCCCxx#......",
	".#cccccccccccttMMMMMMMMMttCCCCCCCCxxx#......",
	".#cccccccccccccttttttttCCCCCCCCCCxxxx#......",
	".#####################################......",
])

# ---------------------------------------------------------------- 圣徒伊比利亚（e_saint_dark）
# 同一位老猎人的强化形态：帽侧插一根暗红长羽（向左后扬）、破旧的暗红斗篷披在肩上盖住大衣、眼神更沉；左眼橙色点光。
IBERIA_PAL = dict(SAINT_PAL)
IBERIA_PAL.update({"p": (120, 34, 58), "P": (78, 20, 40), "q": (150, 50, 72), "c": (60, 50, 60), "C": (42, 34, 44), "x": (28, 22, 30)})
portrait("iberia", IBERIA_PAL, [
	"............................................",
	"...........#..################..............",
	"..........#q##kkkkkkkkkkkkkkkk##............",
	".........#qq#kkkkkkkkkkKKKKKKKKK#...........",
	"........#qpq#kkkkkkkksKKKKKKKKKK#...........",
	".......#qppq#kkkkkkksssSKKKKKKKK#...........",
	".......#qpppq#kkkkkkksKKKKKKKKKK#...........",
	"......#qpppPq#kkkkkkksKKKKKKKKKK#...........",
	"......#qppPPq#kkkkkksssSKKKKKKKK#...........",
	"......#qpPPPPq#kkkkkkkkkKKKKKKKK#...........",
	".....#qppPPPPq#jjjjjjjjjjjjjjjjj#...........",
	".....#qpPPPPPq#kkkkkkkkkkkkkkkkk######......",
	"....##qpPPPPPPqkkkkkkkkkkkkkkKKKKKKKKKK##...",
	"...#kkqPPPPPPPkkkkkkkkkkkkkkKKKKKKKKKKKK#...",
	"....####PPPP###wwwwwwwwwwgg############.....",
	"........####wwwwfffffffffffgggg#............",
	".......#wwwwwwfddddfffffddddFFgg#...........",
	".......#wwwwwffeeefffffffeeeFFgg#...........",
	".......#wwwwfffAeffffffffeeFFFgg#...........",
	".......#wwwwfffffffffffffFFFFFGg#...........",
	".......#wwwwfffffffdFFFFFFFFFFGg#...........",
	".......#wwwwfffffffddFFFFFFFFFGG#...........",
	".......#wwwwwfffwwwwwwwwFFFFFFGG#...........",
	"........#wwwwwwwwwwwwwwwwwggGGG#............",
	"........#wwwwwwwwwwwwwwwwwwggGG#............",
	"........#wwwwwwwwwwwwwwwwwwggGG#............",
	".........#wwwwwwwwwwwwwwwwgggG#.............",
	".........#wwwwwwwwwwwwwwwgggGG#.............",
	"..........#wwwwwwwwwwwwwggggG#..............",
	"......#####wwwwwwwwwwwwggggG#####...........",
	"....##qpppp#wwwwwwwwwwgggG#PPPPP##..........",
	"...#qppppppp#wwwwwwwwggG#PPPPPPPPP#.........",
	"..#qpppppppcc#wwwwwwgG#CPPPPPPPPPPP#........",
	".#qppppppccctt#wwwwG#tmmCPPPPPPPPPPP#.......",
	".#qppppppcttmm#ww#tmmmmCCPPPPPPPPPPPx#......",
	".#qpppppcctmmmm####mmmmMMCCPPPPPPPPPx#......",
	".#qppppppctmmmmmmmmmmmMMMMMCCPPPPPPPx#......",
	".#qppppppctmmmmmmmmmMMMMMMMMCCPPPPPPx#......",
	".#qpppppppctmmmmmmmMMMMMMMMMtCCPPPPPx#......",
	".#qpppppppppctmmmmmMMMMMMMMMtCCCPPPxx#......",
	".#qpppppppppcctmmmMMMMMMMMMtCCCCPPPxx#......",
	".#qpppppppppppcttMMMMMMMMMttCCCCPPxxx#......",
	".#qpppppppppppppcttttttttCCCCCCCxxxxx#......",
	".#####################################......",
])

# ---------------------------------------------------------------- 塑路者（e_path）
# 替大群探路的海嗣：一团低伏的黑紫甲壳（左缘受光泛蓝灰，壳面一道道斜向甲缝），右上探出苍白的骨质头颅、两道钢蓝眼缝（强调色）；
# 底下左右各伸出一对苍白的甲刃（本体帧条里就是这几片白骨最显眼）。
portrait("path", {
	"k": (46, 40, 58), "K": (30, 26, 40), "x": (18, 16, 26), "l": (74, 66, 92), "L": (98, 92, 122),
	"p": (214, 214, 226), "P": (168, 170, 190), "q": (120, 124, 150), "b": (120, 170, 230), "B": (60, 100, 170),
	"v": (90, 60, 110),
}, [
	"............................................",
	"............................................",
	"............................................",
	"............................................",
	"..........................####..............",
	"........................##pppp##............",
	".......................#ppppppppp#..........",
	"......................#pppHpppppPP#.........",
	"......................#ppppppppPPPP#........",
	".....................#pppppppppPPPPP#.......",
	".....................#pppppppppPPPPPq#......",
	".....................#ppAAApppppAAAPq#......",
	"..............#####..#pABBAppppABBAPq#......",
	"...........###lllll###ppAAApppppAAAPq#......",
	".........##llllkkkkkkk#ppppPPPPPPPqq#.......",
	"........#lllkkkkkkkkkkk#pPPPPPqqqqq#........",
	".......#llkkkkkkkkkkkkkk#PPq#qqqq##.........",
	"......#llkkkkkkkkkkkkkkkk#q#.####...........",
	"......#lkkkkkkkkkkkkkkkkkk#.................",
	".....#lkkkkkLLkkkkkkkkkkkkk#................",
	".....#lkkkkLkkLkkkkkkkkkkkkK#...............",
	"....#lkkkkLkkkkLkkkkkkkkkkkKK#..............",
	"....#lkkkkLkkkkkLkkkkkkkkkkKKK#.............",
	"....#lkkkkkLkkkkkLkkkkkkkkkKKKK#............",
	"...#lkkkkkkkLkkkkkLkkkkkkkkKKKKK#...........",
	"...#lkkkkkkkkLkkkkkLkkkkkkkKKKKKK#..........",
	"...#lkkkkkkkkkLkkkkkLkkkkkkKKKKKKK#.........",
	"...#lkkkkkkkkkkLkkkkkLkkkkkKKKKKKKK#........",
	"..#lkkkkkkkkkkkkLkkkkkLkkkkKKKKKKKKK#.......",
	"..#lkkkkkkkkkkkkkLkkkkkLkkkKKKKKKKKK#.......",
	"..#lkkkkkvvkkkkkkkLkkkkkLkkKKKKKKKKKK#......",
	"..#lkkkkvvvvkkkkkkkLkkkkkLkKKKKKKKKKK#......",
	"..#lkkkkkvvkkkkkkkkkLkkkkkLKKKKKKKKKKx#.....",
	".#lkkkkkkkkkkkkkkkkkkLkkkkkKKKKKKKKKxx#.....",
	".#lkkkkkkkkkkkkkkkkkkkLkkkkKKKKKKKKKxx#.....",
	".#lkkkkkkkkkkkkkkkkkkkkLkkkKKKKKKKKxxx#.....",
	".#lkkkkkkkkkkkkkkkkkkkkkLkkKKKKKKKKxxx#.....",
	".#lkkkkkkkkkkkkkkkkkkkkkkLkKKKKKKKxxxx#.....",
	".#lkk#pp#kkkkkkkkkkkkkkkkkKKKKK#pp#xxx#.....",
	".#lk#pPPP#kkkkkkkkkkkkkkkkKKKK#pPPP#xx#.....",
	".#l#ppPPPP#kkkkkkkkkkkkkkkKKK#ppPPPP#x#.....",
	".##ppPPPPq#kkkkkkkkkkkkkkkKK#ppPPPPq##......",
	".#pPPPPqqq#kkkkkkkkkkkkkkkK#pPPPPqqq#.......",
	".####################################.......",
])

# ---------------------------------------------------------------- 接潮主教（e_bishop）
# 戴宽檐黑帽的长袍祭司：帽下只露苍白的下半张脸，墨绿长袍带金绿纹，右肩旁举着法杖、杖头一团青色（强调色）潮光。
portrait("bishop", {
	"k": (30, 30, 40), "K": (18, 18, 26), "g": (54, 96, 86), "G": (36, 66, 60), "d": (24, 44, 42),
	"y": (150, 140, 80), "f": (214, 206, 200), "F": (168, 160, 160), "e": (40, 30, 40),
	"s": (110, 100, 80), "S": (70, 62, 50), "o": (190, 255, 250), "a": (40, 150, 160),
}, [
	"............................................",
	"............................................",
	".................############...............",
	"...............##kkkkkkkkkkkk##.............",
	"..............#kkkkkkkkkkkkkkKK#............",
	".............#kkkkkkkkkkkkkkkKKK#...........",
	".............#kkkkkkkkkkkkkkkKKK#...........",
	".............#kkkkkkkkkkkkkkkKKK#...........",
	".............#kkkkkkkkkkkkkkkKKK#...........",
	".............#kkkkkkkkkkkkkkkKKK#...........",
	".......#######kkkkkkkkkkkkkkkKKK#######.....",
	".....##kkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKK##...",
	"....#kkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKK#..",
	"....#kkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKKK#..",
	".....###########KKKKKKKKKKKK############....",
	"...............#KKKKKKKKKKKKK#.......##.....",
	"...............#KKffeKKKKKeKK#......#oo#....",
	"...............#KfffffffffFFF#.....#oAAo#...",
	"...............#fffffffffFFFF#.....#oAAo#...",
	"...............#ffffffffFFFFF#......#oo#....",
	"...............#fffffffFFFFFF#......#aa#....",
	"................#ffffFFFFFFF#.......#aa#....",
	"................#ffffFFFFFFF#.......#aa#....",
	".................#fffFFFFFF#........#aa#....",
	"............#######ffFFFF#####......#aa#....",
	"..........##gggggg#ffFFF#GGGGG##....#aa#....",
	"........##ggggggggg#fFF#GGGGGGGG#...#aa#....",
	".......#gggggggggggg#F#GGGGGGGGGG#..#aa#....",
	"......#gggggyggggggg###GGGGGyGGGGG#.#aa#....",
	".....#gggggyyyggggggggGGGGGyyyGGGGG##aa#....",
	".....#ggggyyyyyggggggGGGGGGyyyGGGGG#saa#....",
	"....#gggggyyyygggggggGGGGGGGyyyGGGG#Ssa#....",
	"....#ggggggyyyggggggGGGGGGGGyyyGGGGsSSs#....",
	"....#gggggggygggggggGGGGGGGGyyGGGGGdsSs#....",
	"...#ggggggggggggggggGGGGGGGGGyGGGGdd#aa#....",
	"...#gggggggggggggggGGGGGGGGGGGGGGddd#aa#....",
	"...#ggggggggggggggGGGGGGGGGGGGGGdddd#aa#....",
	"..#ggggggggggggggggGGGGGGGGGGGGGddddd#aa#...",
	"..#gggggggggggggggGGGGGGGGGGGGGGddddd#aa#...",
	"..#gggggggggggggggGGGGGGGGGGGGGGddddd#aa#...",
	".#ggggggggggggggggGGGGGGGGGGGGGGdddddd#aa#..",
	".#ggggggggggggggggGGGGGGGGGGGGGddddddd#aa#..",
	".#gggggggggggggggGGGGGGGGGGGGGGddddddd#aa#..",
	".##########################################.",
])

# ---------------------------------------------------------------- 蔑死体（e_archon）
# 与主教同生共死的粗壮海嗣：漆黑的兽首朝左、吻部前探，颈背一排鲜黄的骨刺向右后掠；额前扣着白骨面甲，面甲下一点绿光（强调色），
# 颈部收细后再放宽到肩，肩甲左缘受光。
portrait("archon", {
	"k": (36, 32, 44), "K": (22, 20, 30), "l": (62, 56, 74), "y": (244, 212, 40), "Y": (190, 150, 24), "o": (120, 90, 20),
	"w": (226, 228, 234), "W": (170, 172, 184), "q": (120, 122, 140), "r": (190, 60, 70),
}, [
	"............................................",
	"............................................",
	"............................................",
	"..................#......#......#...........",
	".................#y#....#y#....#y#..........",
	"................#yy#...#yY#...#yY#....#.....",
	"...............#yyY#..#yyY#..#yYY#...#y#....",
	"...............#yyY#..#yYY#..#yYY#..#yY#....",
	"..............#yyYY#.#yyYY#.#yYYo#.#yYY#....",
	"..............#yyYo#.#yYYo#.#yYYo#.#yYo#....",
	".............#yyYYo##yyYYo##yYYoo##yYoo#....",
	".............#yYYYo#yYYYoo#yYYooo#yYooo#....",
	"..........####YYYoo#YYYooo#YYoooo#Yooo##....",
	"........##kkkkkkkkkkkkkkkkkkkkkkkkkkkkKK#...",
	"......##kkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKK#..",
	".....#lkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKK#.",
	"....#lkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKK#.",
	"...#lkkk######kkkkkkkkkkkkkkkkkkkkkkkKKKKK#.",
	"..#lkk##wwwwww##kkkkkkkkkkkkkkkkkkkkkKKKK#..",
	"..#lk#wwwwwwwwww#kkkkkkkkkkkkkkkkkkkkKKK#...",
	".#lk#wwwwwwwwwwwW#kkkkkkkkkkkkkkkkkkkKK#....",
	".#l#wwwwwwwwwwwwWW#kkkkkkkkkkkkkkkkkkK#.....",
	".#l#wwwHwwwwwwwwWWq#kkkkkkkkkkkkkkkkkK#.....",
	".#l#wwwwwww###wwWWq#kkkkkkkkkkkkkkkkK#......",
	".#l#wwwwww#AAA#wWWq#kkkkkkkkkkkkkkkKK#......",
	".#l#wwwwww#AAA#WWWq#kkkkkkkkkkkkkkKK#.......",
	".#l#wwwwwww###WWWWq#kkkkkkkkkkkkkKKK#.......",
	".#l#wwwwwwwwwwWWWWq#kkkkkkkkkkkkKKK#........",
	".#lk#wwwwwwwwWWWWq#kkkkkkkkkkkkKKK#.........",
	".#lk#wwwwwwwWWWWq#kkkkkkkkkkkkKKK#..........",
	".#lkk#wwwwwWWWWq#kkkkkkkkkkkkKKK#...........",
	".#lkk#WwwwWWWWq#kkkkkkkkkkkkKKK#............",
	".#lkkk#WWWWWWq#kkkkkkkkkkkkKKK#.............",
	".#lkkk#rWWWWq#kkkkkkkkkkkkkKKK#.............",
	".#lkkkk#WrWq#kkkkkkkkkkkkkkKKK##............",
	".#lkkkk#WWq#kkkkkkkkkkkkkkkkKKKK##..........",
	".#lkkkkk###kkkkkkkkkkkkkkkkkkKKKKK##........",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKK##......",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKK#.....",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKK#....",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKK#...",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKK#...",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKK#..",
	".########################################...",
])

# ---------------------------------------------------------------- 斥亡体（e_immortal）
# 迅捷的近战海嗣：细长的黑色兽首朝左，头上扣着白色骨盔（盔檐向右后掠成两道尖翼），眼缝里一道淡蓝光（强调色），
# 盔下露出黑色吻部与颈，颈侧几点暗红；颈收细、肩放宽，左缘受光。
portrait("immortal", {
	"k": (34, 32, 44), "K": (20, 20, 30), "l": (60, 58, 76), "w": (226, 228, 236), "W": (176, 180, 196), "q": (124, 128, 150),
	"r": (170, 50, 60), "b": (90, 120, 200),
}, [
	"............................................",
	"............................................",
	"............................................",
	"............................................",
	"...................##########...............",
	"................###wwwwwwwwww###............",
	"..............##wwwwwwwwwwwwwwWW##..........",
	"............##wwwwwwwwwwwwwwwwWWWW##........",
	"...........#wwwwwwwwwwwwwwwwwwWWWWWW#.......",
	"..........#wwwwwwwwwwwwwwwwwwwWWWWWWW#......",
	".........#wwwwwwwwwwwwwwwwwwwWWWWWWWWq#.....",
	".........#wwwHwwwwwwwwwwwwwwwWWWWWWWqq##....",
	"........#wwwwwwwwwwwwwwwwwwwWWWWWWWqqqqq#...",
	"........#wwwwwwwwwwwwwwwwwwWWWWWWWqqqqqqq#..",
	"........#wwwwwwwwwwwwwwwwwWWWWWWWqq###qqq#..",
	"........#wwwwwww#########WWWWWWqq#...###....",
	".......#wwwwwww#AAAAAAAAA#WWWWqq#...........",
	".......#wwwwww#AAbbbbbbbAA#WWWqq#...........",
	".......#wwwwww#AbbbbbbbbbA#WWWqq##..........",
	".......#wwwwwww#AAAAAAAAA#WWWqqqqq#.........",
	".......#wwwwwwww#########WWWqqqq##..........",
	".......#wwwwwwwwwwwwwwwwWWWWq###............",
	".......#wwwwwwwwwwwwwwwWWWWq#...............",
	"......#wwwwwwwwwwwwwwwWWWWWq#...............",
	"......#wwwwwwwwwwwwwwWWWWWq#................",
	"......#kkwwwwwwwwwwwWWWWWq#.................",
	"......#kkkkwwwwwwwWWWWWWq#..................",
	".....#lkkkkkkWWWWWWWWWqq#...................",
	"....#lkkkkkkkkk#######kk#...................",
	"...#llkkkkkkkkkkkkkkkkkkk#..................",
	"...#lkkkkkkkkkkkkkkkkkkkkK#.................",
	"...#lkkkkkkkrrkkkkkkkkkkkKK#................",
	"...#lkkkkkkkrrrkkkkkkkkkkKKK##..............",
	"..#lkkkkkkkkkrrkkkkkkkkkkkKKKK##............",
	"..#lkkkkkkkkkkkkkkkkkkkkkkKKKKKK##..........",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKK##........",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKK##......",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKK#.....",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKK#....",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKKK#...",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKKKK#..",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKKKK#..",
	".#lkkkkkkkkkkkkkkkkkkkkkkkkKKKKKKKKKKKKKK#..",
	".########################################...",
])

# ---------------------------------------------------------------- 偏执泡影（e_paranoia）
# 被大群祈望拖着变形的她：一团冰白的荆棘壳包着两瓣粉肉的「心」，壳顶一圈枯褐王冠，底下是暗紫的触须裙；荆棘尖上泛紫光（强调色）。
portrait("paranoia", {
	"w": (232, 240, 248), "W": (176, 196, 220), "q": (110, 130, 170), "c": (138, 92, 60), "C": (92, 58, 36),
	"p": (246, 196, 176), "P": (220, 140, 130), "d": (170, 90, 100), "k": (54, 40, 70), "K": (34, 24, 48), "v": (90, 60, 120),
}, [
	"............................................",
	"............................................",
	"............................................",
	".............#######...#######..............",
	"...........##ccccccc###cccccccc##...........",
	"..........#cccccccccccccccccccCC#...........",
	"..........#ccccccccccccccccccCCCC#..........",
	"...........##cccccccccccccccCCC##...........",
	"..........#ww##########wwwwww##W#...........",
	".........#wwww#........#wwwwwwWW#...........",
	"........#wwwww#..#......#wwwwwWWW#..........",
	".......#wwwwww#.#w#......#wwwwWWWW#.........",
	"......#wwwwwww##www#......#wwwWWWW#.........",
	".....#wwwwwww#wwwww#.......#wwWWWWW#........",
	"....#wwwwwww#wwwpppp#.......#WWWWWWq#.......",
	"....#wwwwww#wwwppppppp#......#WWWWWq#.......",
	"...#wwwwww#wwwpppppppppp#....#WWWWWq#.......",
	"...#wwwww#wwwppppppppppppp#..#WWWWWq#.......",
	"...#wwww#wwwppHpppppppppPPP#.#WWWWWq#.......",
	"..#wwww#wwwwppppppppppppPPPP##WWWWWqq#......",
	"..#wwww#wwwppppppppppppPPPPPPPWWWWWqq#......",
	"..#www#wwwwpppppppppppPPPPPPPPdWWWWqq#......",
	"..#www#wwwwpppppppppppPPPPPPPPdWWWWqq#......",
	"..#www#wwwwpppppppppPPPPPPPPPddWWWWqq#......",
	"..#www#wwwwwppppppppPPPPPPPPddWWWWWqq#......",
	"..#wwww#wwwwwpppppppPPPPPPPddWWWWWqq#.......",
	"..#wwwww#wwwwwpppppPPPPPPdddWWWWWqqq#.......",
	"...#wwwww#wwwwwwpppPPPPdddWWWWWWqqq#........",
	"...#wwwwww#wwwwwwwwwddddWWWWWWWqqq#.........",
	"....#wwwwwww#wwwwwwwwWWWWWWWWWqqq#..........",
	"....#wwwwwwww##wwwwwWWWWWWWWqqqq#...........",
	".....#wwwwwwwww###WWWWWWWWqqqqq#............",
	"......#AwwwwwwwwwwWWWWWWqqqqqA#.............",
	"......##AAwwwwwwwWWWWWqqqqqAA##.............",
	".....#kk#AAAAAwwWWWqqqAAAAA#kK#.............",
	"....#kkkk##AAAAAAAAAAAAAA##kkKK#............",
	"...#kkkkkkk###AAAAAAAA###kkkkKKK#...........",
	"..#kkkkkkkkkkk##########kkkkkKKKK#..........",
	"..#kkkvvkkkkkkkkkkkkkkkkkkkkkKKKKK#.........",
	".#kkkvvvvkkkkkvvkkkkkkkkvvkkkkKKKKK#........",
	".#kkkkvvkkkkkvvvvkkkkkkvvvvkkkkKKKKK#.......",
	".#kkkkkkkkkkkkvvkkkkkkkkvvkkkkkKKKKKK#......",
	".#kkkkkkkkkkkkkkkkkkkkkkkkkkkkkKKKKKK#......",
	".#####################################......",
])

# ---------------------------------------------------------------- 伊莎玛拉（e_ishar）
# 转化中的少女：银白长发垂到肩，头顶一圈枯枝般的鹿角冠（土黄），红眼，脖子上一条青绿围巾（强调色）；表情空而静。
portrait("ishar", {
	"w": (236, 240, 246), "W": (190, 198, 214), "g": (140, 150, 176), "a": (196, 160, 104),
	"b": (150, 116, 70), "B": (104, 78, 44), "f": (244, 226, 212), "F": (222, 196, 178), "d": (184, 150, 136),
	"e": (210, 40, 50), "E": (120, 20, 30), "t": (60, 200, 190), "T": (30, 130, 130), "k": (40, 44, 60),
}, [
	"............................................",
	"............#.....#.........#.....#.........",
	"...........#a#...#a#.......#a#...#a#........",
	"...........#a#..#aa#.......#aa#..#a#........",
	"..........#aa#.#aab#.#...#.#aab#.#aa#.......",
	"..........#aa##abb#.#a#.#a#.#bbb##aa#.......",
	"..........#aaa#ab#.#aa#.#aa#.#bbb#aaa#......",
	"...........#aaaab##ab###ab##bbbbbba#........",
	"............#aaaaaaabbbbbbbbbbbbbb#.........",
	".............#wwwwwwwwwwwwWWWWWWW#..........",
	"...........##wwwwwwwwwwwwwwWWWWWWW##........",
	"..........#wwwwwwwwwwwwwwwwwWWWWWWWW#.......",
	".........#wwwwwww#########wwWWWWWWWW#.......",
	"........#wwwwww#fffffffffff#WWWWWWWWW#......",
	"........#wwwww#fffffffffffFF#WWWWWWWW#......",
	".......#wwwww#fffffffffffffFF#WWWWWWWg#.....",
	".......#wwwww#fffffffffffffFF#WWWWWWWg#.....",
	".......#wwww#fffffffffffffFFFF#WWWWWWg#.....",
	".......#wwww#ffff###fffff###FF#WWWWWWg#.....",
	".......#wwww#fff#eee#fff#eeE#F#WWWWWWg#.....",
	".......#wwww#fff#eHe#fff#eHE#F#WWWWWWg#.....",
	".......#wwww#ffff###fffff###FF#WWWWWWg#.....",
	".......#wwww#fffffffffffffFFFF#WWWWWWg#.....",
	".......#wwww#ffffffffffdfFFFFF#WWWWWWg#.....",
	".......#wwww#ffffffffffffFFFFF#WWWWWgg#.....",
	".......#wwwww#fffffffffffFFFF#WWWWWWgg#.....",
	".......#wwwww#fffffffdddfFFFF#WWWWWWgg#.....",
	".......#wwwwww#fffffffffFFFF#WWWWWWWgg#.....",
	".......#wwwwwww#ffffffffFFF#WWWWWWWWgg#.....",
	".......#wwwwwwww##ffffffF##WWWWWWWWWgg#.....",
	".......#wwwwwwwwww##fFFF#WWWWWWWWWWWgg#.....",
	"......#wwwwwwwww##tt#FF#tt##WWWWWWWWWgg#....",
	"......#wwwwwwww#ttttt###tttTT#WWWWWWWgg#....",
	".....#wwwwwwww#ttttttttttttTTT#WWWWWWWgg#...",
	".....#wwwwwww#ttttttttttttTTTTT#WWWWWWgg#...",
	"....#wwwwwww#ttttttttttttTTTTTTT#WWWWWWgg#..",
	"....#wwwwwww#tttttttttttTTTTTTTT#WWWWWWgg#..",
	"....#wwwwwww#ttttttttttTTTTTTTTT#WWWWWWgg#..",
	"...#wwwwwwww#tttttttttTTTTTTTTTT#WWWWWWWgg#.",
	"...#wwwwwwww#tttttttTTTTTTTTTTTT#WWWWWWWgg#.",
	"...#wwwwwwww#tttttttTTTTTTTTTTTT#WWWWWWWgg#.",
	"...#wwwwwwww#ttttttTTTTTTTTTTTTT#WWWWWWWgg#.",
	"...#wwwwwwww#tttttTTTTTTTTTTTTTT#WWWWWWWgg#.",
	".##########################################.",
])

# ---------------------------------------------------------------- 伊祖米克（e_izumik）
# 海嗣的母体之一：一顶珠光的水母伞盖（左侧泛青、右侧泛粉），伞顶三圈白环，伞缘垂下一排灰紫触须；伞内透出一点绿光（强调色）。
portrait("izumik", {
	"w": (240, 244, 248), "c": (206, 236, 240), "p": (236, 214, 232), "P": (214, 176, 206), "q": (178, 150, 190),
	"r": (255, 255, 255), "R": (210, 220, 230), "g": (180, 190, 206), "G": (138, 146, 166), "t": (120, 110, 140), "T": (84, 76, 104),
	"m": (210, 150, 190),
}, [
	"............................................",
	"............................................",
	"...................######...................",
	"............####..#rrrrrr#..####............",
	"...........#rrrr#.#rRRRRr#.#rrrr#...........",
	"...........#rRRr#.#rrRRrr#.#rRRr#...........",
	"............####...######...####............",
	".....................##.....................",
	"...................##ww##...................",
	"................###wwwwww###................",
	"..............##wwwwwwwwwwww##..............",
	"............##wwwwwwwwwwwwwwww##............",
	"..........##cwwwwwwwwwwwwwwwwwpp##..........",
	".........#ccwwwwwwwwwwwwwwwwwwppp#..........",
	"........#cccwwwwwwwwwwwwwwwwwwpppP#.........",
	".......#ccccwwwwwwwwwwwwwwwwwwppppP#........",
	"......#cccccwwwwwHwwwwwwwwwwwwppppPP#.......",
	"......#ccccwwwwwwwwwwwwwwwwwwwwpppPPP#......",
	".....#ccccwwwwwwwwwwwwwwwwwwwwwpppPPPq#.....",
	".....#cccwwwwwwwwwwwwwwwwwwwwwwwppPPPq#.....",
	"....#cccwwwwwwwwwwwwAAAwwwwwwwwwppPPPqq#....",
	"....#ccwwwwwwwwwwwwAAAAAwwwwwwwwwpPPPqq#....",
	"....#ccwwwwwwwwwwwwAAAAAwwwwwwwwwpPPPqq#....",
	"....#cwwwwwwwwwwwwwwAAAwwwwwwwwwwpPPPqq#....",
	"....#cwwwwwwwwwwwwwwwwwwwwwwwwwwwppPPqq#....",
	"....#cwwwwwwwwwwwwwwwwwwwwwwwwwwwppPPqq#....",
	"....#mcwwwwwwwwwwwwwwwwwwwwwwwwwwpPPqqm#....",
	"....#mmcwwwwwwwwwwwwwwwwwwwwwwwwppPqqmm#....",
	".....#mmmcwwwwwwwwwwwwwwwwwwwwwppPqqmmm#....",
	".....#mmmmmcwwwwwwwwwwwwwwwwwwpPqqmmmmm#....",
	"......#mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm#.....",
	"......#gg#gg#gg#gg##gg##gg#gg#gg#gG#G#......",
	"......#gg#gg#gg#gg##gg##gg#gG#gG#GG#G#......",
	"......#gg#gg#gG#gG##gG##gG#GG#GG#GG#G#......",
	".......#g#gG#gG#gG##gG##GG#GG#GG#Gt#t#......",
	".......#g#gG#gG#GG##GG##GG#GG#Gt#tt#t#......",
	".......#g#gG#GG#GG##GG##GG#Gt#Gt#tt#t#......",
	".......#g#GG#GG#GG##Gt##Gt#Gt#tt#tt#t#......",
	".......#G#GG#GG#Gt##Gt##Gt#tt#tt#tT#T#......",
	".......#G#GG#Gt#Gt##Gt##tt#tt#tT#tT#T#......",
	".......#G#Gt#Gt#Gt##tt##tt#tT#tT#TT#T#......",
	".......#G#Gt#Gt#tt##tt##tT#tT#TT#TT#T#......",
	".......#G#Gt#tt#tt##tT##tT#TT#TT#TT#T#......",
	".......###############################......",
])

# ---------------------------------------------------------------- 最后的骑士（e_knight）
# 猎潮骑士：全覆面的黑铁头盔（眼缝透一线冰蓝，强调色），盔顶与盔侧垂着蓝黑的长羽饰向右后飘，肩上是厚重的黑甲与破斗篷，右侧露出长枪杆的一截。
portrait("knight_boss", {
	"k": (44, 46, 58), "K": (28, 30, 40), "x": (16, 18, 26), "l": (74, 78, 96), "L": (104, 110, 132),
	"b": (70, 90, 170), "B": (44, 56, 120), "v": (28, 34, 80), "s": (180, 186, 200), "S": (120, 126, 144),
	"c": (34, 28, 44),
}, [
	"............................................",
	"............................................",
	"..................#.........................",
	".................#b#.....##.................",
	"................#bb#....#bb#................",
	"...............#bbb#...#bBB#.........#......",
	"..............#bbBB#..#bBBB#........#s#.....",
	"..............#bbBB#.#bBBBv#.......#ss#.....",
	"..............#bBBB##bBBvv#........#ss#.....",
	".............##bBBBBBBBvvv#........#ss#.....",
	"...........##LlkkkkkkkkkBvv##......#ss#.....",
	"..........#LlkkkkkkkkkkkkkKK#......#ss#.....",
	".........#LlkkkkkkkkkkkkkkKKK#.....#ss#.....",
	"........#LlkkkkkkkkkkkkkkkkKKK#....#ss#.....",
	"........#LlkkkkkkkkkkkkkkkkKKK#....#ss#.....",
	".......#LlkkkkkkkkkkkkkkkkkkKKK#...#ss#.....",
	".......#LlkkkkkkkkkkkkkkkkkkKKK#...#ss#.....",
	".......#Llkkk################KK#...#ss#.....",
	".......#Llkk#AAAAAAAAAAAAAAA#KK#...#ss#.....",
	".......#Llkk#AbbbbbbbbbbbbbA#KK#...#ss#.....",
	".......#Llkkk###############KKK#...#ss#.....",
	".......#LlkkkkkkkkkkkkkkkkkkKKK#...#ss#.....",
	".......#LlkkkkkkkkkkkkkkkkkkKKK#...#ss#.....",
	".......#LlkkkkkkkkkkkkkkkkkkKKK#...#ss#.....",
	"........#LlkkkkkkkkkkkkkkkkKKK#....#ss#.....",
	"........#LlkkkkkkkkkkkkkkkkKKK#....#ss#.....",
	".........#LlkkkkkkkkkkkkkkKKK#.....#sS#.....",
	"..........#LlkkkkkkkkkkkkKKK#......#sS#.....",
	"...........##llkkkkkkkkkKK##.......#sS#.....",
	".........####kkkkkkkkkkkkkk####....#sS#.....",
	".......##LLlkkkkkkkkkkkkkkkKKKK##..#sS#.....",
	".....##LLllkkkkkkkkkkkkkkkkKKKKKK###sS#.....",
	"....#LLlllkkkkkkkkkkkkkkkkkKKKKKKKK#sS#.....",
	"...#LLllllkkkkkkkkkkkkkkkkkkKKKKKKKK#S#.....",
	"..#LLllllllkkkkkkkkkkkkkkkkkkKKKKKKKKKx#....",
	"..#LlllllllkkkkkkkkkkkkkkkkkkKKKKKKKKxx#....",
	".#LlllllllllkkkkkkkkkkkkkkkkkkKKKKKKKxxx#...",
	".#LllllllllkkkkkkkkkkkkkkkkkkkKKKKKKKxxx#...",
	".#LlllllllkkkkkkkccckkkkkkkkkkKKKKKKxxxx#...",
	".#LllllllkkkkkkkcccccckkkkkkkkKKKKKKxxxx#...",
	".#LlllllkkkkkkkccccccckkkkkkkkKKKKKKxxxx#...",
	".#LllllkkkkkkkkcccccccckkkkkkkKKKKKKxxxx#...",
	".#LlllkkkkkkkkkccccccccckkkkkkKKKKKKxxxx#...",
	".########################################...",
])


# ---------------------------------------------------------------- 渲染 / 自检 / 接入
def render(bid):
	pal, rows = PORTRAITS[bid]
	assert len(rows) == N, "%s: %d 行" % (bid, len(rows))
	im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
	px = im.load()
	for y, row in enumerate(rows):
		assert len(row) == N, "%s 第 %d 行长 %d" % (bid, y, len(row))
		for x, ch in enumerate(row):
			if ch == ".":
				continue
			assert ch in pal, "%s (%d,%d) 未知字符 %r" % (bid, x, y, ch)
			assert 1 <= x <= N - 2 and y >= 1, "%s (%d,%d) 进了留边" % (bid, x, y)
			px[x, y] = pal[ch] + (255,)
	one = im.resize((N * 2, N * 2), Image.NEAREST)
	two = one.resize((N * 4, N * 4), Image.NEAREST)
	assert set(one.getdata()) == set(two.getdata())
	return one, two


def contact(hand):
	"""总表：每行一只 Boss —— 名字 / 强调色块 / 1x / 2x（@2x 原尺寸）/ 4x 放大"""
	rowh = 176 + 16
	sheet = Image.new("RGBA", (120 + 88 + 176 + 352 + 60, rowh * len(ORDER) + 8), (24, 26, 34, 255))
	d = ImageDraw.Draw(sheet)
	for i, bid in enumerate(ORDER):
		y = 8 + i * rowh
		one, two = hand[bid]
		d.text((8, y + 4), bid, fill=(255, 255, 255, 255))
		d.text((8, y + 20), NAMES[bid], fill=(200, 210, 220, 255))
		d.rectangle((8, y + 40, 40, y + 56), fill=ACCENT[bid] + (255,))
		x = 120
		d.rectangle((x - 1, y - 1, x + 88, y + 88), outline=ACCENT[bid] + (255,))
		sheet.alpha_composite(one, (x, y))
		x += 88 + 12
		sheet.alpha_composite(two, (x, y))
		x += 176 + 12
		sheet.alpha_composite(one.resize((352, 352), Image.NEAREST).crop((0, 0, 352, 176)), (x, y))
	return sheet


def main():
	png = os.path.join(OUT, "png")
	os.makedirs(png, exist_ok=True)
	hand = {}
	for bid in ORDER:
		one, two = render(bid)
		hand[bid] = (one, two)
		one.save(os.path.join(png, "boss_%s.png" % bid))
		two.save(os.path.join(png, "boss_%s@2x.png" % bid))
		cols = len(set(one.getdata()) - {(0, 0, 0, 0)})
		print("boss_%s.png  %s  %d 色" % (bid, NAMES[bid], cols))
	p = os.path.join(OUT, "portraits_contact.png")
	contact(hand).save(p)
	print("总表", p)
	if "--view" in sys.argv:
		s = int(sys.argv[sys.argv.index("--view") + 1])
		ids = ORDER
		if "--only" in sys.argv:
			ids = [b for b in sys.argv[sys.argv.index("--only") + 1].split(",") if b in hand]
		n = min(5, len(ids))
		rows = (len(ids) + n - 1) // n
		sheet = Image.new("RGBA", (n * (N * s + 8), rows * (N * s + 8)), (60, 60, 70, 255))
		dr = ImageDraw.Draw(sheet)
		for k, bid in enumerate(ids):
			x, y = (k % n) * (N * s + 8) + 4, (k // n) * (N * s + 8) + 4
			sheet.alpha_composite(hand[bid][0].resize((N * s, N * s), Image.NEAREST), (x, y))
			dr.text((x + 2, y + 2), bid, fill=(255, 255, 0, 255))
		vp = os.path.join(OUT, "_view%dx.png" % s)
		sheet.save(vp)
		print("自检图", vp)
	if "--live" in sys.argv:
		os.makedirs(INC, exist_ok=True)
		for bid, (one, two) in hand.items():
			one.save(os.path.join(INC, "boss_%s.png" % bid))
			two.save(os.path.join(INC, "boss_%s@2x.png" % bid))
		print("接入 %d 张到 %s" % (len(hand), INC))


if __name__ == "__main__":
	main()
