# -*- coding: utf-8 -*-
"""干员出场名字卡 · 动态版（docs/327 §17，参照鹰角活动 PV「NEW OPERATOR」段）：
Blender 渲的像素海底背景板（pv3d_pixel.py PV3D_NOMZ=1，缓慢漂移）上逐帧叠：
  像素干员（技能起手 → 循环帧，整数倍最近邻放大到画面内高约 88%，青色边光）
  超大英文代号（前 5 帧故障出字：横切错位 + 青色重影，之后定格）
  小字簇（中文名 宋 700 56 + 职业图标 + 职业 · 分支 + 一行简介）6 帧淡入；右侧 OPERATOR 编号；左上 2×2 小方格
  2.35:1 遮幅 + 单色颗粒
  render(bg_dir, out_dir, op) → out_dir/c%04d.png（帧数 = 背景帧数）
"""
import json, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pv_type as T

ROOT = T.ROOT
ART = ROOT + "/game/art"
W, H = 1920, 1080
LB = 131   # 2.35:1
FPS = 60
OPS = {
    # id: (代号, 中文名, 职业图标, 职业 · 分支, 简介（招募卡上用户写的那句）, 序号)
    "mizuki": ("MIZUKI", "水月", "special", "特种 · 伏击客", None, 1),
    "skadi": ("SKADI", "斯卡蒂", "warrior", "近卫", None, 2),
    "texas": ("TEXAS", "德克萨斯", "pioneer", "先锋", None, 3),
}


def ease(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


def _frames(op):
    """技能起手 8 帧（16 fps）→ 循环帧（8 fps）；按全部帧的并集外框裁，避免人物跳动"""
    d = json.load(open(ROOT + "/game/data/characters/%s.json" % op, encoding="utf-8"))
    sp = d["sprites"]
    seq = []
    for key in ("skill_s3", "skill_s3_loop"):
        if key not in sp:
            continue
        v = sp[key]
        s = Image.open(ART + "/operators/%s/%s@2x.png" % (op, v["tex"])).convert("RGBA")
        n = int(v["frames"])
        fw = s.width // n
        seq.append(([s.crop((i * fw, 0, (i + 1) * fw, s.height)) for i in range(n)], float(v.get("fps", 10))))
    if not seq:   # 没有技能帧：用入场帧
        v = sp["entry"]
        s = Image.open(ART + "/operators/%s/%s@2x.png" % (op, v["tex"])).convert("RGBA")
        n = int(v["frames"])
        fw = s.width // n
        seq.append(([s.crop((i * fw, 0, (i + 1) * fw, s.height)) for i in range(n)], float(v.get("fps", 10))))
    bb = None
    for frs, _ in seq:
        for f in frs:
            b = f.getbbox()
            if b:
                bb = b if bb is None else (min(bb[0], b[0]), min(bb[1], b[1]), max(bb[2], b[2]), max(bb[3], b[3]))
    return [([f.crop(bb) for f in frs], fps) for frs, fps in seq]


def _frame_at(seq, t):
    (a, fa) = seq[0]
    ta = len(a) / fa
    if t < ta or len(seq) == 1:
        return a[min(len(a) - 1, int(t * fa))] if len(seq) > 1 else a[int(t * fa) % len(a)]
    b, fb = seq[1]
    return b[int((t - ta) * fb) % len(b)]


def condensed(text, font, squeeze=0.78):
    tmp = Image.new("RGBA", (int(font.size * len(text) * 1.2), int(font.size * 1.4)), (0, 0, 0, 0))
    T.tracked(ImageDraw.Draw(tmp), (0, 0), text, font, T.INK + (255,), 0.04)
    tmp = tmp.crop(tmp.getbbox())
    return tmp.resize((int(tmp.width * squeeze), tmp.height), Image.LANCZOS)


_BG = None


def game_bg(i, n_frames=99):
    """游戏自己的像素海底（标题页 ui/title_deep/bg.png，428×240）×5 最近邻；整段缓慢右移 40 px（每像素格 5 px 的整数步）；
    一束顶光、远处标题页像素水母慢漂、方块海雪上浮（11-08 用户：背景用我们的像素背景）"""
    global _BG
    from PIL import ImageEnhance
    if _BG is None:
        bg = Image.open(ART + "/ui/title_deep/bg.png").convert("RGB")
        bg = bg.resize((bg.width * 5, bg.height * 5), Image.NEAREST)
        _BG = ImageEnhance.Color(bg).enhance(0.75)
    pan = int(40 * i / max(1, n_frames)) // 5 * 5
    x0 = (_BG.width - W) // 2 - 20 + pan
    y0 = (_BG.height - H) // 2
    img = _BG.crop((x0, y0, x0 + W, y0 + H)).convert("RGBA")
    shaft = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shaft).polygon([(1240, LB), (1480, LB), (1680, H - LB), (1060, H - LB)], fill=46)
    img.paste((170, 235, 240, 255), (0, 0), shaft.filter(ImageFilter.GaussianBlur(30)))
    for j, (x, y, kk) in enumerate(((300, 210, 2), (760, 160, 1), (1760, 260, 2))):
        jf = Image.open(ART + "/ui/title_deep/jelly_%d.png" % (j % 3)).convert("RGBA")
        jf = jf.resize((jf.width * kk, jf.height * kk), Image.NEAREST)
        jf.putalpha(jf.getchannel("A").point(lambda a: int(a * 0.35)))
        img.alpha_composite(jf, (x, int(y - i * 0.25 * kk) // 5 * 5))
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    rnd = random.Random(5)
    for _ in range(140):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        sz = rnd.choice((1, 1, 2, 3)) * 4
        yy = (y - i * (0.3 + sz * 0.05)) % H
        d.rectangle((x // 4 * 4, yy // 4 * 4, x // 4 * 4 + sz, yy // 4 * 4 + sz), fill=(200, 240, 245, rnd.randint(60, 160)))
    img.alpha_composite(lay)
    return img


def render(bg_dir, out_dir, op, n_frames=None):
    code, cn, icon, cls, intro, idx = OPS[op]
    seq = _frames(op)
    h0 = seq[0][0][0].height
    k = max(1, round((H - 2 * LB) * 0.88 / h0))   # 整数倍，人物（含伞）占画面内高约 88%
    print("OPCARD", op, "frame h", h0, "k", k)
    nm = condensed(code, T.latin(230, True))
    bgs = sorted(f for f in os.listdir(bg_dir) if f.endswith(".png")) if bg_dir != "game" else ["game"] * (n_frames or 99)
    os.makedirs(out_dir, exist_ok=True)
    rnd = random.Random(3)
    for i, fn in enumerate(bgs):
        t = i / FPS
        im = game_bg(i, len(bgs)) if fn == "game" else Image.open(os.path.join(bg_dir, fn)).convert("RGBA")
        # 干员：右侧，脚底贴画面下缘
        fr = _frame_at(seq, t)
        opi = fr.resize((fr.width * k, fr.height * k), Image.NEAREST)
        ox, oy = 1300 - opi.width // 2, H - LB - opi.height + 8   # 偏右，避开背景灯塔
        rim = Image.new("RGBA", opi.size, (94, 230, 230, 0))
        rim.putalpha(opi.getchannel("A"))
        im.alpha_composite(rim, (ox - 6, oy - 6))
        im.alpha_composite(opi, (ox, oy))
        d = ImageDraw.Draw(im)
        # 左上 2×2 小方格
        for (x, y, s) in ((120, 236, 10), (160, 270, 8)):
            d.rectangle((x, y, x + s, y + s), fill=T.INK)
            d.rectangle((x + s, y + s, x + 2 * s, y + 2 * s), fill=T.INK)
        T.tracked(d, (124, 330), "‹  方舟幸存者  ›", T.sans(22, 500), T.INK, 0.08)
        # 超大代号：前 5 帧故障出字
        nx, ny = 112, 372
        if i < 5:
            tint = Image.new("RGBA", nm.size, (94, 230, 230, 255))
            tint.putalpha(nm.getchannel("A").point(lambda a: int(a * 0.8)))
            im.alpha_composite(tint, (nx + rnd.randint(8, 24), ny))
            hh = nm.height // 5
            for kk in range(5):
                if rnd.random() < 0.3 + i * 0.15:
                    sl = nm.crop((0, kk * hh, nm.width, (kk + 1) * hh))
                    im.alpha_composite(sl, (nx + rnd.randint(-50, 50) * (5 - i) // 5, ny + kk * hh))
        else:
            im.alpha_composite(nm, (nx, ny))
        # 小字簇：第 6 帧起淡入
        a = ease((i - 6) / 8)
        if a > 0:
            lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
            ld = ImageDraw.Draw(lay)
            y2 = ny + nm.height + 34
            T.tracked(ld, (124, y2), cn, T.serif(56, 700), T.INK + (255,), 0.2)
            ic = Image.open(ART + "/ui/professions/%s.png" % icon).convert("RGBA")
            cw = int(T.tracked(ImageDraw.Draw(Image.new("RGBA", (4, 4))), (0, 0), cn, T.serif(56, 700), (0, 0, 0, 0), 0.2))
            lay.alpha_composite(ic, (124 + cw + 36, y2 + 14))
            T.tracked(ld, (124 + cw + 36 + ic.width + 16, y2 + 22), cls, T.sans(22, 500), T.INK_DIM + (255,), 0.1)
            if intro:
                T.tracked(ld, (124, y2 + 92), intro, T.sans(18, 400), (150, 166, 178, 255), 0.04)
            rx = 1620
            T.tracked(ld, (rx, 560), "OPERATOR  %02d" % idx, T.latin(22, True), T.INK + (255,), 0.12)
            ld.line((rx, 594, rx + 240, 594), fill=T.INK + (255,), width=2)
            T.tracked(ld, (W - 112, H - LB - 40), "%02d / 03" % idx, T.latin(14, False), (150, 166, 178, 255), 0.4, "r")
            lay.putalpha(lay.getchannel("A").point(lambda v: int(v * a)))
            im.alpha_composite(lay)
        out = T.letterbox_post(im.convert("RGB"), i, bars=False)
        d2 = ImageDraw.Draw(out)
        d2.rectangle((0, 0, W, LB), fill=(0, 0, 0)); d2.rectangle((0, H - LB, W, H), fill=(0, 0, 0))
        out.save(os.path.join(out_dir, "c%04d.png" % i))
    return len(bgs)


if __name__ == "__main__":
    print(render(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else None))
