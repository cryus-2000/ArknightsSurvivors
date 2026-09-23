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
