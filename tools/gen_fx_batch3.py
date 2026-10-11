# -*- coding: utf-8 -*-
"""第三批干员（docs/59）的弹体 / 特效帧条（程序生成，固定种子、可重复；只有 0 / 255 两种 alpha；@2x 为严格 2 倍最近邻）。

写法同 tools/gen_fx_strips.py。帧条都朝右画（角度 0 = 右），游戏里按方向旋转；锚点（帧内像素）见 SPECS 与 docs/25 §6。
只出图、登记 game.gd V6_FRAMES；**不接玩法**（docs/59 的数据干员实现时再用 op_api.spawn_fx_sprite / g.vfx.spr_rot 取）。

  能天使   proj_exusiai_bullet / _power、fx_exusiai_muzzle / _gold、fx_exusiai_hit
           技能弹药换色（EXU_VARIANTS）：proj_exusiai_bullet_s1/_s2/_s3、fx_exusiai_muzzle_s1/_s2/_s3、fx_exusiai_hit_s1/_s2/_s3/_gold
  安洁莉娜 proj_angelina_orb、fx_angelina_pull、fx_angelina_levitate
  浊心斯卡蒂 fx_skalter_wave / _dim、fx_skalter_note
  星熊     fx_hoshiguma_block、fx_hoshiguma_sand、fx_hoshiguma_demon_slash
  德克萨斯 fx_texas_dash、fx_texas_blade

用法：python tools/gen_fx_batch3.py [--preview [目录]] [--no-write]
  --preview 另写 <目录>/contact.png（缺省 build/batch3_art/）：每条帧条一行，1x 与 4x。
"""
import os, sys, math, random
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art", "incoming")
PREV = os.path.join(ROOT, "build", "batch3_art")
CLEAR = (0, 0, 0, 0)


def C(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


# ---------------------------------------------------------------- 色板（docs/59 各人「美术」行的主色）
# 能天使 天使红 (0.95, 0.3, 0.3) + 白色弹道；弹夹满时金色
EX_W, EX_P, EX_R, EX_D = C("#fff6f2"), C("#ffc0b4"), C("#f24d4d"), C("#8a1c24")
EX_GW, EX_GP, EX_G, EX_GD = C("#fffbe6"), C("#fff0b0"), C("#ffd86a"), C("#c08a1e")
# 能天使三个技能的弹药色（10-12 用户「不同技能的弹药颜色是否可以更改」，docs/25 §6.1）：由上面的红 / 金帧条整张换色得到，形状不变。
# 避开敌方危险色（洋红 world.ENEMY_TELL / ui.RED、敌弹洋红描边、新星弹紫、酸团橄榄、神经弹浅黄）与治疗绿；三档明度也拉开（色盲靠亮度也分得清）。
#   S1 冲锋模式 冰青（强力弹形状）  S2 扫射模式 琥珀橙曳光  S3 过载模式 过热白 + 深红尾  弹匣倾泻 金（原样，另补金色命中）
EXU_S1 = {EX_W: C("#f0fdff"), EX_P: C("#b8f2ff"), EX_R: C("#48ccff"), EX_D: C("#12528a"),   # 小号帧条（枪口焰 / 命中）的四色
          EX_GW: C("#f0fdff"), EX_GP: C("#b8f2ff"), EX_G: C("#5cd8ff")}                   # 强力弹的金色三阶；红边 / 暗红尾走上一行
EXU_S1_POWER = {**EXU_S1, EX_R: C("#2a9ee0")}     # 强力弹里的红是外缘与拖尾：换成深一阶的青，弹头更亮
EXU_S2 = {EX_W: C("#fffaec"), EX_P: C("#ffdca4"), EX_R: C("#ff9a2e"), EX_D: C("#b04e10")}
EXU_S3 = {EX_W: C("#ffffff"), EX_P: C("#fff4ee"), EX_R: C("#ffd0c8"), EX_D: C("#d42a3a")}
EXU_GOLD = {EX_W: EX_GW, EX_P: EX_GP, EX_R: EX_G, EX_D: EX_GD}   # = fx_exusiai_muzzle_gold 的换色，给倾泻的命中火花
#   新帧条: (源帧条, 色板)
EXU_VARIANTS = {
    "proj_exusiai_bullet_s1": ("proj_exusiai_bullet_power", EXU_S1_POWER),
    "proj_exusiai_bullet_s2": ("proj_exusiai_bullet", EXU_S2),
    "proj_exusiai_bullet_s3": ("proj_exusiai_bullet", EXU_S3),
    "fx_exusiai_muzzle_s1": ("fx_exusiai_muzzle", EXU_S1),
    "fx_exusiai_muzzle_s2": ("fx_exusiai_muzzle", EXU_S2),
    "fx_exusiai_muzzle_s3": ("fx_exusiai_muzzle", EXU_S3),
    "fx_exusiai_hit_s1": ("fx_exusiai_hit", EXU_S1),
    "fx_exusiai_hit_s2": ("fx_exusiai_hit", EXU_S2),
    "fx_exusiai_hit_s3": ("fx_exusiai_hit", EXU_S3),
    "fx_exusiai_hit_gold": ("fx_exusiai_hit", EXU_GOLD),
}
# 安洁莉娜 重力紫 (0.7, 0.5, 0.95)
AN_W, AN_L, AN_V, AN_D, AN_K = C("#f6efff"), C("#dcc4ff"), C("#b380f2"), C("#6a44b0"), C("#34205e")
# 浊心斯卡蒂 浊心红 (0.85, 0.25, 0.35) + 海蓝波纹；昏暗档换深紫（PAL_DIM）
SK_W, SK_L, SK_R, SK_D = C("#fff0f2"), C("#ff9cac"), C("#d94059"), C("#7a1830")
SK_BL, SK_B = C("#9ae6ff"), C("#36a4dc")
PAL_DIM = {SK_W: C("#f0e6ff"), SK_L: C("#c9a6ff"), SK_R: C("#8a5cd6"), SK_D: C("#3a1c5a"),
           SK_BL: C("#6c8ad8"), SK_B: C("#3a3e94")}
# 星熊 鬼金 (0.95, 0.75, 0.3)；热砂橙；魔王黑红
HO_W, HO_P, HO_G, HO_D = C("#fffbea"), C("#ffe9a8"), C("#f2bf4d"), C("#a8701a")
SA_H, SA_M, SA_D = C("#ffc070"), C("#e08a3a"), C("#9a4c1a")
DM_K, DM_D, DM_R, DM_L = C("#1a0a0e"), C("#5a0c18"), C("#c82434"), C("#ff8a8a")
# 德克萨斯 企鹅黑 + 橙 (1.0, 0.55, 0.2)
TX_W, TX_P, TX_O, TX_D, TX_K, TX_S = C("#fff4e6"), C("#ffd0a0"), C("#ff8c33"), C("#b8501e"), C("#2a2a34"), C("#5a5a68")

#   名字: (帧宽, 帧高, 帧数, fps, 锚点)——帧数 / fps 与 game.gd V6_FRAMES 一致；锚点是帧内像素
SPECS = {
    "proj_exusiai_bullet": (16, 6, 2, 20.0, (12, 3)),
    "proj_exusiai_bullet_power": (20, 8, 2, 20.0, (15, 4)),
    "fx_exusiai_muzzle": (16, 16, 3, 30.0, (1, 8)),
    "fx_exusiai_muzzle_gold": (16, 16, 3, 30.0, (1, 8)),
    "fx_exusiai_hit": (12, 12, 3, 24.0, (6, 6)),
    "proj_angelina_orb": (16, 16, 4, 12.0, (8, 8)),
    "fx_angelina_pull": (64, 32, 6, 15.0, (32, 16)),
    "fx_angelina_levitate": (32, 32, 6, 10.0, (16, 27)),
    "fx_skalter_wave": (64, 32, 6, 12.0, (32, 16)),
    "fx_skalter_wave_dim": (64, 32, 6, 12.0, (32, 16)),
    "fx_skalter_note": (12, 16, 4, 8.0, (6, 8)),
    "fx_hoshiguma_block": (32, 32, 5, 20.0, (16, 16)),
    "fx_hoshiguma_sand": (48, 24, 4, 8.0, (24, 12)),
    "fx_hoshiguma_demon_slash": (64, 16, 5, 20.0, (0, 8)),
    "fx_texas_dash": (64, 16, 4, 20.0, (63, 8)),
    "fx_texas_blade": (12, 32, 6, 20.0, (6, 30)),
}
SPECS.update({k: SPECS[src] for k, (src, _) in EXU_VARIANTS.items()})   # 换色帧条：尺寸 / 帧数 / fps / 锚点同源帧条


# ---------------------------------------------------------------- 像素助手（px: dict (x,y)->RGBA）
def put(px, x, y, c):
    px[(int(round(x)), int(round(y)))] = c


def disc(px, cx, cy, r, c, sy=1.0, dither=False, rmin=0.0, phase=0):
    """实心圆（sy < 1 压成椭圆）；dither 只填棋盘格；rmin 为内径（环带）"""
    R = int(math.ceil(r)) + 1
    for y in range(int(cy - R * sy) - 1, int(cy + R * sy) + 2):
        for x in range(int(cx - R) - 1, int(cx + R) + 2):
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) / max(sy, 1e-3))
            if rmin <= d <= r and (not dither or (x + y + phase) % 2 == 0):
                px[(x, y)] = c


def arc(px, cx, cy, r, a0, a1, c, sy=1.0, step=None):
    """沿半径 r 从角 a0 到 a1（弧度，屏幕坐标：y 向下）点一条弧"""
    n = max(2, int(abs(a1 - a0) * r * 1.6)) if step is None else step
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        put(px, cx + math.cos(a) * r - 0.5, cy + math.sin(a) * r * sy - 0.5, c)


def line(px, x0, y0, x1, y1, c):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n):
        t = i / max(1, n - 1)
        put(px, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c)


def glyph(px, rows, x0, y0, leg):
    for j, r in enumerate(rows):
        for i, ch in enumerate(r):
            if ch in leg:
                px[(x0 + i, y0 + j)] = leg[ch]


def outline(px, c, solid=None):
    """给已有像素外面描一圈（4 邻域）"""
    keys = set(px) if solid is None else {p for p, v in px.items() if v in solid}
    for (x, y) in list(keys):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in px:
                px[q] = c


def strip(name, fn):
    fw, fh, n, _, _ = SPECS[name]
    im = Image.new("RGBA", (fw * n, fh), CLEAR)
    for f in range(n):
        px = {}
        fn(px, f)
        for (x, y), c in px.items():
            if 0 <= x < fw and 0 <= y < fh:
                im.putpixel((f * fw + x, y), c)
    return im


def swap(im, pal):
    out = im.copy()
    b = im.tobytes()
    data = [pal.get(p, p) for p in (tuple(b[i:i + 4]) for i in range(0, len(b), 4))]
    out.putdata(data)
    return out


# ================================================================ 能天使
def ex_bullet(px, f, W=EX_W, P=EX_P, R=EX_R, D=EX_D):
    """16×6：白芯弹头（右）+ 粉红 → 天使红 → 暗红棋盘拖尾；第 2 帧拖尾错一格闪烁"""
    for y in (2, 3):
        for x in range(11, 14):
            put(px, x, y, W)
        put(px, 14, y, P)
        for x in range(0, 11):
            if x >= 7:
                c = P if x >= 9 else R
            elif x >= 3:
                c = R
            else:
                if (x + y + f) % 2:
                    continue
                c = D
            if f == 1 and x < 5 and (x + y) % 2 == 0:
                continue
            put(px, x, y, c)
    for x in (11, 12):
        put(px, x, 1, P)
        put(px, x, 4, P)


def ex_bullet_power(px, f):
    """20×8：强力弹——金白弹头 + 天使红外缘 + 长拖尾（穿透感）"""
    for y in range(2, 6):
        edge = y in (2, 5)
        for x in range(13, 18):
            put(px, x, y, EX_GP if edge else EX_GW)
        put(px, 18, y, EX_G if edge else EX_GP)
        for x in range(0, 13):
            if x >= 9:
                c = EX_R if edge else EX_G
            elif x >= 4:
                c = EX_D if edge else EX_R
            else:
                if (x + y + f) % 2:
                    continue
                c = EX_D
            put(px, x, y, c)
    put(px, 19, 3, EX_GW)
    put(px, 19, 4, EX_GW)
    for x in (14, 15, 16):
        put(px, x, 1, EX_R)
        put(px, x, 6, EX_R)
    if f == 0:
        put(px, 16, 0, EX_G)
        put(px, 16, 7, EX_G)


def ex_muzzle(px, f, W=EX_W, P=EX_P, R=EX_R, D=EX_D):
    """16×16 枪口焰，锚点 (1, 8)、朝右：星形白芯 + 前喷锥 → 缩小 → 火星"""
    cx, cy = 3.0, 8.0
    if f == 0:
        for x in range(2, 15):
            h = 4.2 * (1 - (x - 2) / 13.0) + 0.6
            for y in range(int(cy - h), int(cy + h) + 1):
                d = abs(y + 0.5 - cy)
                put(px, x, y, W if d < h * 0.35 and x < 11 else (P if d < h * 0.7 else R))
        disc(px, cx, cy, 3.2, W)
        for dy in (-1, 1):
            line(px, 4, 8 + dy * 2, 9, 8 + dy * 6, P)
        line(px, 2, 3, 2, 1, R)
        line(px, 2, 13, 2, 15, R)
    elif f == 1:
        for x in range(2, 12):
            h = 2.6 * (1 - (x - 2) / 10.0) + 0.5
            for y in range(int(cy - h), int(cy + h) + 1):
                if x > 7 and (x + y) % 2:
                    continue
                put(px, x, y, P if abs(y + 0.5 - cy) < h * 0.5 else R)
        disc(px, cx, cy, 2.0, W)
    else:
        rnd = random.Random(5910)
        disc(px, 2.5, cy, 1.4, D, dither=True)
        for q in range(5):
            a = rnd.uniform(-0.9, 0.9)
            d = rnd.uniform(5, 12)
            put(px, cx + math.cos(a) * d, cy + math.sin(a) * d, R if q % 2 else P)


def ex_muzzle_gold(px, f):
    ex_muzzle(px, f, EX_GW, EX_GP, EX_G, EX_GD)


def ex_hit(px, f):
    """12×12 命中：白色十字星 → 红环 + 四火星 → 稀疏火星"""
    cx = cy = 6.0
    if f == 0:
        disc(px, cx, cy, 2.0, EX_W)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for k in range(2, 5):
                put(px, cx - 0.5 + dx * k, cy - 0.5 + dy * k, EX_W if k < 4 else EX_P)
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            put(px, cx - 0.5 + dx * 2, cy - 0.5 + dy * 2, EX_P)
    elif f == 1:
        disc(px, cx, cy, 4.2, EX_R, rmin=3.2)
        disc(px, cx, cy, 1.2, EX_P)
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            put(px, cx - 0.5 + dx * 5, cy - 0.5 + dy * 5, EX_P)
    else:
        disc(px, cx, cy, 5.2, EX_D, rmin=4.4, dither=True)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            put(px, cx - 0.5 + dx * 5, cy - 0.5 + dy * 5, EX_R)


# ================================================================ 安洁莉娜
def an_orb(px, f):
    """16×16 重力弹（循环）：紫球 + 棋盘外晕 + 两道绕着转、往里收的弧"""
    cx = cy = 8.0
    disc(px, cx, cy, 6.6, AN_D, dither=True, rmin=4.6, phase=f)
    disc(px, cx, cy, 4.4, AN_V)
    disc(px, cx, cy, 3.0, AN_L)
    disc(px, cx - 1.0, cy - 1.0, 1.3, AN_W)
    base = f * math.pi / 4
    for k in range(2):
        a = base + k * math.pi
        for i in range(7):
            t = i / 6.0
            r = 7.4 - 2.4 * t
            aa = a + t * 1.4
            put(px, cx + math.cos(aa) * r - 0.5, cy + math.sin(aa) * r - 0.5, AN_W if i > 3 else AN_L)


def an_pull(px, f):
    """64×32 落点拉拢（地面，压扁 0.5）：环从外往里收、六道向心旋弧，最后中心一闪"""
    cx, cy, sy = 32.0, 16.0, 0.5
    R = [30, 24, 18, 13, 8, 4][f]
    if f < 5:
        disc(px, cx, cy, R + 1.2, AN_V, sy=sy, rmin=R - 0.2)
        disc(px, cx, cy, R, AN_L, sy=sy, rmin=R - 0.8)
    if f >= 1:
        Rp = [30, 24, 18, 13, 8][f - 1]
        disc(px, cx, cy, Rp + 0.8, AN_D, sy=sy, rmin=Rp - 0.4, dither=True)
    for k in range(6):
        a0 = k * math.tau / 6 + f * 0.35
        r_out = R + 9 - f
        for i in range(8):
            t = i / 7.0
            r = r_out - (r_out - R - 1) * t
            a = a0 + t * 0.7
            if r < 1:
                continue
            put(px, cx + math.cos(a) * r - 0.5, cy + math.sin(a) * r * sy - 0.5, AN_W if t > 0.7 else (AN_L if t > 0.35 else AN_D))
    if f >= 3:
        disc(px, cx, cy, [0, 0, 0, 3.0, 5.0, 6.5][f], AN_V, sy=sy)
        disc(px, cx, cy, [0, 0, 0, 1.6, 3.0, 3.6][f], AN_W, sy=sy)
    if f == 5:
        disc(px, cx, cy, 9.0, AN_D, sy=sy, rmin=7.5, dither=True)


def an_levitate(px, f):
    """32×32 悬浮（循环，锚点脚底 (16, 27)）：脚下紫光椭圆 + 上升的尘点与细光丝"""
    cx, cy = 16.0, 27.0
    disc(px, cx, cy, 11.0, AN_D, sy=0.3, dither=True, rmin=8.0, phase=f)
    disc(px, cx, cy, 8.0, AN_V, sy=0.3, rmin=6.5)
    disc(px, cx, cy, 6.5, AN_K, sy=0.3, dither=True)
    rnd = random.Random(5920)
    motes = [(rnd.uniform(5, 27), rnd.uniform(0, 24), rnd.choice([AN_L, AN_W, AN_V])) for _ in range(9)]
    for i, (x, y0, c) in enumerate(motes):
        y = cy - 2 - ((y0 + f * 4) % 24)
        if y < 2:
            continue
        put(px, x, y, c)
        if c == AN_W and y < cy - 4:
            put(px, x, y + 1, AN_V)
    for k, x in enumerate((9, 23, 16)):
        top = cy - 6 - ((f * 3 + k * 7) % 14)
        for y in range(int(top), int(top) + 4):
            if (y + k) % 2 == 0:
                put(px, x, y, AN_L)


# ================================================================ 浊心斯卡蒂
def sk_wave(px, f):
    """64×32 声浪（地面，压扁 0.5）：浊心红环向外扩 + 内侧海蓝波纹（波浪起伏），后两帧棋盘散去"""
    cx, cy, sy = 32.0, 16.0, 0.5
    R = [6, 12, 18, 23, 27, 30][f]
    fade = f >= 4
    for i in range(int(R * 7)):
        a = i / (R * 7) * math.tau
        wob = 0.8 * math.sin(a * 6 + f)
        for dr, c in ((0.0, SK_L), (1.0, SK_R), (-1.0, SK_R)):
            x, y = cx + math.cos(a) * (R + dr + wob) - 0.5, cy + math.sin(a) * (R + dr + wob) * sy - 0.5
            if fade and (int(round(x)) + int(round(y))) % 2:
                continue
            put(px, x, y, SK_W if (f <= 1 and dr == 0.0) else c)
    Ri = R - 5
    if Ri > 2:
        for i in range(int(Ri * 6)):
            a = i / (Ri * 6) * math.tau
            wob = 1.0 * math.sin(a * 8 - f * 1.3)
            x, y = cx + math.cos(a) * (Ri + wob) - 0.5, cy + math.sin(a) * (Ri + wob) * sy - 0.5
            if (int(round(x)) + int(round(y))) % 2 == 0 or not fade:
                put(px, x, y, SK_BL if wob > 0.3 else SK_B)
    if f == 0:
        disc(px, cx, cy, 3.0, SK_W, sy=sy)
        disc(px, cx, cy, 4.5, SK_L, sy=sy, rmin=3.0)
    if f >= 2:
        disc(px, cx, cy, R + 2.5, SK_D, sy=sy, rmin=R + 1.8, dither=True)


NOTE = [
    "...WW..",
    "...WWW.",
    "...W.WW",
    "...W..W",
    "...W...",
    "...W...",
    ".WWW...",
    "WWWW...",
    "WWWW...",
    ".WW....",
]


def sk_note(px, f):
    """12×16 绕行音符（循环）：白色八分音符 + 浊心红描边，上下浮动，偶数帧右上一点海蓝闪光"""
    dy = [0, -1, -1, 0][f]
    glyph(px, NOTE, 2, 3 + dy, {"W": SK_W})
    put(px, 3, 10 + dy, SK_L)
    outline(px, SK_R)
    if f % 2 == 0:
        put(px, 10, 2 + dy, SK_BL)
    else:
        put(px, 1, 13 + dy, SK_B)


# ================================================================ 星熊
def ho_block(px, f):
    """32×32 格挡：盾面六边形金白闪光 + 放射 → 六边形描边 + 冲击环 → 环外扩散成火星"""
    cx = cy = 16.0
    hexr = lambda r, rot=0.0: [(cx + math.cos(rot + k * math.pi / 3) * r, cy + math.sin(rot + k * math.pi / 3) * r) for k in range(6)]

    def hex_fill(r, c):
        pts = hexr(r, math.pi / 6)
        for y in range(32):
            for x in range(32):
                px_, py_ = x + 0.5, y + 0.5
                inside = True
                for i in range(6):
                    (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % 6]
                    if (x2 - x1) * (py_ - y1) - (y2 - y1) * (px_ - x1) < 0:
                        inside = False
                        break
                if inside:
                    px[(x, y)] = c

    def hex_line(r, c):
        pts = hexr(r, math.pi / 6)
        for i in range(6):
            (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % 6]
            line(px, x1 - 0.5, y1 - 0.5, x2 - 0.5, y2 - 0.5, c)

    if f == 0:
        hex_fill(8.0, HO_G)
        hex_fill(6.0, HO_P)
        hex_fill(3.6, HO_W)
        for k in range(8):
            a = k * math.pi / 4
            line(px, cx + math.cos(a) * 10 - 0.5, cy + math.sin(a) * 10 - 0.5, cx + math.cos(a) * 14 - 0.5, cy + math.sin(a) * 14 - 0.5, HO_W if k % 2 == 0 else HO_P)
    elif f == 1:
        hex_line(9.0, HO_G)
        hex_line(8.0, HO_P)
        hex_fill(4.0, HO_P)
        hex_fill(2.2, HO_W)
        disc(px, cx, cy, 12.5, HO_G, rmin=11.3)
    elif f == 2:
        hex_line(9.0, HO_D)
        disc(px, cx, cy, 14.5, HO_P, rmin=13.4)
        disc(px, cx, cy, 13.4, HO_G, rmin=12.6)
        disc(px, cx, cy, 2.0, HO_G, dither=True)
    elif f == 3:
        disc(px, cx, cy, 15.6, HO_G, rmin=14.6, dither=True)
        rnd = random.Random(5930)
        for q in range(8):
            a = q * math.tau / 8 + rnd.uniform(-0.2, 0.2)
            d = rnd.uniform(10, 14)
            put(px, cx + math.cos(a) * d - 0.5, cy + math.sin(a) * d - 0.5, HO_P if q % 2 else HO_W)
    else:
        rnd = random.Random(5931)
        for q in range(6):
            a = rnd.random() * math.tau
            d = rnd.uniform(12, 15.5)
            put(px, cx + math.cos(a) * d - 0.5, cy + math.sin(a) * d - 0.5, HO_D if q % 2 else HO_G)


def ho_sand(px, f):
    """48×24 热砂（地面循环，压扁）：椭圆里的砂粒按相位明灭 + 几缕上升的热浪棋盘点"""
    cx, cy = 24.0, 12.0
    rnd = random.Random(5940)
    grains = []
    while len(grains) < 64:
        x, y = rnd.uniform(1, 47), rnd.uniform(2, 22)
        if ((x - cx) / 22.5) ** 2 + ((y - cy) / 10.0) ** 2 <= 1.0:
            grains.append((int(x), int(y), rnd.randrange(4)))
    cols = [SA_H, SA_M, SA_D, None]
    for x, y, ph in grains:
        c = cols[(ph + f) % 4]
        if c is not None:
            px[(x, y)] = c
            if c == SA_H and x + 1 < 48:
                px[(x + 1, y)] = SA_M
    disc(px, cx, cy, 23.0, SA_D, sy=0.44, rmin=22.0, dither=True, phase=f)
    for k, x in enumerate((12, 24, 35)):
        base = 14 - ((f * 2 + k * 3) % 8)
        for j in range(5):
            y = base - j
            xx = x + (1 if (j + f + k) % 4 < 2 else 0)
            if 0 <= y and (j % 2 == 0):
                px[(xx, y)] = SA_H if j < 2 else SA_M


def ho_demon(px, f):
    """64×16 魔王直线斩（锚点左中 (0, 8)、朝右）：白芯 → 黑红獠牙边的直线 → 红色棋盘散 → 黑红碎片"""
    cy = 8
    L = [22, 63, 63, 63, 63][f]
    rnd = random.Random(5950 + f)
    if f == 0:
        for x in range(0, L):
            put(px, x, cy, HO_W)
            put(px, x, cy - 1, DM_L if x > 4 else DM_R)
        put(px, L, cy, DM_L)
        return
    if f in (1, 2):
        th = 1 if f == 1 else 2
        for x in range(0, L + 1):
            taper = 1 if x > L - 6 else 0
            for y in range(cy - th + taper, cy + th - taper):
                put(px, x, y, HO_W if f == 1 else DM_L)
            put(px, x, cy - th - 1 + taper, DM_R)
            put(px, x, cy + th - taper, DM_R)
            # 鬼面獠牙：上下交错的锯齿（黑）
            k = x % 6
            if x < L - 4:
                if k in (0, 1):
                    put(px, x, cy - th - 2 - (1 if k == 0 else 0), DM_K)
                    put(px, x, cy - th - 2, DM_K)
                if k in (3, 4):
                    put(px, x, cy + th + 1 + (1 if k == 4 else 0), DM_K)
                    put(px, x, cy + th + 1, DM_K)
        if f == 2:   # 中段一对红眼斑
            for ex in (20, 42):
                put(px, ex, cy - 4, DM_R)
                put(px, ex + 1, cy - 4, DM_L)
    elif f == 3:
        for x in range(0, L + 1):
            for y in (cy - 2, cy - 1, cy, cy + 1):
                if (x + y) % 2 == 0:
                    put(px, x, y, DM_R if y in (cy - 1, cy) else DM_D)
            if x % 6 in (0, 3) and x < L - 4:
                put(px, x, cy - 4 if x % 6 == 0 else cy + 3, DM_K)
    else:
        for q in range(16):
            x = rnd.uniform(0, 62)
            y = cy + rnd.uniform(-3, 3)
            put(px, x, y, DM_D if q % 3 else DM_R)
            put(px, x + 1, y, DM_K)


# ================================================================ 德克萨斯
def tx_dash(px, f):
    """64×16 疾行斩剑光（锚点右中 (63, 8)：冲刺终点；朝右）：尖头白芯 → 橙 → 暗橙棋盘拖尾 + 上下两道速度线"""
    cy = 8.0
    head = 63
    tail = [0, 8, 24, 40][f]
    for x in range(tail, head + 1):
        u = (x - tail) / max(1.0, head - tail)       # 0 尾 … 1 头
        if f >= 2 and (x % 2 == 0):
            continue
        h = 0.6 + 3.0 * (u ** 0.6) * (1.0 - max(0.0, (u - 0.93) / 0.07))
        if f >= 1:
            h *= [1.0, 0.8, 0.55, 0.4][f]
        for y in range(int(cy - h), int(cy + h) + 1):
            d = abs(y + 0.5 - cy) / max(h, 0.5)
            if u > 0.75 and d < 0.4 and f <= 1:
                c = TX_W
            elif d < 0.6:
                c = TX_P if u > 0.5 else TX_O
            else:
                c = TX_O if u > 0.4 else TX_D
            if u < 0.25 and (x + y) % 2:
                continue
            put(px, x, y, c)
    for dy, x0, x1 in ((-5, 18, 50), (5, 10, 44)):
        a = x0 + f * 10
        for x in range(a, min(x1 + f * 6, 63)):
            if f >= 2 and x % 3 == 0:
                continue
            put(px, x, cy + dy, TX_O if x > (a + x1) / 2 else TX_D)
    if f == 3:
        rnd = random.Random(5960)
        for q in range(6):
            put(px, rnd.uniform(40, 62), cy + rnd.uniform(-4, 4), TX_O)


BLADE = [
    ".KKK.",
    "OOOOO",
    "..K..",
    ".KWK.",
    ".KOK.",
    ".KOK.",
    ".KOK.",
    ".KOK.",
    ".KOK.",
    "..K..",
    "..W..",
]


def tx_blade(px, f):
    """12×32 剑雨的一柄短剑（锚点 (6, 30) = 落点）：两帧下落（带橙色拖影）→ 插地白闪 → 橙色地环 → 剑身棋盘淡出 → 火星"""
    leg = {"K": TX_K, "O": TX_O, "W": TX_W}
    gy = 30
    if f in (0, 1):
        top = [0, 9][f]
        for y in range(max(0, top - 8), top):
            if (y + f) % 2 == 0 or y > top - 4:
                put(px, 6, y, TX_O if y > top - 4 else TX_D)
        glyph(px, BLADE, 4, top, leg)
    else:
        top = gy - 10
        if f == 2:
            disc(px, 6.5, gy, 5.5, TX_P, sy=0.35)
            disc(px, 6.5, gy, 3.0, TX_W, sy=0.35)
            line(px, 6, gy - 1, 6, gy - 14, TX_W)
        elif f == 3:
            disc(px, 6.5, gy, 6.0, TX_O, sy=0.35, rmin=4.5)
        if f <= 4:
            for j, r in enumerate(BLADE):
                for i, ch in enumerate(r):
                    if ch in leg and (f <= 3 or (i + j) % 2 == 0):
                        px[(4 + i, top + j)] = leg[ch] if f <= 3 else TX_S
        if f >= 4:
            rnd = random.Random(5970 + f)
            for q in range(4 if f == 4 else 3):
                put(px, rnd.uniform(1, 11), gy - rnd.uniform(1, 6 + f), TX_O if q % 2 else TX_D)


# ----------------------------------------------------------------
GEN = {
    "proj_exusiai_bullet": ex_bullet,
    "proj_exusiai_bullet_power": ex_bullet_power,
    "fx_exusiai_muzzle": ex_muzzle,
    "fx_exusiai_muzzle_gold": ex_muzzle_gold,
    "fx_exusiai_hit": ex_hit,
    **{k: None for k in EXU_VARIANTS},    # = 源帧条整张换色（EXU_VARIANTS）
    "proj_angelina_orb": an_orb,
    "fx_angelina_pull": an_pull,
    "fx_angelina_levitate": an_levitate,
    "fx_skalter_wave": sk_wave,
    "fx_skalter_wave_dim": None,          # = fx_skalter_wave 换 PAL_DIM
    "fx_skalter_note": sk_note,
    "fx_hoshiguma_block": ho_block,
    "fx_hoshiguma_sand": ho_sand,
    "fx_hoshiguma_demon_slash": ho_demon,
    "fx_texas_dash": tx_dash,
    "fx_texas_blade": tx_blade,
}


def _x2(im):
    return im.resize((im.width * 2, im.height * 2), Image.NEAREST)


def check(im, name):
    fw, fh, n, _, _ = SPECS[name]
    assert im.size == (fw * n, fh), (name, im.size)
    assert set(im.getchannel("A").tobytes()) <= {0, 255}, name
    for f in range(n):    # 每帧都不能是空的
        assert im.crop((f * fw, 0, f * fw + fw, fh)).getbbox() is not None, (name, f)


def build():
    ims = {}
    for name, fn in GEN.items():
        if fn is None:
            continue
        ims[name] = strip(name, fn)
    ims["fx_skalter_wave_dim"] = swap(ims["fx_skalter_wave"], PAL_DIM)
    for name, (src, pal) in EXU_VARIANTS.items():
        left = {p for p in ims[src].getdata() if p[3] and p not in pal}
        assert not left, (name, "源帧条里有色板没覆盖的颜色", left)   # 每个像素都换掉，不留原色
        ims[name] = swap(ims[src], pal)
    return {k: ims[k] for k in GEN}


def preview(ims, out_dir, icons=None):
    """联系表：（可选）第三批技能图标一行 1x + 4x，然后每条帧条一行 1x、一行 4x，名字标在左边"""
    from PIL import ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    bg = (28, 30, 44, 255)
    rows = []
    if icons:
        strip1 = Image.new("RGBA", (len(icons) * 36, 32), CLEAR)
        for i, im in enumerate(icons):
            strip1.paste(im, (i * 36, 0), im)
        rows.append(("skill icons 1x", strip1))
        rows.append(("skill icons 4x", strip1.resize((strip1.width * 4, strip1.height * 4), Image.NEAREST)))
    for name, im in ims.items():
        rows.append((name, im))
        rows.append(("", im.resize((im.width * 4, im.height * 4), Image.NEAREST)))
    LBL = 190
    W = max(r.width for _, r in rows) + LBL + 16
    H = sum(r.height + 8 for _, r in rows) + 8
    sheet = Image.new("RGBA", (W, H), bg)
    d = ImageDraw.Draw(sheet)
    y = 8
    for label, r in rows:
        if label:
            fw, fh, n, fps, an = SPECS.get(label, (0, 0, 0, 0, None)) if label in SPECS else (0, 0, 0, 0, None)
            d.text((8, y), label, fill=(255, 230, 120, 255))
            if n:
                d.text((8, y + 12), "%dx%d x%d %gfps @%s" % (fw, fh, n, fps, an), fill=(180, 190, 210, 255))
        sheet.paste(r, (LBL, y), r)
        y += r.height + 8
    p = os.path.join(out_dir, "contact.png")
    sheet.save(p)
    return p


def main():
    ims = build()
    for name, im in ims.items():
        check(im, name)
        if "--no-write" not in sys.argv:
            im.save(os.path.join(OUT, name + ".png"))
            _x2(im).save(os.path.join(OUT, name + "@2x.png"))
        print("ok", name, im.size)
    if "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        d = sys.argv[i + 1] if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--") else PREV
        icons = []
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        try:
            import skill_icons_batch3 as SI
            r = SI.render_all()
            icons = [r[k] for k in sorted(r, key=lambda k: (SI.OPS.index(k[0]), k[1]))]
        except Exception as e:   # 预览可选
            print("（图标行跳过：%s）" % e)
        print("preview:", preview(ims, d, icons))


if __name__ == "__main__":
    main()
