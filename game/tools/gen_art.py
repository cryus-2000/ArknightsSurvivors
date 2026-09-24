"""程序生成原创像素素材（海底地形、海嗣、特效、掉落物）。
所有图按"美术像素"尺寸绘制，游戏里以 2 倍放大、最近邻采样显示。"""
from PIL import Image, ImageDraw
import math, random, os

OUT = os.path.join(os.path.dirname(__file__), "..", "art", "px")
os.makedirs(OUT, exist_ok=True)
OUTLINE = (8, 14, 24, 255)


def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def outline(im, col=OUTLINE):
    w, h = im.size
    src = im.load()
    out = im.copy()
    o = out.load()
    for x in range(w):
        for y in range(h):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                        o[x, y] = col
                        break
    return out


def silhouette(im):
    w, h = im.size
    out = new(w, h)
    s, o = im.load(), out.load()
    for x in range(w):
        for y in range(h):
            if s[x, y][3] > 0:
                o[x, y] = (255, 255, 255, 255)
    return out


def strip(frames):
    w, h = frames[0].size
    s = new(w * len(frames), h)
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


def save_enemy(name, frames):
    frames = [outline(f) for f in frames]
    strip(frames).save(f"{OUT}/{name}.png")
    strip([silhouette(f) for f in frames]).save(f"{OUT}/{name}_white.png")


def px(d, pts, c):
    for p in pts:
        d.point(p, fill=c)


# ---------------------------------------------------------------- 海嗣
def drifter(frame):
    # 小型游荡体：半透明伞状头 + 飘动的触须
    im = new(14, 16); d = ImageDraw.Draw(im)
    body, shade, hi = (63, 184, 168), (37, 122, 115), (150, 235, 215)
    d.ellipse((2, 1, 11, 9), fill=body)
    d.rectangle((2, 6, 11, 8), fill=shade)
    d.point((4, 3), fill=hi); d.point((5, 2), fill=hi); d.point((6, 2), fill=hi)
    off = [0, 1][frame]
    for i, x in enumerate((3, 6, 9)):
        for y in range(9, 14):
            xx = x + ((y + i + off) % 3 == 0) * (1 if i % 2 else -1)
            d.point((xx, y), fill=shade)
    d.point((5, 5), fill=(255, 233, 138)); d.point((8, 5), fill=(255, 233, 138))
    return im


def dart(frame):
    # 疾游体：梭形带尾鳍
    im = new(16, 10); d = ImageDraw.Draw(im)
    body, shade, hi = (90, 208, 255), (45, 120, 170), (200, 245, 255)
    d.ellipse((4, 2, 14, 7), fill=body)
    d.line((5, 6, 13, 6), fill=shade)
    t = [0, 1][frame]
    d.polygon([(5, 4), (1, 1 + t), (1, 7 - t)], fill=shade)
    d.line((7, 3, 11, 3), fill=hi)
    d.point((12, 4), fill=(255, 233, 138))
    return im


def crawler(frame):
    # 爬行体：多足、背甲
    im = new(18, 16); d = ImageDraw.Draw(im)
    body, shade, hi = (138, 106, 224), (80, 58, 150), (190, 170, 250)
    o = [0, 1][frame]
    for i, x in enumerate((3, 6, 11, 14)):
        dy = o if i % 2 else 1 - o
        d.line((x, 10, x + (-1 if x < 9 else 1), 13 + dy), fill=shade)
    d.ellipse((2, 3, 15, 12), fill=body)
    d.arc((2, 3, 15, 12), 20, 160, fill=shade)
    d.line((5, 5, 11, 5), fill=hi); d.point((4, 6), fill=hi)
    d.point((6, 8), fill=(255, 120, 150)); d.point((11, 8), fill=(255, 120, 150))
    return im


def shell(frame):
    # 甲壳体：厚重甲片
    im = new(22, 20); d = ImageDraw.Draw(im)
    body, shade, hi, plate = (61, 85, 184), (35, 48, 110), (130, 155, 235), (90, 115, 210)
    o = [0, 1][frame]
    for x in (4, 8, 13, 17):
        d.line((x, 14, x, 17 + (o if x in (4, 13) else 1 - o)), fill=shade)
    d.ellipse((1, 3, 20, 16), fill=body)
    for i, x0 in enumerate((4, 9, 14)):
        d.arc((x0 - 2, 4, x0 + 5, 13), 180, 360, fill=plate)
    d.line((5, 5, 15, 5), fill=hi)
    d.rectangle((2, 12, 19, 14), fill=shade)
    d.point((8, 10), fill=(255, 233, 138)); d.point((13, 10), fill=(255, 233, 138))
    return im


def boss(frame):
    # 潮渊巨噬体：巨大口器 + 触手环
    im = new(52, 48); d = ImageDraw.Draw(im)
    body, shade, hi, mouth = (138, 36, 88), (80, 16, 50), (200, 90, 140), (30, 5, 20)
    o = frame
    for k in range(8):
        a = k / 8 * math.tau + o * 0.2
        x0, y0 = 26 + math.cos(a) * 14, 26 + math.sin(a) * 12
        pts = []
        for s in range(8):
            r = 14 + s * 1.6
            aa = a + math.sin(s * 0.9 + o * 1.5 + k) * 0.18
            pts.append((26 + math.cos(aa) * r * 1.1, 26 + math.sin(aa) * r * 0.9))
        d.line(pts, fill=shade, width=3)
    d.ellipse((9, 8, 43, 40), fill=body)
    d.ellipse((12, 10, 38, 26), fill=(160, 50, 105))
    d.ellipse((17, 22, 35, 36), fill=mouth)
    for tx in range(19, 34, 3):
        d.polygon([(tx, 23), (tx + 1, 23), (tx + 0.5, 27)], fill=(240, 220, 230))
        d.polygon([(tx + 1, 35), (tx + 2, 35), (tx + 1.5, 31)], fill=(240, 220, 230))
    for ex, ey in ((16, 16), (22, 13), (30, 13), (36, 16)):
        d.rectangle((ex, ey, ex + 1, ey + 1), fill=(255, 220, 90))
    d.line((14, 12, 20, 10), fill=hi)
    return im


for name, fn in (("drifter", drifter), ("dart", dart), ("crawler", crawler), ("shell", shell), ("boss", boss)):
    save_enemy(name, [fn(0), fn(1)])


# ---------------------------------------------------------------- 地形
random.seed(7)
TILE = 16
base_cols = [(40, 86, 104), (42, 89, 107), (38, 83, 101), (43, 91, 108)]
tiles = []
for v in range(4):
    im = Image.new("RGBA", (TILE, TILE), base_cols[v] + (255,))
    d = ImageDraw.Draw(im)
    for _ in range(10 + v * 3):
        x, y = random.randrange(TILE), random.randrange(TILE)
        c = random.choice([(48, 98, 114), (34, 76, 94), (52, 104, 118)])
        d.point((x, y), fill=c + (255,))
    if v == 3:  # 沙纹
        for y in (4, 10):
            for x in range(2, 14):
                if (x + y) % 4 < 2:
                    d.point((x, y + (x % 3 == 0)), fill=(50, 100, 114, 255))
    tiles.append(im)
strip(tiles).save(f"{OUT}/tiles.png")

# 装饰：海草(2帧)、珊瑚、贝壳、石块
def seaweed(f):
    im = new(10, 16); d = ImageDraw.Draw(im)
    for i, x in enumerate((2, 5, 7)):
        pts = [(x + math.sin((15 - y) * 0.5 + f * 1.2 + i) * 1.3, y) for y in range(15, 3 + i * 2, -1)]
        d.line(pts, fill=(40, 130, 100) if i != 1 else (60, 160, 115))
    return outline(im, (6, 20, 22, 255))

def coral():
    im = new(14, 12); d = ImageDraw.Draw(im)
    c1, c2 = (190, 80, 120), (235, 130, 160)
    d.line((7, 11, 7, 4), fill=c1); d.line((7, 7, 3, 3), fill=c1); d.line((7, 6, 11, 2), fill=c1)
    d.line((3, 3, 3, 1), fill=c2); d.line((11, 2, 12, 1), fill=c2); d.line((7, 4, 7, 2), fill=c2)
    d.line((5, 11, 9, 11), fill=(120, 50, 80))
    return outline(im, (20, 10, 20, 255))

def shellprop():
    im = new(8, 6); d = ImageDraw.Draw(im)
    d.pieslice((0, 0, 7, 9), 180, 360, fill=(220, 200, 170))
    for x in (2, 4, 6):
        d.line((4, 5, x, 1), fill=(180, 150, 120))
    return outline(im)

def rock():
    im = new(12, 8); d = ImageDraw.Draw(im)
    d.ellipse((0, 1, 11, 8), fill=(40, 60, 75)); d.ellipse((2, 1, 8, 5), fill=(60, 85, 100))
    return outline(im)

strip([seaweed(0), seaweed(1)]).save(f"{OUT}/seaweed.png")
coral().save(f"{OUT}/coral.png")
shellprop().save(f"{OUT}/shell_prop.png")
rock().save(f"{OUT}/rock.png")


# ---------------------------------------------------------------- 掉落物
def gem(c1, c2):
    im = new(7, 9); d = ImageDraw.Draw(im)
    d.polygon([(3, 0), (6, 4), (3, 8), (0, 4)], fill=c1)
    d.line((3, 1, 1, 4), fill=c2); d.point((3, 2), fill=(255, 255, 255))
    return outline(im)

gem((80, 230, 170), (180, 255, 225)).save(f"{OUT}/gem_small.png")
gem((130, 130, 255), (210, 210, 255)).save(f"{OUT}/gem_big.png")

im = new(9, 12); d = ImageDraw.Draw(im)  # 灯油瓶
d.rectangle((3, 0, 5, 2), fill=(120, 80, 50)); d.ellipse((0, 2, 8, 11), fill=(255, 170, 60))
d.ellipse((2, 4, 6, 9), fill=(255, 225, 120)); d.point((3, 5), fill=(255, 255, 230))
outline(im).save(f"{OUT}/oil.png")

im = new(14, 11); d = ImageDraw.Draw(im)  # 藏品箱
d.rectangle((0, 3, 13, 10), fill=(120, 75, 35)); d.rectangle((0, 0, 13, 4), fill=(150, 95, 45))
d.rectangle((0, 4, 13, 4), fill=(230, 180, 70)); d.rectangle((6, 3, 7, 6), fill=(255, 220, 110))
outline(im).save(f"{OUT}/chest.png")


# ---------------------------------------------------------------- 特效
# 伞击挥砍：半月形斩击弧，4 帧（向右为 0 度）
def slash(frame):
    S = 48
    im = new(S, S); p = im.load()
    c = S / 2
    span = [0.35, 0.75, 1.0, 1.0][frame]
    fade = [1.0, 1.0, 0.8, 0.45][frame]
    for x in range(S):
        for y in range(S):
            dx, dy = x - c + 0.5, y - c + 0.5
            r = math.hypot(dx, dy); a = math.atan2(dy, dx)
            lo = -1.1; hi = lo + 2.2 * span
            if lo <= a <= hi:
                t = (a - lo) / 2.2
                thick = 3 + 5 * math.sin(max(0.0, min(1.0, t)) * math.pi)
                if 22 - thick <= r <= 22:
                    edge = r > 22 - 1.5
                    col = (235, 250, 255) if edge else (130, 200, 255)
                    p[x, y] = col + (int(255 * fade),)
    return im

strip([slash(i) for i in range(4)]).save(f"{OUT}/slash.png")

# 触手：从地面钻出，5 帧（升起→停留→缩回）
def tentacle(frame):
    im = new(12, 30); d = ImageDraw.Draw(im)
    hgt = [6, 16, 26, 22, 10][frame]
    base_y = 28
    dark, mid, hi = (40, 30, 90), (100, 70, 180), (170, 140, 240)
    pts = []
    for i in range(hgt):
        y = base_y - i
        x = 6 + math.sin(i * 0.35 + frame * 0.7) * (1 + i * 0.08)
        pts.append((x, y))
    for i, (x, y) in enumerate(pts):
        w = max(1, int(3.5 - i * 3.0 / max(hgt, 1)))
        d.line((x - w, y, x + w, y), fill=mid)
        d.point((x - w, y), fill=dark)
        if i % 4 == 1 and w > 1:
            d.point((x + w - 1, y), fill=(230, 140, 200))  # 吸盘
    if pts:
        tx, ty = pts[-1]
        d.point((tx, ty - 1), fill=hi)
    d.ellipse((1, 26, 11, 29), fill=(20, 18, 40))  # 地面裂口
    return outline(im)

strip([tentacle(i) for i in range(5)]).save(f"{OUT}/tentacle.png")

# 发光水母（环绕武器），2 帧
def jelly(frame):
    im = new(12, 14); d = ImageDraw.Draw(im)
    d.pieslice((1, 0, 10, 10), 180, 360, fill=(150, 220, 255))
    d.rectangle((1, 5, 10, 6), fill=(110, 180, 240))
    d.point((3, 2), fill=(255, 255, 255)); d.point((4, 2), fill=(230, 250, 255))
    for i, x in enumerate((3, 5, 7, 9)):
        for y in range(7, 13):
            xx = x + (1 if (y + i + frame) % 4 == 0 else 0)
            d.point((xx, y), fill=(170, 225, 255) if y < 10 else (120, 190, 240))
    return outline(im, (20, 40, 70, 255))

strip([jelly(0), jelly(1)]).save(f"{OUT}/jelly.png")

# 光晕贴图（给光源用）
L = 128
im = new(L, L); p = im.load()
for x in range(L):
    for y in range(L):
        r = math.hypot(x - L / 2 + 0.5, y - L / 2 + 0.5) / (L / 2)
        a = max(0.0, 1.0 - r) ** 1.6
        p[x, y] = (255, 255, 255, int(255 * a))
im.save(f"{OUT}/light.png")

print("ok")

# 阴影
im = new(14, 5); d = ImageDraw.Draw(im)
d.ellipse((0, 0, 13, 4), fill=(0, 0, 0, 110))
im.save(f"{OUT}/shadow.png")

# 玩家：由提供的角色图缩小为像素尺寸（仅缩放，不改动造型）
src = Image.open(os.path.join(os.path.dirname(__file__), "..", "art", "player_cut.png")).convert("RGBA")
H = 36
Wd = round(src.size[0] * H / src.size[1])
s = src.resize((Wd, H), Image.LANCZOS)
a = s.split()[3].point(lambda v: 255 if v > 120 else 0)
s.putalpha(a)
s.save(f"{OUT}/player.png")
print("player", s.size)

# ---------------------------------------------------------------- 援护干员（原创通用造型：兜帽小人，按职业配色与武器区分）
def ally(kind, frame):
    im = new(14, 18); d = ImageDraw.Draw(im)
    cols = {"sniper": ((70, 110, 90), (150, 190, 150)), "caster": ((80, 60, 130), (190, 150, 255)),
            "medic": ((200, 200, 210), (120, 220, 200)), "support": ((50, 90, 140), (140, 200, 255))}
    body, acc = cols[kind]
    bob = frame
    d.rectangle((4, 8 + bob, 9, 15), fill=body)                  # 身体
    d.line((5, 16, 5, 17), fill=(30, 35, 45)); d.line((8, 16, 8, 17), fill=(30, 35, 45))  # 腿
    d.ellipse((3, 1 + bob, 10, 9 + bob), fill=body)               # 兜帽
    d.rectangle((5, 5 + bob, 8, 7 + bob), fill=(235, 215, 195))   # 脸
    d.point((6, 6 + bob), fill=(20, 20, 30)); d.point((8, 6 + bob), fill=(20, 20, 30))
    d.line((4, 12 + bob, 9, 12 + bob), fill=acc)                  # 腰带/职业色
    if kind == "sniper":
        d.line((10, 6 + bob, 12, 14 + bob), fill=(150, 110, 70)); d.line((12, 6 + bob, 12, 14 + bob), fill=(220, 220, 220))
    elif kind == "caster":
        d.line((11, 4 + bob, 11, 16), fill=(120, 90, 60)); d.rectangle((10, 2 + bob, 12, 4 + bob), fill=acc)
    elif kind == "medic":
        d.rectangle((10, 9 + bob, 13, 12 + bob), fill=(240, 240, 240)); d.point((11, 10 + bob), fill=(220, 60, 70)); d.point((12, 10 + bob), fill=(220, 60, 70)); d.point((11, 11 + bob), fill=(220, 60, 70))
    else:
        d.line((11, 5 + bob, 11, 16), fill=(90, 110, 140)); d.ellipse((9, 2 + bob, 13, 6 + bob), outline=acc)
    return outline(im)

for k in ("sniper", "caster", "medic", "support"):
    strip([ally(k, 0), ally(k, 1)]).save(f"{OUT}/ally_{k}.png")

# 术师法术弹
im = new(8, 8); d = ImageDraw.Draw(im)
d.ellipse((0, 0, 7, 7), fill=(150, 110, 255)); d.ellipse((2, 2, 5, 5), fill=(230, 210, 255))
im.save(f"{OUT}/orb.png")
print("allies ok")

# ================================================================ v0.5 海嗣（原创造型，按原作定位设计）
def e_bone(f):      # 骨海漂流体：半透明伞体 + 外露骨刺
    im = new(14, 16); d = ImageDraw.Draw(im)
    d.ellipse((2, 1, 11, 9), fill=(70, 150, 150)); d.rectangle((2, 6, 11, 8), fill=(40, 100, 105))
    for x in (4, 7, 10): d.line((x, 2, x - 1, 7), fill=(225, 225, 205))
    for i, x in enumerate((3, 6, 9)):
        for y in range(9, 14):
            d.point((x + ((y + i + f) % 3 == 0) * (1 if i % 2 else -1), y), fill=(210, 210, 190))
    d.point((5, 5), fill=(255, 90, 90)); d.point((8, 5), fill=(255, 90, 90))
    return im

def e_slider(f):    # 底海滑动者：贴地滑行、多条附肢
    im = new(18, 12); d = ImageDraw.Draw(im)
    d.ellipse((3, 3, 16, 10), fill=(60, 120, 170)); d.line((5, 4, 13, 4), fill=(130, 190, 230))
    for i, x in enumerate((3, 6, 10, 14)):
        d.line((x, 9, x - 2 + (f + i) % 2 * 2, 11), fill=(40, 80, 120))
    d.line((15, 5, 17, 3 + f), fill=(40, 80, 120)); d.point((13, 6), fill=(255, 230, 120))
    return im

def e_stone(f):     # 固海凿石者：石质甲壳 + 凿状前肢（远程）
    im = new(18, 16); d = ImageDraw.Draw(im)
    d.polygon([(2, 12), (5, 3), (13, 2), (16, 11)], fill=(110, 110, 120)); d.line((5, 4, 12, 3), fill=(170, 170, 180))
    d.line((6, 7, 11, 8), fill=(80, 80, 90)); d.rectangle((3, 12, 15, 13), fill=(60, 60, 70))
    d.line((15, 6, 17, 2 + f), fill=(200, 150, 90)); d.point((12, 6), fill=(120, 230, 255))
    return im

def e_offspring(f): # 伊祖米克的子代：臃肿缓慢的幼体
    im = new(20, 18); d = ImageDraw.Draw(im)
    d.ellipse((1, 3 + f, 18, 17), fill=(120, 170, 110)); d.ellipse((4, 5 + f, 12, 11 + f), fill=(170, 210, 150))
    for x in (5, 10, 14): d.ellipse((x, 12, x + 3, 15), fill=(90, 130, 85))
    d.point((13, 8 + f), fill=(30, 30, 30)); d.point((15, 9 + f), fill=(30, 30, 30))
    return im

def e_brood(f):     # 注亡拟嗣：卵形诱饵
    im = new(10, 12); d = ImageDraw.Draw(im)
    d.ellipse((1, 1, 8, 11), fill=(170, 110, 150)); d.ellipse((3, 3, 6, 7), fill=(220, 170, 200))
    d.line((2, 10, 1 + f, 11), fill=(120, 70, 100)); d.line((7, 10, 8 - f, 11), fill=(120, 70, 100))
    return im

def e_pocket(f):    # 囊海爬行者：背负气囊的精英
    im = new(22, 18); d = ImageDraw.Draw(im)
    for i, x in enumerate((3, 7, 14, 18)):
        d.line((x, 13, x + (-1 if x < 11 else 1), 17 - (f + i) % 2), fill=(70, 50, 120))
    d.ellipse((2, 6, 19, 15), fill=(120, 90, 190))
    for x, y in ((4, 2), (9, 1), (14, 3)): d.ellipse((x, y, x + 5, y + 6), fill=(200, 120, 230)); d.point((x + 2, y + 2), fill=(255, 220, 255))
    d.point((6, 11), fill=(255, 230, 120)); d.point((15, 11), fill=(255, 230, 120))
    return im

def e_skimmer(f):   # 掠海漂移体：低空悬浮的鳐形（远程）
    im = new(24, 14); d = ImageDraw.Draw(im)
    d.polygon([(0, 7 - f), (8, 3), (16, 3), (23, 7 - f), (16, 10), (8, 10)], fill=(70, 160, 170))
    d.line((8, 4, 16, 4), fill=(150, 230, 230)); d.line((12, 10, 12, 13), fill=(40, 100, 110))
    d.point((10, 6), fill=(255, 90, 90)); d.point((14, 6), fill=(255, 90, 90))
    return im

def e_mother(f):    # 投嗣育母：膨大的育囊（远程）
    im = new(24, 22); d = ImageDraw.Draw(im)
    d.ellipse((3, 2, 21, 18), fill=(150, 80, 110)); d.ellipse((6, 5, 18, 15), fill=(190, 110, 140))
    for x, y in ((7, 7), (12, 9), (15, 6)): d.ellipse((x, y, x + 3, y + 3), fill=(240, 190, 210))
    d.ellipse((9, 15, 15, 20), fill=(60, 20, 40))
    for x in (5, 19): d.line((x, 16, x + (1 if x < 12 else -1) * (1 + f), 21), fill=(110, 50, 80))
    return im

def e_chest(f):     # 宝箱（补给箱 / 箱形恐鱼伪装）
    im = new(16, 14); d = ImageDraw.Draw(im)
    d.rectangle((0, 4, 15, 13), fill=(110, 75, 40)); d.rectangle((0, 1, 15, 5), fill=(140, 95, 50))
    d.rectangle((0, 5, 15, 5), fill=(220, 175, 80)); d.rectangle((7, 4, 8, 8), fill=(255, 215, 110))
    d.line((3, 1, 3, 13), fill=(90, 60, 30)); d.line((12, 1, 12, 13), fill=(90, 60, 30))
    return im

def e_mimic(f):     # 箱形恐鱼现形：箱盖张开、利齿与触须
    im = new(20, 18); d = ImageDraw.Draw(im)
    d.rectangle((2, 8, 17, 17), fill=(110, 75, 40)); d.polygon([(2, 7), (17, 7), (15, 0 + f), (4, 1 + f)], fill=(140, 95, 50))
    d.rectangle((3, 6, 16, 9), fill=(60, 10, 25))
    for x in range(4, 16, 3): d.polygon([(x, 6), (x + 1, 6), (x + 0.5, 9)], fill=(240, 230, 220))
    for x in (1, 18): d.line((x, 12, x + (-1 if x < 10 else 1), 17 - f), fill=(140, 60, 100))
    d.point((6, 3 + f), fill=(255, 60, 60)); d.point((13, 3 + f), fill=(255, 60, 60))
    return im

def e_path(f):      # 塑路者：高大的刃肢 Boss（近战）
    im = new(40, 44); d = ImageDraw.Draw(im)
    d.polygon([(14, 42), (12, 20), (20, 8), (28, 20), (26, 42)], fill=(60, 70, 110))
    d.ellipse((14, 4, 26, 16), fill=(80, 95, 140)); d.line((17, 10, 23, 10), fill=(120, 240, 255))
    d.line((12, 20, 2, 30 - f * 3), fill=(170, 180, 220), width=3); d.line((28, 20, 38, 30 - f * 3), fill=(170, 180, 220), width=3)
    d.line((16, 24, 24, 24), fill=(110, 125, 170)); d.line((16, 30, 24, 30), fill=(110, 125, 170))
    return im

def e_fractal(f):   # 塑路者碎片
    im = new(10, 10); d = ImageDraw.Draw(im)
    d.polygon([(5, 0), (9, 5 - f), (5, 9), (1, 5 + f)], fill=(120, 140, 200)); d.point((5, 4), fill=(160, 250, 255))
    return im

def e_izumik(f):    # 伊祖米克：巨大的海葵状生态体（远程）
    im = new(56, 52); d = ImageDraw.Draw(im)
    for k in range(10):
        a = k / 10 * math.tau + f * 0.15
        pts = [(28 + math.cos(a + math.sin(s * 0.8 + k) * 0.2) * (12 + s * 3), 30 + math.sin(a + math.sin(s * 0.8 + k) * 0.2) * (10 + s * 2.4)) for s in range(7)]
        d.line(pts, fill=(80, 170, 120), width=3)
    d.ellipse((14, 16, 42, 44), fill=(60, 130, 100)); d.ellipse((20, 22, 36, 38), fill=(170, 240, 190))
    d.ellipse((25, 27, 31, 33), fill=(255, 250, 220))
    return im

def e_ishar(f):     # 伊莎玛拉：发光的腐化之心（最终 Boss，远程）
    im = new(64, 60); d = ImageDraw.Draw(im)
    for k in range(12):
        a = k / 12 * math.tau + f * 0.12
        pts = [(32 + math.cos(a + s * 0.12) * (14 + s * 3), 30 + math.sin(a + s * 0.12) * (13 + s * 2.6)) for s in range(7)]
        d.line(pts, fill=(60, 40, 120), width=3)
    d.ellipse((16, 14, 48, 46), fill=(40, 30, 90)); d.ellipse((21, 19, 43, 41), fill=(110, 70, 200))
    d.ellipse((26, 24, 38, 36), fill=(200, 170, 255)); d.ellipse((29, 27, 35, 33), fill=(255, 255, 255))
    return im

def e_tear(f):      # 伊莎玛拉之泪：地面发光水洼
    im = new(18, 10); d = ImageDraw.Draw(im)
    d.ellipse((0, 2, 17, 9), fill=(90, 60, 170)); d.ellipse((3, 3 + f, 14, 8), fill=(170, 130, 255)); d.ellipse((7, 4, 10, 6), fill=(240, 220, 255))
    return im

for name, fn in (("e_bone", e_bone), ("e_slider", e_slider), ("e_stone", e_stone), ("e_offspring", e_offspring),
                 ("e_brood", e_brood), ("e_pocket", e_pocket), ("e_skimmer", e_skimmer), ("e_mother", e_mother),
                 ("e_chest", e_chest), ("e_mimic", e_mimic), ("e_path", e_path), ("e_fractal", e_fractal),
                 ("e_izumik", e_izumik), ("e_ishar", e_ishar), ("e_tear", e_tear)):
    save_enemy(name, [fn(0), fn(1)])

# 敌方弹、源石锭、商人
im = new(8, 8); d = ImageDraw.Draw(im)
d.ellipse((0, 0, 7, 7), fill=(230, 80, 140)); d.ellipse((2, 2, 5, 5), fill=(255, 190, 220)); im.save(f"{OUT}/ebullet.png")
im = new(9, 7); d = ImageDraw.Draw(im)
d.polygon([(1, 3), (4, 0), (8, 2), (7, 6), (2, 6)], fill=(235, 120, 50)); d.line((3, 2, 5, 1), fill=(255, 210, 140))
outline(im).save(f"{OUT}/ingot.png")
def merchant(f):
    im = new(16, 20); d = ImageDraw.Draw(im)
    d.rectangle((1, 7, 6, 16), fill=(110, 80, 50))                      # 背包
    d.rectangle((5, 8 + f, 11, 17), fill=(70, 60, 80)); d.ellipse((4, 1 + f, 12, 10 + f), fill=(70, 60, 80))
    d.rectangle((6, 5 + f, 10, 8 + f), fill=(40, 30, 40)); d.point((7, 6 + f), fill=(255, 220, 120)); d.point((9, 6 + f), fill=(255, 220, 120))
    d.line((12, 9 + f, 14, 12), fill=(90, 70, 50)); d.ellipse((12, 12, 15, 16), fill=(255, 190, 90))
    d.line((6, 18, 6, 19), fill=(30, 30, 40)); d.line((10, 18, 10, 19), fill=(30, 30, 40))
    return outline(im)
strip([merchant(0), merchant(1)]).save(f"{OUT}/merchant.png")
print("v05 art ok")

# ================================================================ 第三层 Boss 与最终 Boss（原创造型）
def e_saint(f, hat, coat, weapon):   # 圣徒：宽檐帽、长外套，手持火铳/剑
    im = new(26, 34); d = ImageDraw.Draw(im)
    d.polygon([(8, 32), (7, 14), (13, 10), (19, 14), (18, 32)], fill=coat)
    d.rectangle((9, 15, 17, 17), fill=(200, 170, 90))
    d.ellipse((9, 5, 17, 13), fill=(220, 200, 180)); d.rectangle((4, 4 - f, 22, 6 - f), fill=hat); d.rectangle((9, 0 - f, 17, 5 - f), fill=hat)
    d.point((11, 9), fill=(40, 40, 50)); d.point((15, 9), fill=(40, 40, 50))
    if weapon == "cannon":
        d.rectangle((17, 16, 25, 19), fill=(80, 80, 90)); d.rectangle((23, 15, 25, 20), fill=(60, 60, 70))
    else:
        d.line((18, 12, 25, 30), fill=(210, 220, 230), width=2)
    d.line((9, 32, 9, 33), fill=(30, 30, 40)); d.line((16, 32, 16, 33), fill=(30, 30, 40))
    return im

def e_bishop(f):    # 接潮主教：高大的长袍主教，身上长出海嗣组织
    im = new(24, 38); d = ImageDraw.Draw(im)
    d.polygon([(6, 37), (5, 14), (12, 8), (19, 14), (18, 37)], fill=(40, 45, 70))
    d.line((12, 14, 12, 36), fill=(200, 170, 90))
    d.polygon([(8, 9), (12, 0 + f), (16, 9)], fill=(220, 215, 200)); d.ellipse((9, 7, 15, 13), fill=(200, 190, 180))
    for y in (18, 24, 30): d.ellipse((3, y, 8, y + 4), fill=(90, 160, 150))
    d.line((20, 8, 20, 37), fill=(160, 140, 90)); d.ellipse((18, 5, 22, 9), fill=(120, 230, 220))
    return im

def e_archon(f):    # 接潮蔑死体：粗壮的海嗣躯体（近战）
    im = new(30, 30); d = ImageDraw.Draw(im)
    d.ellipse((4, 6, 26, 26), fill=(60, 110, 120)); d.ellipse((8, 9, 22, 20), fill=(90, 150, 160))
    for x in (6, 24): d.line((x, 14, x + (-5 if x < 15 else 5), 22 + f), fill=(40, 80, 90), width=3)
    d.polygon([(10, 22), (20, 22), (15, 28)], fill=(30, 10, 20))
    d.point((12, 13), fill=(255, 220, 90)); d.point((18, 13), fill=(255, 220, 90))
    return im

def e_immortal(f):  # 接潮斥亡体：细长迅捷的海嗣躯体（近战）
    im = new(28, 22); d = ImageDraw.Draw(im)
    d.ellipse((5, 6, 23, 16), fill=(90, 120, 170)); d.line((7, 8, 21, 8), fill=(150, 190, 230))
    for i, x in enumerate((6, 11, 16, 21)): d.line((x, 15, x - 3 + (i + f) % 2 * 6, 21), fill=(60, 80, 120))
    d.line((22, 9, 27, 5 - f), fill=(60, 80, 120), width=2); d.point((19, 10), fill=(255, 90, 90))
    return im

def e_paranoia(f):  # "偏执泡影"：悬浮的幻影气泡，外壳映出扭曲的光
    im = new(56, 56); d = ImageDraw.Draw(im)
    d.ellipse((6, 4 + f, 50, 48 + f), fill=(70, 50, 110)); d.ellipse((10, 8 + f, 46, 44 + f), fill=(120, 90, 170))
    d.arc((12, 10 + f, 44, 42 + f), 200, 320, fill=(230, 210, 255), width=2)
    for k in range(6):
        a = k / 6 * math.tau
        x, y = 28 + math.cos(a) * 11, 26 + f + math.sin(a) * 11
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(255, 240, 180)); d.point((x, y), fill=(40, 20, 50))
    d.ellipse((24, 22 + f, 32, 30 + f), fill=(255, 255, 255))
    for x in (14, 28, 42): d.line((x, 48 + f, x + (2 if f else -2), 55), fill=(90, 60, 140), width=2)
    return im

save_enemy("e_iberia", [e_saint(0, (60, 40, 40), (120, 40, 40), "sword"), e_saint(1, (60, 40, 40), (120, 40, 40), "sword")])
save_enemy("e_carmen", [e_saint(0, (30, 30, 40), (60, 60, 90), "cannon"), e_saint(1, (30, 30, 40), (60, 60, 90), "cannon")])
save_enemy("e_bishop", [e_bishop(0), e_bishop(1)])
save_enemy("e_archon", [e_archon(0), e_archon(1)])
save_enemy("e_immortal", [e_immortal(0), e_immortal(1)])
save_enemy("e_paranoia", [e_paranoia(0), e_paranoia(1)])
print("bosses ok")

# ---- v0.6 地面道具：磁铁 / 回复（通用图标）
im = new(12, 12); d = ImageDraw.Draw(im)
d.arc((1, 1, 10, 10), 180, 360, fill=(220, 50, 60), width=3)      # U 形上半
d.rectangle((1, 6, 3, 9), fill=(220, 50, 60)); d.rectangle((8, 6, 10, 9), fill=(60, 110, 230))
d.rectangle((1, 9, 3, 10), fill=(230, 235, 240)); d.rectangle((8, 9, 10, 10), fill=(230, 235, 240))
d.point((3, 3), fill=(255, 160, 160))
outline(im).save(f"{OUT}/pickup_magnet.png")
im = new(12, 12); d = ImageDraw.Draw(im)
d.ellipse((0, 0, 11, 11), fill=(40, 120, 80)); d.ellipse((1, 1, 10, 10), fill=(90, 210, 140))
d.rectangle((5, 2, 6, 9), fill=(245, 255, 245)); d.rectangle((2, 5, 9, 6), fill=(245, 255, 245))
d.point((3, 2), fill=(200, 255, 220))
outline(im).save(f"{OUT}/pickup_heal.png")
print("pickups ok")

# ---- v0.8 支援无人机（通用四旋翼造型，2 帧旋翼）
def drone(f):
    im = new(18, 12); d = ImageDraw.Draw(im)
    d.rectangle((6, 4, 11, 8), fill=(70, 90, 110)); d.rectangle((7, 5, 10, 7), fill=(120, 150, 175))
    d.point((8, 6), fill=(120, 255, 255)); d.point((9, 6), fill=(120, 255, 255))
    d.line((2, 4, 6, 5), fill=(50, 60, 75)); d.line((11, 5, 15, 4), fill=(50, 60, 75))
    for x in (2, 15):
        if f == 0: d.line((x - 2, 3, x + 2, 3), fill=(200, 230, 240))
        else: d.line((x - 1, 2, x + 1, 4), fill=(200, 230, 240))
    d.rectangle((7, 9, 10, 9), fill=(255, 120, 80))
    return im
strip([drone(0), drone(1)]).save(f"{OUT}/drone.png")
print("drone ok")
