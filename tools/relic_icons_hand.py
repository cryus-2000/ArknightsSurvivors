# -*- coding: utf-8 -*-
"""手摆像素藏品图标（docs/11 规格：32×32、透明底、1 px 外轮廓 #080E18、二值 alpha、主体 ≤ 28×28、左上来光）。

与 tools/gen_relic_icons.py 的「模板词汇表」不同：这里每张图标都是逐像素手摆的字符图（每行 32 个字符，一字符一像素），
配一张调色表。物件按藏品名字和含义设计（八音盒是带摇柄的小盒、玻璃小鸟是半透明玻璃鸟、狙击镜是有镜片反光的瞄准镜……），
流派色只做点缀，物件保持本来的颜色。

本文件是入口，含最早的 10 张试做；其余按批放在 tools/relic_icons_hand_<a-h>.py（每个模块一个 register(icon)）。

用法：python tools/relic_icons_hand.py            渲染全部到 art/incoming/_hand_icons/relic_<id>.png
      python tools/relic_icons_hand.py --view 8   另出 build/icons_hand/_hand8x.png（自检用放大图；--only 3,4,5 只看这些）
      python tools/relic_icons_hand.py --contact  另出三方联系表 build/icons_hand/contact.png（最早 10 张：手绘参考 / 模板试做 / 手摆）
      python tools/relic_icons_hand.py --all      全部手摆图标按流派分组的 1x / 3x 联系表 build/icons_all/contact.png
      python tools/relic_icons_hand.py --live     复制到 art/incoming/relic_<id>.png 接入游戏（已有的手绘图标一律不覆盖）
自检：每行 32 字符、字符都在调色表里、四周 2 px 内无像素、alpha 只有 0/255。
"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
INC = os.path.join(ROOT, "art", "incoming")
OUT = os.path.join(INC, "_hand_icons")
TRIAL = os.path.join(INC, "_trial_icons")
BUILD = os.path.join(ROOT, "build", "icons_hand")
ALL = os.path.join(ROOT, "build", "icons_all")
DATA = os.path.join(ROOT, "game", "data", "relics.json")
PARTS = "abcdefgh"

O = (0x08, 0x0E, 0x18)      # 轮廓
H = (0xE6, 0xFA, 0xFF)      # 冰白高光
I = (0x9F, 0xE3, 0xF0)      # 冰蓝高光

ICONS = {}


def icon(rid, name, pal, rows):
    pal = dict(pal)
    pal["#"] = O
    pal["H"] = H
    pal["I"] = I
    ICONS[rid] = (name, pal, rows)


# ---------------------------------------------------------------- 2 凉拌海草（流派 A，红色点缀 = 辣椒丝）
# 一碗堆得冒尖的海草，白瓷碗带一圈蓝边，碗沿露出两根辣椒丝。
icon(2, "凉拌海草", {
    "s": (127, 207, 160), "m": (62, 140, 104), "d": (30, 74, 66),
    "r": (224, 80, 106), "R": (179, 38, 62),
    "w": (232, 238, 244), "g": (169, 180, 194), "k": (111, 124, 140), "K": (58, 70, 88),
    "u": (74, 122, 224),
}, [
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "..............###.....###.......",
    "............##smm#..##mmd#......",
    "..........##ddssm#.#dssmm##.....",
    ".........#mmdddss##dddssmm#.....",
    "........#ssmmdddssmmdddssm#.....",
    ".......#ddssmmdddssmmdddssm#....",
    "......#mdddssmmdddssrRdddssm#...",
    ".....#smmdddssmmdddssmmdddss#...",
    "....#dssmmddRrsmmdddssmmddd#....",
    "....#ddssmmdRRssmmdddssmmdd#....",
    "...##dddddddddddddddddddddd##...",
    "...#wHwwwwwwwwwwwwwwwwwwwwwgg#..",
    "...#wwwwwwwwwwwwwwwwwwwwwwggg#..",
    "...#wwwwwwwwwwwwwwwwwwwwwgggg#..",
    "...#uuuuuuuuuuuuuuuuuuuuuuuuu#..",
    "....#wwwwwwwwwwwwwwwwwwwggggk#..",
    "....#gwwwwwwwwwwwwwwwwgggggk#...",
    ".....#ggwwwwwwwwwwwwggggggkk#...",
    "......#gggggggggggggggggkkk#....",
    ".......#ggggggggggggggkkk#......",
    "........##gggggggggkkk##........",
    "..........####kkkkK###..........",
    ".............#KKKKK#............",
    "..............#####.............",
    "................................",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 80 海程（流派 B，蓝色点缀 = 罗盘面）
# 一只黄铜航海罗盘：顶上有提环，蓝色盘面，红白指针朝北，东西南各一粒刻度。
icon(80, "海程", {
    "b": (255, 227, 154), "B": (232, 184, 74), "D": (138, 94, 31),
    "F": (63, 122, 148), "f": (46, 76, 110), "e": (22, 35, 58),
    "r": (224, 80, 106), "n": (230, 250, 255),
}, [
    "................................",
    "................................",
    "..............####..............",
    ".............#b..D#.............",
    ".............#######............",
    "...........#bbbbbbbbb#..........",
    ".........#bHHbbbbbbbbbb#........",
    "........#bbbbbeeeeeBBBBB#.......",
    ".......#bbbbeFFFrFFFeBBBB#......",
    "......#bbbeFFFFrrrFFFFeBBB#.....",
    "......#bbeFFFFFrrrFFFFFeBB#.....",
    ".....#bbbeFFFFFrrrFFFFFeBBB#....",
    ".....#bbeFFFFFFrrrFFFfffeBB#....",
    "....#bbbeFFFFFFrrrFFffffeBBB#...",
    "....#bbeFFFFFFFrrrFffffffeBB#...",
    "....#bbeFFFFFFFrrrfffffffeBB#...",
    "....#bBenFFFFFFBBBffffffneBB#...",
    "....#bBeFFFFFFFnnnfffffffeBB#...",
    "....#bBeFFFFFFFnnnfffffffeBB#...",
    "....#BBBeFFFFFfnnnffffffeBBB#...",
    ".....#BBeFFFFffnnnffffffeBD#....",
    ".....#BBBeFFfffnnnfffffeBDD#....",
    "......#BBeFffffnnnfffffeDD#.....",
    "......#BBBeffffnnnffffeDDD#.....",
    ".......#BBBBefffnfffeDDDD#......",
    "........#BBBBBeeeeeDDDDD#.......",
    ".........#BBBBBBDDDDDDD#........",
    "...........#DDDDDDDDD#..........",
    ".............#######............",
    "................................",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 86 高卢银行支票（流派 C，紫色点缀 = 印章）
# 一张略斜的纸质支票：左侧带撕孔的存根、三行字迹、右下紫色印章、左下签名。
icon(86, "高卢银行支票", {
    "p": (246, 236, 208), "c": (220, 205, 170), "k": (168, 144, 106),
    "i": (111, 124, 140), "j": (58, 70, 88),
    "v": (201, 166, 255), "V": (138, 92, 214), "u": (90, 52, 160),
    "g": (232, 184, 74),
}, [
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "......#######################...",
    "......#pHpp#pppppppppppppppp#...",
    "......#pppp.pppppppppppppppc#...",
    "......#pppp#pppppppppppppppc#...",
    "......#ppjp.ppiiiiiiiippiipc#...",
    ".....#pppp#ppppppppppppppcc#....",
    ".....#pppp.piiiiiiipppppppc#....",
    ".....#pppp#pppppppppppppppc#....",
    ".....#pjpp.piiiiiiiiiiiiipc#....",
    ".....#pppp#ppppppppppppppcc#....",
    "....#pppp.ppppppppp##vv##c#.....",
    "....#pppp#ppppppppp#vVVv#c#.....",
    "....#pppp.pp#jj#ppp#VuuV#c#.....",
    "....#ppjp#p#ppp#j#p#vVVv#c#.....",
    "....#pppp.pj#ppp##p##vv##c#.....",
    "....#cccc#cccccccccccccckk#.....",
    "....#######################.....",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 10 独奏八音盒（流派 G，金色点缀 = 摇柄与音符）
# 木盒掀开盖子，盖子内衬红绒，盒里露出钢齿梳和黄铜滚筒，右侧伸出金摇柄，右上飘一个金音符。
icon(10, "独奏八音盒", {
    "w": (196, 140, 80), "W": (150, 98, 50), "x": (96, 60, 30),
    "r": (179, 38, 62), "R": (110, 26, 42),
    "b": (255, 227, 154), "B": (232, 184, 74), "D": (138, 94, 31),
    "s": (199, 207, 217), "S": (111, 124, 140), "e": (22, 35, 58),
}, [
    "................................",
    "................................",
    "......................##........",
    ".....................#bB#.......",
    ".....................#b#BB#.....",
    ".....................#b#.##.....",
    ".....................#b#........",
    "...................####B#.......",
    "..................#bBBBB#.......",
    "..................#BBBDD#.......",
    ".....####################.......",
    "....#wwrrrrrrrrrrrrrrrrww#......",
    "....#wrRRRRRRRRRRRRRRRRrw#......",
    "...#wwrRRRRRRRRRRRRRRRRRwW#.....",
    "...#WWWWWWWWWWWWWWWWWWWWWW#.....",
    "...#eeeeeeeeeeeeeeeeeeeeee#.....",
    "...#esssssssssssssssssssse#.....",
    "...#eSeSeSeSeSeSeSeSeSeSee#.....",
    "...#ebBbBbBbBbBbBbBbBbBbBe####..",
    "...#eBDBDBDBDBDBDBDBDBDBDe#bB#..",
    "...########################bB#..",
    "...#wwwwwwwwwwwwwwwwwwwwwW#DB#..",
    "...#wwwwwwwww#BB#wwwwwwwWW###...",
    "...#wwwwwwwww#bB#wwwwwwWWW#.....",
    "...#WwwwwwwwwwwwwwwwwwWWWW#.....",
    "...#WWwwwwwwwwwwwwwwwWWWWW#.....",
    "...#xWWWWWWWWWWWWWWWWWWWWx#.....",
    "...########################.....",
    "................................",
    "................................",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 6 皮特水果什锦（无流派）
# 一只罐头玻璃瓶，锡盖，瓶里塞满各色果块：樱桃、橙瓣、葡萄、蓝莓、菠萝块。
icon(6, "皮特水果什锦", {
    "t": (199, 207, 217), "T": (111, 124, 140), "e": (58, 70, 88),
    "y": (255, 227, 154), "Y": (232, 184, 74),
    "r": (224, 80, 106), "R": (179, 38, 62),
    "o": (255, 138, 61), "O": (200, 90, 30),
    "g": (154, 203, 122), "G": (79, 138, 74),
    "v": (138, 92, 214), "V": (90, 52, 160),
    "a": (230, 250, 255), "c": (159, 227, 240),
}, [
    "................................",
    "................................",
    "................................",
    "................................",
    "........##############..........",
    ".......#tHtttttttttTTT#.........",
    ".......#tttttttttttTTT#.........",
    ".......#TTTTTTTTTTTTee#.........",
    "........#eeeeeeeeeeee#..........",
    "......###tttttttttttt###........",
    ".....#aayyyyyyyeyyggyyyc#.......",
    ".....#aayyyyyyeyygGggyycc#......",
    ".....#aayyyyyeyyygGGggycc#......",
    ".....#aayyrrrryyyyGGgyycc#......",
    ".....#aayrrrrrrrryyyyyycc#......",
    ".....#aayrHrrrrrrryyyyycc#......",
    ".....#aayrrrRRrRrryYYyycc#......",
    ".....#aayyrrRyyRRyYYYyycc#......",
    ".....#aayyyyyyyyyyYYYvvcc#......",
    ".....#aayyoooyyyyyyyvVvcc#......",
    ".....#aayooooOyyyyyvVVvcc#......",
    ".....#aayoooOOOyyyyyvVycc#......",
    ".....#aayyOOOOOoyyyyyyycc#......",
    ".....#aayyyOOOoyyyyyyyycc#......",
    ".....#aayyyyyyyyyyyyyyycc#......",
    "......#aayyyyyyyyyyyyyycc#......",
    ".......#ccccccccccccccc#........",
    "........###############.........",
    "................................",
    "................................",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 87 《第二经济改革法》（流派 C，紫色点缀 = 封面与书签带）
# 一本厚厚的深紫封面法典，封面压一枚金币纹章，底下露出一条紫书签带，右侧和下方露出书页。
icon(87, "《第二经济改革法》", {
    "v": (120, 78, 196), "V": (84, 48, 150), "u": (50, 26, 96),
    "l": (201, 166, 255),
    "b": (255, 227, 154), "B": (232, 184, 74), "D": (138, 94, 31),
    "p": (246, 236, 208), "c": (220, 205, 170), "k": (168, 144, 106),
}, [
    "................................",
    "................................",
    "................................",
    "................................",
    "......####################......",
    ".....#uvvvvvvvvvvvvvvvvvvv#.....",
    ".....#uvHlllllllllllllllvv#.....",
    ".....#uvlvvvvvvvvvvvvvvllv##....",
    ".....#uvlvvvvvvvvvvvvvvllv#p#...",
    ".....#uvlvvvvvvvvvvvvvvllv#p#...",
    ".....#uvlvvvvv####vvvvvllV#p#...",
    ".....#uvlvvvv#bbBB#vvvvllV#p#...",
    ".....#uvlvvv#bbbBBB#vvvllV#p#...",
    ".....#uvlvvv#bBDDBB#vvvllV#p#...",
    ".....#uvlvvv#bBDDBB#vvvllV#p#...",
    ".....#uvlvvv#BBBBBD#vvvllV#p#...",
    ".....#uvlvvvv#BBBD#vvvvllV#c#...",
    ".....#uvlvvvvv####vvvvvllV#c#...",
    ".....#uvlvvvvvvvvvvvvvvllV#c#...",
    ".....#uvlvvvvvvvvvvvvvvllV#c#...",
    ".....#uvlvvvvvvvvvvvvvvllV#c#...",
    ".....#uvlllllllllllllllllV#c#...",
    ".....#uVVVVVVVVVVVVVVVVVVV#c#...",
    ".....######################c#...",
    "......#ppppppppp#ll#pppppck#....",
    "......#cccccccc#llV#ccccckk#....",
    "......#kkkkkkkk#lVV#kkkkkkk#....",
    ".......#########uVV########.....",
    "................#VVu#...........",
    ".................###............",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 11 源石鸢尾花（流派 G，金色点缀 = 花心的金须）
# 一朵花瓣结晶化的鸢尾：三片直立的棱角旗瓣、三片下垂的垂瓣，花心一撮金须，绿茎带一片叶。
icon(11, "源石鸢尾花", {
    "L": (201, 166, 255), "V": (138, 92, 214), "v": (84, 48, 150), "u": (46, 24, 80),
    "G": (255, 196, 107), "g": (232, 184, 74),
    "s": (127, 207, 160), "S": (79, 138, 74), "d": (42, 78, 46),
}, [
    "................................",
    "................................",
    "...............##...............",
    "..............#LV#..............",
    "..............#LVv#.............",
    ".........##..#LLVv#..##.........",
    "........#LV#.#LVVv#.#VV#........",
    "........#LVv#LLVVv#.#Vvv#.......",
    ".......#LLVv#LVVvv#.#VVvv#......",
    ".......#LLVv#LVVvv##VVvvu#......",
    "......#LLVVv#LVVvvv#VVvvu#......",
    "......#LLVVvv#LVVvv#VVvvu#......",
    "......#LVVvvv#LVVvv#Vvvuu#......",
    ".......#LVVvv##GgGg#Vvvu#.......",
    "........#VVv##GgHGg##vu#........",
    ".....###VVv#LVgGgGgV#vu###......",
    "....#LVVVVv#LVVGgGvv#vvvvV#.....",
    "...#LLVVVvv#LVVVvvvv#VvvvvV#....",
    "...#LLVVvvv#LVVVvvvv#Vvvvuu#....",
    "...#LVVvvuu#LVVVvvvu#Vvvuuu#....",
    "....#VVvvu##LVVvvvuu##vvuu#.....",
    ".....##vu##.#LVvvvu#.##uu#......",
    ".......##...#LVvvvu#..###.......",
    "............#LVvvuu#............",
    ".............#Vvuu#.............",
    "..............#SS#..............",
    ".............#sSS#..............",
    "...........##sSS#...............",
    "..........#ssSSd#...............",
    "...........#####................",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 8 蓝色丝巾（无流派）
# 一条打了松结的蓝丝巾：结在中间，左上一个翻起的环，两条垂尾朝下，尾端有流苏缺口，丝面带一道亮边。
icon(8, "蓝色丝巾", {
    "l": (191, 216, 255), "m": (74, 122, 224), "d": (40, 70, 150), "e": (24, 40, 96),
}, [
    "................................",
    "................................",
    "................................",
    "..........##########............",
    "........##llllllllmm##..........",
    "......##llllmmmmmmmmmm##........",
    ".....#lHlmmm######mmmmmm#.......",
    "....#llmm##......##mmmmdd#......",
    "....#lmm#..........#mmmdd#......",
    "....#lmm#..........#mmddd#......",
    "....#lmm#..........#mmdd#.......",
    ".....#mm##.......##mmdd#........",
    "......#mmm##...##mmddd#.........",
    ".......#mmmm#.#mmdddd#..........",
    ".........#llmmmmmmd##...........",
    "........#lHlmmmmmmdd#...........",
    "........#llmmmmmmmdd#...........",
    ".........#mmmmmmmdd#............",
    "........#lmmm##mmdd#............",
    ".......#lmmmd#.#mdd#............",
    "......#lmmmd#..#mddd#...........",
    "......#lmmmd#..#mmdd#...........",
    ".....#lmmmd#....#mdd#...........",
    ".....#lmmmd#....#mddd#..........",
    ".....#lmmdd#....#mmdd#..........",
    ".....#lmmdd#.....#mdd#..........",
    ".....#mmdd#......#mddd#.........",
    ".....#e#e#.......#mmdd#.........",
    ".....###.#........#d#d#.........",
    "..................###.#.........",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 104 Scout的狙击镜（流派 G，金色点缀 = 物镜圈）
# 3/4 视角的狙击镜：大物镜朝向左下，镜片蓝色带一道斜反光，镜筒向右上延伸到目镜，筒上一颗调节旋钮，金色物镜圈。
icon(104, "Scout的狙击镜", {
    "s": (169, 180, 194), "S": (111, 124, 140), "k": (58, 70, 88), "e": (30, 38, 52),
    "b": (255, 227, 154), "B": (232, 184, 74), "D": (138, 94, 31),
    "F": (63, 122, 148), "f": (46, 76, 110), "n": (22, 35, 58),
}, [
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "..............#####.............",
    "..............#sSk#.............",
    "...#######....#sSk#.............",
    "...#FFFBs#....#sSk#...#######...",
    "...#FHFBs#..#.#sSk##..#ssssn#...",
    "...#HFFBs##############ssssn#...",
    "...#FFFBs#ss#ssssss#ss#ssSSn#...",
    "...#FFfBS#ss#ssssss#ss#sSSSn#...",
    "...#FffBS#SS#SSSSSS#SS#SSSSn#...",
    "...#fffDS#SS#SSSSSS#SS#SSSkn#...",
    "...#ffnDS#SS#SSSSSS#SS#SSkkn#...",
    "...#fnnDk#kk#kkkkkk#kk#Skkkn#...",
    "...#nnnDk##############kkkkn#...",
    "...#nnnDk#..#.#sSk##..#kkkkn#...",
    "...#nnnDk#....#sSk#...#######...",
    "...#######....#sSk#.............",
    "..............#sSk#.............",
    "..............#####.............",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
])

# ---------------------------------------------------------------- 13 玻璃小鸟（无流派）
# 一只侧身朝左的玻璃小鸟摆件：圆头、翘尾、橙喙，身子通透（内里更亮、右下有一圈暗边），立在一只小玻璃底座上。
icon(13, "玻璃小鸟", {
    "w": (230, 250, 255), "c": (159, 228, 240), "d": (83, 190, 212), "k": (63, 122, 148),
    "o": (255, 138, 61), "O": (200, 90, 30), "e": (22, 35, 58),
    "W": (255, 255, 255),
}, [
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "..........######..........##....",
    ".........#wwwwcc#........#cd#...",
    "........#wWWwwccc#......#ccdk#..",
    ".......#wWwwwwcccd#....#cccdk#..",
    "....##.#wwwwwecccd#...#ccccdk#..",
    "...#oo##wwwwwwcccd#..#ccccddk#..",
    "..#ooOOOwwwwwccccd#.#cccccdkk#..",
    "...#OO##wwwwwcccccd##ccccddkk#..",
    "....##.#wwwwwcccccccccccdddk#...",
    ".......#wwwwwccccccccccddddk#...",
    ".......#wwwwwccwwwwcccdddddk#...",
    ".......#wwwwwcwWWwwwccddddk#....",
    "........#wwwwcwWwwwwcccdddk#....",
    "........#wwwwccwwwwwccddddk#....",
    ".........#wwwccccwwwccdddk#.....",
    ".........#wwwwccccccccdddk#.....",
    "..........#wwwwccccccdddk#......",
    "...........#wwwwccccdddk#.......",
    "............##ccccccdkk#........",
    "..............##ddddk##.........",
    "...............#kk#kk#..........",
    "...........#####cc#cc#####......",
    "..........#wwwwwccccccccdk#.....",
    "..........#cccccccccddddkk#.....",
    "...........###############......",
    "................................",
    "................................",
])


# ---------------------------------------------------------------- 分批模块
import importlib
for _part in PARTS:
    try:
        _mod = importlib.import_module("relic_icons_hand_" + _part)
    except ImportError:
        continue
    _mod.register(icon)


# ---------------------------------------------------------------- 渲染 / 自检
def render(rid):
    name, pal, rows = ICONS[rid]
    assert len(rows) == 32, "%s: %d 行" % (rid, len(rows))
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    px = im.load()
    for y, row in enumerate(rows):
        assert len(row) == 32, "%s 第 %d 行长 %d" % (rid, y, len(row))
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            assert ch in pal, "%s (%d,%d) 未知字符 %r" % (rid, x, y, ch)
            assert 2 <= x <= 29 and 2 <= y <= 29, "%s (%d,%d) 进了 2 px 留边" % (rid, x, y)
            px[x, y] = pal[ch] + (255,)
    return im


def contact(hand):
    """三方联系表：每行一个藏品 —— 手绘参考（同类物件，有则放） / 模板试做 / 手摆，各 1x 与 4x。"""
    REF = {2: 1, 80: None, 86: 100, 10: None, 6: 1, 87: 15, 11: 105, 8: 112, 104: 199, 13: 118}
    order = [2, 80, 86, 10, 6, 87, 11, 8, 104, 13]
    cell1, cell4, pad = 36, 132, 6
    colw = cell1 + cell4 + pad * 3
    W = 72 + colw * 3
    rowh = cell4 + pad * 2
    sheet = Image.new("RGBA", (W, 28 + rowh * len(order)), (40, 44, 54, 255))
    dr = ImageDraw.Draw(sheet)
    for c, t in enumerate(["hand-made ref", "template trial", "hand-placed"]):
        dr.text((72 + colw * c + pad, 8), t, fill=(220, 225, 232, 255))
    for r, rid in enumerate(order):
        y0 = 28 + rowh * r
        dr.text((6, y0 + 4), "%d" % rid, fill=(220, 225, 232, 255))
        refid = REF[rid]
        srcs = [os.path.join(INC, "relic_%d.png" % refid) if refid else None,
                os.path.join(TRIAL, "relic_%d.png" % rid), None]
        for c in range(3):
            x0 = 72 + colw * c + pad
            if c == 2:
                im = hand[rid]
            elif srcs[c] and os.path.exists(srcs[c]):
                im = Image.open(srcs[c]).convert("RGBA")
            else:
                dr.text((x0, y0 + pad + 50), "(none)", fill=(140, 146, 158, 255))
                continue
            sheet.alpha_composite(im, (x0 + 2, y0 + pad + 2))
            sheet.alpha_composite(im.resize((128, 128), Image.NEAREST), (x0 + cell1 + pad, y0 + pad + 2))
            if c == 0 and refid:
                dr.text((x0, y0 + pad + 40), "ref %d" % refid, fill=(140, 146, 158, 255))
    return sheet


def lanes_of():
    """id → 流派串（relics.json；没有流派记 '-'）"""
    import json
    out = {}
    for it in json.load(open(DATA, encoding="utf-8"))["items"]:
        out[it["id"]] = "".join(it.get("lanes", [])) or "-"
    return out


def contact_all(hand):
    """全部手摆图标，按流派分组，每张 1x + 3x 并排，下面写编号。"""
    lanes = lanes_of()
    groups = {}
    for rid in hand:
        groups.setdefault(lanes.get(rid, "-")[0], []).append(rid)
    order = [k for k in "ABCDEFGH-" if k in groups]
    cols = 8
    cw, ch = 36 + 100, 112
    rows_total = sum((len(groups[k]) + cols - 1) // cols for k in order)
    sheet = Image.new("RGBA", (cols * cw + 16, rows_total * ch + 22 * len(order) + 16), (40, 44, 54, 255))
    dr = ImageDraw.Draw(sheet)
    y = 8
    for k in order:
        dr.text((8, y), "lane %s  (%d)" % (k, len(groups[k])), fill=(220, 225, 232, 255))
        y += 22
        ids = sorted(groups[k])
        for i, rid in enumerate(ids):
            x = 8 + (i % cols) * cw
            yy = y + (i // cols) * ch
            im = hand[rid]
            sheet.alpha_composite(im, (x, yy))
            sheet.alpha_composite(im.resize((96, 96), Image.NEAREST), (x + 36, yy))
            dr.text((x, yy + 40), "%d" % rid, fill=(220, 225, 232, 255))
        y += ((len(ids) + cols - 1) // cols) * ch
    return sheet


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    hand = {}
    for rid in ICONS:
        im = render(rid)
        hand[rid] = im
        im.save(os.path.join(OUT, "relic_%d.png" % rid))
        cols = len(set(im.getdata()) - {(0, 0, 0, 0)})
        print("relic_%d.png  %s  %d 色" % (rid, ICONS[rid][0], cols))
    print("共 %d 张" % len(hand))
    if "--view" in sys.argv:
        s = int(sys.argv[sys.argv.index("--view") + 1])
        ids = list(ICONS)
        if "--only" in sys.argv:
            only = [int(v) for v in sys.argv[sys.argv.index("--only") + 1].split(",")]
            ids = [r for r in only if r in ICONS]
        n = 5
        rows = (len(ids) + n - 1) // n
        sheet = Image.new("RGBA", (n * (32 * s + 8), rows * (32 * s + 8)), (60, 60, 70, 255))
        dr = ImageDraw.Draw(sheet)
        for k, rid in enumerate(ids):
            x, y = (k % n) * (32 * s + 8) + 4, (k // n) * (32 * s + 8) + 4
            sheet.alpha_composite(hand[rid].resize((32 * s, 32 * s), Image.NEAREST), (x, y))
            dr.text((x + 2, y + 2), "%d" % rid, fill=(255, 255, 255, 255))
        sheet.save(os.path.join(BUILD, "_hand%dx.png" % s))
    if "--contact" in sys.argv:
        p = os.path.join(BUILD, "contact.png")
        contact(hand).save(p)
        print("联系表", p)
    if "--all" in sys.argv:
        os.makedirs(ALL, exist_ok=True)
        p = os.path.join(ALL, "contact.png")
        contact_all(hand).save(p)
        print("全表", p)
    if "--live" in sys.argv:
        n = 0
        for rid, im in hand.items():
            dst = os.path.join(INC, "relic_%d.png" % rid)
            if os.path.exists(dst):
                print("已有，跳过", dst)
                continue
            im.save(dst)
            n += 1
        print("接入 %d 张到 %s" % (n, INC))


if __name__ == "__main__":
    main()
