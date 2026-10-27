# -*- coding: utf-8 -*-
"""可见成长藏品拿到前 / 后对照 gif（docs/163 §8 第 5 步）：每类（远程 / 近战 / 召唤）跑两次同一场景（--vg_on=0 / 1），
逐帧左右拼成一张，1/3 速输出到 build/visible_growth/<类>.gif。开窗口走 godot_runner（屏幕外、不抢焦点、静音）。

用法：python tools/vis_growth_rec.py [ranged melee summon]
"""
import os, sys, glob
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "build", "visible_growth")
RAW = os.path.join(OUT, "raw")
LABEL = {"ranged": ("能天使", "银餐叉 + 左轮弹巢"), "melee": ("拉普兰德", "锈蚀刀片 + 赶车夫的长鞭"), "summon": ("维什戴尔精二", "散轶诗简 + 衍生者终端")}
CROP = 230   # 以画面中心为心的半边宽（像素）
STEP = 3     # 每 3 帧取一张（60 帧 → 20 张 / 秒）
ZOOM = 1.3   # 裁下来再放大（最近邻，保留像素感）
SLOW = 3     # 1/3 速


def run(case, on):
    godot = GR.find_godot()
    out, err, to = GR.run_godot([godot, "--path", GAME, "res://tests/vis_growth_capture.tscn", "--",
                                 "--balance", "--seed=1", "--op=" + {"ranged": "exusiai", "melee": "lappland", "summon": "wisadel"}[case],
                                 "--vg_case=" + case, "--vg_on=%d" % on, "--vg_out=" + RAW], 300)
    ok = "VG CAPTURE done" in out
    if not ok:
        print(case, on, "失败", (out + err)[-1500:])
    return ok


def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", os.path.join(GAME, "fonts", "ui_fallback.otf")]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def compose(case):
    a = sorted(glob.glob(os.path.join(RAW, case + "_0_*.png")))
    b = sorted(glob.glob(os.path.join(RAW, case + "_1_*.png")))
    n = min(len(a), len(b))
    f = font(18)
    frames = []
    for i in range(0, n, STEP):
        ia, ib = Image.open(a[i]).convert("RGB"), Image.open(b[i]).convert("RGB")
        w, h = ia.size
        box = (w // 2 - int(CROP * 0.55), h // 2 - int(CROP * 0.8), w // 2 + int(CROP * 1.15), h // 2 + int(CROP * 0.45))
        ca, cb = ia.crop(box), ib.crop(box)
        ca = ca.resize((int(ca.width * ZOOM), int(ca.height * ZOOM)), Image.NEAREST)
        cb = cb.resize((int(cb.width * ZOOM), int(cb.height * ZOOM)), Image.NEAREST)
        cw, ch = ca.size
        im = Image.new("RGB", (cw * 2 + 6, ch + 30), (12, 14, 20))
        im.paste(ca, (0, 30))
        im.paste(cb, (cw + 6, 30))
        d = ImageDraw.Draw(im)
        who, rel = LABEL[case]
        d.text((10, 5), who + " · 拿到前", fill=(220, 220, 230), font=f)
        d.text((cw + 16, 5), who + " · 拿到后（" + rel + "）", fill=(255, 220, 140), font=f)
        frames.append(im.quantize(colors=128, method=Image.Quantize.MEDIANCUT))
    path = os.path.join(OUT, case + ".gif")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 / 60 * STEP * SLOW), loop=0, optimize=True)
    print("写出", path, len(frames), "帧")
    return path


def main():
    cases = sys.argv[1:] or ["ranged", "melee", "summon"]
    os.makedirs(RAW, exist_ok=True)
    for c in cases:
        for p in glob.glob(os.path.join(RAW, c + "_*.png")):
            os.remove(p)
    jobs = [(c, on) for c in cases for on in (0, 1)]
    with ThreadPoolExecutor(3) as ex:
        res = list(ex.map(lambda j: run(*j), jobs))
    if not all(res):
        sys.exit(1)
    for c in cases:
        compose(c)


if __name__ == "__main__":
    main()
