# -*- coding: utf-8 -*-
"""Boss 改版逐幕演示 gif（docs/142b §9）：逐个开窗口局（走 godot_runner：副屏 / 屏幕外、静音、全机并发上限），
--autotest --bossacts=<spec> 让 Boss 按自己的 AI 出招、每 7 秒过一道卡点，每 3 帧截一张；再拼成 gif（10 帧 / 秒，裁中间 16:9 区域缩到 480 宽）
和一张逐幕对照图（每幕中段一帧）。一次只开 1 个 Godot；结束靠进程自己退出（超时由 godot_runner 按自己的 PID 结束）。

    python tools/probes/boss_act_gifs.py                    # 其余 8 只（docs/142b §9 表）
    python tools/probes/boss_act_gifs.py carmen paranoia    # 只跑这几只
    python tools/probes/boss_act_gifs.py --gif-only carmen  # 不重跑，只用已有截图重拼
输出 build/boss_acts/<spec>/（截图、run.log）与 build/boss_acts/<spec>.gif、build/boss_acts/sheet.png
"""
import os, shutil, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

DEFAULT = ["carmen", "path", "bishop+archon", "bishop+immortal", "paranoia", "ishar", "izumik"]
OUT = os.path.join(ROOT, "build", "boss_acts")
W = 480


def run(spec):
    out = os.path.join(OUT, spec.replace("+", "_"))
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--autotest", "--seed=1", "--op=mizuki", "--bossacts=" + spec, "--shotdir=" + out.replace(os.sep, "/")]
    o, e, to = gr.run_godot(args, 400)
    open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    gates = [ln for ln in o.splitlines() if ln.startswith("BOSSACTS")]
    n = len([f for f in os.listdir(out) if f.endswith(".png")])
    print(spec, "shots:", n, "errors:", gr.script_errors(o, e)[:5], "timeout" if to else "", "|", " / ".join(gates))
    return out, gates


def frames(out):
    fs = sorted(f for f in os.listdir(out) if f.startswith("shot_acts_") and f.endswith(".png"))
    ims = []
    for f in fs:
        im = Image.open(os.path.join(out, f)).convert("RGB")
        w, h = im.size
        cw, ch = int(w * 0.8), int(w * 0.8 * 9 / 16)   # 裁中间 80% 宽的 16:9（Boss 与队长都在中间）
        x0, y0 = (w - cw) // 2, max(0, (h - ch) // 2)
        ims.append(im.crop((x0, y0, x0 + cw, y0 + ch)).resize((W, int(W * 9 / 16)), Image.LANCZOS))
    return fs, ims


def make_gif(spec, out):
    fs, ims = frames(out)
    if not ims:
        print(spec, "没有截图")
        return []
    pal = [im.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for im in ims]
    p = os.path.join(OUT, spec.replace("+", "_") + ".gif")
    pal[0].save(p, save_all=True, append_images=pal[1:], duration=100, loop=0, optimize=True, disposal=1)
    print(p, "%.1f MB" % (os.path.getsize(p) / 1048576.0), len(ims), "帧")
    return ims


def sheet(rows):
    """rows：[(spec, [每幕中段一帧 Image])]"""
    if not rows:
        return
    cols = max(len(r[1]) for r in rows)
    th = int(W * 9 / 16)
    lab = 120
    im = Image.new("RGB", (lab + cols * (W + 6), len(rows) * (th + 6)), (12, 14, 20))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
    except OSError:
        font = None
    for i, (spec, acts) in enumerate(rows):
        y = i * (th + 6)
        d.text((8, y + th // 2 - 10), spec, fill=(230, 230, 230), font=font)
        for j, a in enumerate(acts):
            im.paste(a, (lab + j * (W + 6), y))
            d.text((lab + j * (W + 6) + 6, y + 4), "第 %d 幕" % (j + 1), fill=(255, 230, 150), font=font)
    p = os.path.join(OUT, "sheet.png")
    im.save(p, optimize=True)
    print(p)


def main():
    args = sys.argv[1:]
    gif_only = "--gif-only" in args
    specs = [a for a in args if not a.startswith("--")] or DEFAULT
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for spec in specs:
        out = os.path.join(OUT, spec.replace("+", "_"))
        if not gif_only:
            out, _ = run(spec)
        ims = make_gif(spec, out)
        if ims:
            per = 70   # 7 秒一幕、每 3 帧一张 → 每幕约 70 张；取每幕中段
            acts = [ims[min(len(ims) - 1, k * per + per // 2)] for k in range((len(ims) + per - 1) // per)]
            rows.append((spec, acts))
    sheet(rows)


if __name__ == "__main__":
    main()
