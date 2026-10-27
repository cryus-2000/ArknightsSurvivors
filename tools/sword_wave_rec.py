# -*- coding: utf-8 -*-
"""剑气非线性速度改前 / 改后对照 gif（用户 10-27，sword_ease.gd）：拉普兰德远掷剑气（lap）、德克萨斯吃藏品剑气（qi）
各跑两次同一场景（--bal=sword_ease/on=0 / 1），逐帧左右拼成一张，1/3 速输出到 build/sword_wave_speed/<类>.gif。
开窗口走 godot_runner（屏幕外、不抢焦点、静音）。

用法：python tools/sword_wave_rec.py [lap qi]
"""
import os, sys, glob, shutil
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "build", "sword_wave_speed")
RAW = os.path.join(OUT, "raw")
LABEL = {"lap": "拉普兰德 · 领主剑气", "qi": "德克萨斯 · 锈蚀刀片 + 老近卫军之锋剑气"}
OPS = {"lap": "lappland", "qi": "texas"}
CROP = 230   # 以画面中心为心的半边宽（像素）
STEP = 1     # 逐帧（剑气只飞 0.4 秒，抽帧会漏掉出手那几帧）
ZOOM = 1.3   # 裁下来再放大（最近邻，保留像素感）
SLOW = 3     # 1/3 速


def run(case, on):
    godot = GR.find_godot()
    out, err, to = GR.run_godot([godot, "--path", GAME, "res://tests/sword_wave_capture.tscn", "--",
                                 "--balance", "--seed=1", "--op=" + OPS[case], "--sw_case=" + case, "--sw_frames=150",
                                 "--bal=sword_ease/on=%d" % on, "--sw_out=" + os.path.join(RAW, str(on))], 300)
    ok = "SW CAPTURE done" in out
    if not ok:
        print(case, on, "失败", (out + err)[-1500:])
    return ok


def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", os.path.join(GAME, "fonts", "ui_fallback.otf")]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def compose(case):
    a = sorted(glob.glob(os.path.join(RAW, "0", case + "_*.png")))
    b = sorted(glob.glob(os.path.join(RAW, "1", case + "_*.png")))
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
        d.text((10, 5), "改前（匀速）", fill=(220, 220, 230), font=f)
        d.text((cw + 16, 5), "改后（爆发出手 → 衰减滑行）  " + LABEL[case], fill=(255, 220, 140), font=f)
        frames.append(im.quantize(colors=128, method=Image.Quantize.MEDIANCUT))
    path = os.path.join(OUT, case + ".gif")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 / 60 * STEP * SLOW), loop=0, optimize=True)
    print("写出", path, len(frames), "帧")
    return path


def main():
    cases = sys.argv[1:] or ["lap", "qi"]
    for c in cases:
        for on in ("0", "1"):
            os.makedirs(os.path.join(RAW, on), exist_ok=True)
            for p in glob.glob(os.path.join(RAW, on, c + "_*.png")):
                os.remove(p)
    jobs = [(c, on) for c in cases for on in (0, 1)]
    with ThreadPoolExecutor(3) as ex:
        res = list(ex.map(lambda j: run(*j), jobs))
    if not all(res):
        sys.exit(1)
    for c in cases:
        compose(c)
    shutil.rmtree(RAW, ignore_errors=True)   # 静帧用完即删（10-27 口径：给用户只看 gif）


if __name__ == "__main__":
    main()
