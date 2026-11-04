#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""成长看得见截图（docs/245 §5）：同种子同一干员精零 / 精一 / 精二对照 + 精英化瞬间（云端 xvfb + opengl3，参照 late_game_diag_shots.py）。

用法（仓库根目录，Linux 云端）：
    python tools/elite_moment_shots.py shoot --ops texas,exusiai --seed 11
    python tools/elite_moment_shots.py sheet --out docs/assets/elite_moment
做法：
  · 对照：--prog=0 / 3 / 6（开局把全队推到精零 / 精一 / 精二），同种子，第 SHOT_T 秒各拍一张；两开关开（on）与全关（off）各一组。
  · 瞬间：--prog=0 + --eliteat=60（到 60 秒把队长推到精二），从触发前 1 帧起连拍；两开关开。
  · 非实时平衡模式约 0.0659 局内秒 / 渲染帧；平衡模式不定格（定格只在玩家局），横幅 / 爆亮 / 光柱按真实时间照画。
"""
import argparse, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

SHOT = os.path.join(ROOT, "build", "elite_moment", "shots")
SPF = 0.0659
SHOT_T = 40
ELITE_AT = 60
MOMENT_K = [2, 5, 10, 18, 30, 50, 80]   # 平衡模式每个渲染帧 = 8 个模拟步（shot 帧号按模拟步数）：触发后第 k 个渲染帧 = k / 60 秒真实时间
ON = ["--bal=growth/elite_show=1", "--bal=growth/visible_nodes=1"]


def run(op, seed, tag, extra, frames, maxt):
    d = os.path.join(SHOT, "%s_s%d_%s" % (op, seed, tag))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GR.find_godot(), "--rendering-driver", "opengl3", "--path", os.path.join(ROOT, "game"),
            "--resolution", "1280x720", "--audio-driver", "Dummy", "--fixed-fps", "60", "--",
            "--balance", "--nodeath", "--seed=%d" % seed, "--op=" + op, "--maxt=%d" % maxt,
            "--shots=" + ",".join(str(f) for f in frames), "--shotdir=" + d] + extra
    p = subprocess.run(args, capture_output=True, text=True, timeout=5400)
    errs = [l for l in (p.stdout + p.stderr).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    return tag, op, len(os.listdir(d)), errs[:3]


def cmd_shoot(a):
    f0 = int(round(SHOT_T / SPF))
    fe = int(round(ELITE_AT / SPF))
    jobs = []
    for op in a.ops.split(","):
        for pg in (0, 3, 6):
            jobs.append((op, a.seed, "p%d_on" % pg, ON + ["--prog=%d" % pg], [f0], SHOT_T + 3))
            jobs.append((op, a.seed, "p%d_off" % pg, ["--prog=%d" % pg], [f0], SHOT_T + 3))
        jobs.append((op, a.seed, "moment", ON + ["--eliteat=%d" % ELITE_AT], [fe - 8] + [fe + 8 * k for k in MOMENT_K], ELITE_AT + 60))
    with ThreadPoolExecutor(a.jobs) as ex:
        for r in ex.map(lambda j: run(*j), jobs):
            print(r, flush=True)


def _font(sz):
    from PIL import ImageFont
    for p in [os.path.join(ROOT, "game", "fonts", "ui.ttf"), "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
              os.path.join(ROOT, "game", "fonts", "NotoSansSC-Regular.otf")]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    for r, _, fs in os.walk(os.path.join(ROOT, "game")):
        for f in fs:
            if f.lower().endswith((".ttf", ".otf")) and ("sc" in f.lower() or "cjk" in f.lower() or "hans" in f.lower()):
                return ImageFont.truetype(os.path.join(r, f), sz)
    return ImageFont.load_default()


def _crop(path, box=(360, 170, 920, 530), k=1):
    from PIL import Image
    im = Image.open(path).convert("RGB").crop(box)
    return im.resize((im.width * k, im.height * k), Image.NEAREST) if k > 1 else im


def _label(im, txt):
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    f = _font(22)
    d.rectangle((0, 0, im.width, 34), fill=(8, 12, 20))
    d.text((10, 4), txt, fill=(235, 240, 245), font=f)
    return im


def cmd_sheet(a):
    from PIL import Image
    os.makedirs(a.out, exist_ok=True)
    f0 = int(round(SHOT_T / SPF))
    names = {0: "精零", 3: "精一", 6: "精二"}
    for op in a.ops.split(","):
        rows = []
        for arm, zh in (("off", "开关关（现状）"), ("on", "开关开")):
            ims = []
            for pg in (0, 3, 6):
                p = os.path.join(SHOT, "%s_s%d_p%d_%s" % (op, a.seed, pg, arm), "shot_%d.png" % f0)
                if os.path.exists(p):
                    shutil.copy(p, os.path.join(a.out, "%s_p%d_%s.png" % (op, pg, arm)))
                    ims.append(_label(_crop(p), "%s · %s · %s · %d 秒" % (op, names[pg], zh, SHOT_T)))
            if ims:
                row = Image.new("RGB", (sum(i.width for i in ims) + 8 * (len(ims) - 1), ims[0].height), (8, 12, 20))
                x = 0
                for i in ims:
                    row.paste(i, (x, 0))
                    x += i.width + 8
                rows.append(row)
        if rows:
            sh = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows) + 8 * (len(rows) - 1)), (8, 12, 20))
            y = 0
            for r in rows:
                sh.paste(r, (0, y))
                y += r.height + 8
            sh.save(os.path.join(a.out, "stages_%s.png" % op))
        md = os.path.join(SHOT, "%s_s%d_moment" % (op, a.seed))
        if os.path.isdir(md):
            fs = sorted(os.listdir(md), key=lambda s: int(s[5:-4]))
            pick = [fs[i] for i in (1, 2, 4, 6) if i < len(fs)]
            for fn in fs:
                shutil.copy(os.path.join(md, fn), os.path.join(a.out, "moment_%s_%s" % (op, fn)))
            ims = [_label(_crop(os.path.join(md, fn), (0, 80, 1280, 620)), "%s · 精英化瞬间 · 第 %s 帧" % (op, fn[5:-4])) for fn in pick]
            if ims:
                w = ims[0].width
                sh = Image.new("RGB", (w * 2 + 8, ims[0].height * ((len(ims) + 1) // 2) + 8), (8, 12, 20))
                for i, im in enumerate(ims):
                    sh.paste(im, ((i % 2) * (w + 8), (i // 2) * (im.height + 8)))
                sh.save(os.path.join(a.out, "moment_%s.png" % op))
    print("sheet ->", a.out)


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd")
    s = sp.add_parser("shoot")
    s.add_argument("--ops", default="texas,exusiai")
    s.add_argument("--seed", type=int, default=11)
    s.add_argument("--jobs", type=int, default=2)
    q = sp.add_parser("sheet")
    q.add_argument("--ops", default="texas,exusiai")
    q.add_argument("--seed", type=int, default=11)
    q.add_argument("--out", default=os.path.join(ROOT, "docs", "assets", "elite_moment"))
    a = ap.parse_args()
    if a.cmd == "shoot":
        cmd_shoot(a)
    elif a.cmd == "sheet":
        cmd_sheet(a)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
