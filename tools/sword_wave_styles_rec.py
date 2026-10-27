# -*- coding: utf-8 -*-
"""藏品剑气按武器分类的对照 gif（用户 10-27，docs/170 §7）：同一场景、同 seed，德克萨斯 / 推进之王 / 艾丽妮 / 星熊 / 乌尔比安 / 归溟幽灵鲨
各拿锈蚀刀片 + 老近卫军之锋跑一次，3 × 2 宫格；出原速（30 帧 / 秒）与 1/3 速两张到 build/sword_wave_speed/styles_1x.gif、styles_slow.gif。
开窗口走 godot_runner（屏幕外、不抢焦点、静音）。

用法：python tools/sword_wave_styles_rec.py
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
RAW = os.path.join(OUT, "raw", "styles")
OPS = [("texas", "德克萨斯 · 刀剑一字斩"), ("siege", "推进之王 · 钝器冲击波"), ("irene", "艾丽妮 · 细剑突刺"),
       ("hoshiguma", "星熊 · 盾冲击波"), ("ulpianus", "乌尔比安 · 锚冲击波"), ("specter_unchained", "归溟幽灵鲨 · 通用（待做）")]
COLS = 3
FRAMES = 150
ZOOM = 1.0


def run(op):
    out, err, to = GR.run_godot([GR.find_godot(), "--path", GAME, "res://tests/sword_wave_capture.tscn", "--",
                                 "--balance", "--seed=1", "--op=" + op, "--sw_case=qi", "--sw_frames=%d" % FRAMES,
                                 "--sw_tag=" + op, "--sw_out=" + RAW], 300)
    ok = "SW CAPTURE done" in out
    if not ok:
        print(op, "失败", (out + err)[-1500:])
    return ok


def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", os.path.join(GAME, "fonts", "ui_fallback.otf")]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def compose(step, ms, name):
    f = font(17)
    seqs = [sorted(glob.glob(os.path.join(RAW, op + "_*.png"))) for op, _ in OPS]
    n = min(len(s) for s in seqs)
    frames = []
    for i in range(0, n, step):
        cells = []
        for s in seqs:
            im = Image.open(s[i]).convert("RGB")
            w, h = im.size
            c = im.crop((w // 2 - 70, h // 2 - 110, w // 2 + 250, h // 2 + 200))   # 剑气朝右下最近的敌人飞（队长在左上角）
            cells.append(c.resize((int(c.width * ZOOM), int(c.height * ZOOM)), Image.NEAREST))
        cw, ch = cells[0].size
        rows = (len(cells) + COLS - 1) // COLS
        im = Image.new("RGB", (cw * COLS + 6 * (COLS - 1), (ch + 28) * rows), (12, 14, 20))
        d = ImageDraw.Draw(im)
        for k, c in enumerate(cells):
            x, y = (k % COLS) * (cw + 6), (k // COLS) * (ch + 28)
            im.paste(c, (x, y + 28))
            d.text((x + 8, y + 4), OPS[k][1], fill=(255, 220, 140), font=f)
        frames.append(im.quantize(colors=128, method=Image.Quantize.MEDIANCUT))
    path = os.path.join(OUT, name)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=ms, loop=0, optimize=True)
    print("写出", path, len(frames), "帧")


def main():
    os.makedirs(RAW, exist_ok=True)
    for p in glob.glob(os.path.join(RAW, "*.png")):
        os.remove(p)
    with ThreadPoolExecutor(6) as ex:
        res = list(ex.map(run, [op for op, _ in OPS]))
    if not all(res):
        sys.exit(1)
    compose(2, 33, "styles_1x.gif")     # 原速：隔帧取、每张 33 ms
    compose(1, 50, "styles_slow.gif")   # 1/3 速：逐帧、每张 50 ms
    shutil.rmtree(RAW, ignore_errors=True)   # 静帧用完即删（10-27 口径：给用户只看 gif）


if __name__ == "__main__":
    main()
