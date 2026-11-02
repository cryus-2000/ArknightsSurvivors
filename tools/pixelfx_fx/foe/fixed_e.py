# -*- coding: utf-8 -*-
"""组 E 固定格式帧条导出（docs/236）：给「代码写死帧数 / 网格 / 画布」的件用，tools/pixelfx_export.py 的自动裁边对不上它们。
按 FIXED 表：用 ak_layers.mjs 渲染 color 层 → 以原点为基准裁固定框 → 帧数等间隔重采样到代码要的数量 → 多个种子按行拼网格 → 32 色调色板 PNG。
不出 _glow（这些件由 bullet_fx / world 自己画四边形，不走 vfx.px_glow）。

    python tools/pixelfx_fx/foe/fixed_e.py [--lib <pixelfx 检出>]
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SRC = os.path.join(ROOT, "tools", "pixelfx_fx")
OUT = os.path.join(ROOT, "game", "art", "fx")

# 名字 → fx、opts、裁框（相对原点：左、上、宽、高，纹素）、帧数、种子（每个种子一行）、文件后缀
FIXED = {
    # Boss 弹迸散：bullet_fx 按 8 列 × 3 行网格取帧（行随机、帧 = min(7, el / 0.45 × 8)），帧 20×20，画成 40 世界像素，代码按弹色着色
    "fx_e_px_bpop": {"fps": 17.8, "fx": "impacts/ak-e-hit", "opts": {"R": 8, "kind": "shard", "ramp": "grey", "n": 6, "tail": 0.15, "light": 0},
                     "box": [-10, -10, 20, 20], "frames": 8, "seeds": [1, 2, 3], "suffix": "@2x"},
    # Boss 弹拖尾：bullet_fx 4 帧循环、帧 16×9，右端贴弹尾、按速度拉长，代码按弹色着色
    "fx_e_px_btrail": {"fps": 14.0, "fx": "projectiles/ak-e-proj", "opts": {"R": 8, "kind": "trail", "ramp": "grey", "light": 0},
                       "box": [-15, -4, 16, 9], "frames": 4, "seeds": [1], "suffix": "@2x"},
    # 囊海破膜：world.gd 写死 6 帧 16 fps、锚点 (0.5, 0.7)，_back 画在本体前（远半）、_front 画在本体后（近半）；1 纹素 = 2 世界像素（enemy_scale）
    "fx_e_px_pocket_burst_back": {"fps": 16.0, "fx": "impacts/ak-e-sac", "opts": {"R": 78, "kind": "goo", "half": -1, "n": 14, "tail": 0.05},
                                  "box": [-90, -112, 180, 160], "frames": 6, "seeds": [7], "suffix": ""},
    "fx_e_px_pocket_burst_front": {"fps": 16.0, "fx": "impacts/ak-e-sac", "opts": {"R": 78, "kind": "goo", "half": 1, "n": 14, "tail": 0.05},
                                   "box": [-90, -112, 180, 160], "frames": 6, "seeds": [7], "suffix": ""},
    # 骑士终局冰材质（final_boss_materials.gd，scale 1.0 = 1 纹素 1 世界像素，锚点 = 脚底）：按代码的帧窗口排布各阶段
    #   晶簇 64×128：rise 7 / hold 3（循环）/ break 10，锚点 (0.5, 124/128)
    "fx_e_px_knight_crystal_rise": {"fps": 28.0, "fx": "impacts/ak-e-ice", "opts": {"shape": "crystal", "phase": "rise", "H": 100},
                                    "box": [-32, -124, 64, 128], "frames": 7, "seeds": [5], "suffix": ""},
    "fx_e_px_knight_crystal_hold": {"fps": 8.0, "fx": "impacts/ak-e-ice", "opts": {"shape": "crystal", "phase": "hold", "H": 100},
                                    "box": [-32, -124, 64, 128], "frames": 3, "seeds": [5], "suffix": ""},
    "fx_e_px_knight_crystal_break": {"fps": 32.0, "fx": "impacts/ak-e-ice", "opts": {"shape": "crystal", "phase": "break", "H": 100},
                                     "box": [-32, -124, 64, 128], "frames": 10, "seeds": [5], "suffix": ""},
    #   冰浪冠 48×32 × 11：代码循环取 2..6 → 0–1 升、2–6 持续循环、7–10 碎；锚点 (0.5, 0.94)
    "fx_e_px_knight_ice_crest": {"fps": 30.0, "fx": "impacts/ak-e-ice", "opts": {"shape": "crest", "H": 24}, "box": [-24, -30, 48, 32], "frames": 11, "seeds": [9], "suffix": "",
                                 "segments": [{"phase": "rise", "n": 2}, {"phase": "hold", "n": 5}, {"phase": "break", "n": 4}]},
    #   冰墙段 64×64 × 36：代码用 10–17 升、17–19 持续、23–35 碎（0–9、20–22 不显示，填邻帧）；锚点 (0.5, 60/64)
    "fx_e_px_knight_ice_wall": {"fps": 30.0, "fx": "impacts/ak-e-ice", "opts": {"shape": "wall", "H": 52}, "box": [-32, -60, 64, 64], "frames": 36, "seeds": [13], "suffix": "",
                                "segments": [{"phase": "rise", "n": 8}, {"phase": "hold", "n": 3}, {"phase": "break", "n": 13}],
                                "layout": [[0, 0]] * 10 + [[0, i] for i in range(7)] + [[1, 0], [1, 1], [1, 2]] + [[1, 2]] * 3 + [[2, i] for i in range(13)]},
}


def resample(frames, n, loop=False):
    """等间隔取 n 帧；loop（循环段，如 hold）：最后一帧 = 首帧的重复，去掉后按不含终点等分，首尾才接得上"""
    while frames and frames[-1].getbbox() is None and len(frames) > n:
        frames = frames[:-1]
    if loop:
        frames = frames[:-1]
        return [frames[int(i * len(frames) / n)] for i in range(n)]
    return frames if len(frames) == n else [frames[min(len(frames) - 1, round(i * (len(frames) - 1) / max(1, n - 1)))] for i in range(n)]


def install(lib):
    shutil.copy2(os.path.join(SRC, "house.js"), os.path.join(lib, "src", "fx", "house.js"))
    shutil.copy2(os.path.join(SRC, "ak_layers.mjs"), os.path.join(lib, "tools", "ak_layers.mjs"))
    for cat in os.listdir(SRC):
        d = os.path.join(SRC, cat)
        if os.path.isdir(d):
            os.makedirs(os.path.join(lib, "src", "fx", cat), exist_ok=True)
            for f in os.listdir(d):
                if f.endswith(".js"):
                    shutil.copy2(os.path.join(d, f), os.path.join(lib, "src", "fx", cat, f))


def render(lib, fx, opts, seed, tmp):
    out = os.path.join(tmp, "%s_%d" % (fx.replace("/", "_"), seed))
    r = subprocess.run(["node", "tools/ak_layers.mjs", fx, "--opts", json.dumps(opts), "--out", out, "--seed", str(seed)], cwd=lib, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    m = json.load(open(os.path.join(out, "meta.json")))
    col = Image.open(os.path.join(out, "color.png")).convert("RGBA")
    fw, fh = m["frameSize"]
    return [col.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(m["frames"])], m["pivot"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=os.path.join(ROOT.split(os.sep + ".claude" + os.sep)[0], "build", "pixelfx"))
    a = ap.parse_args()
    install(a.lib)
    with tempfile.TemporaryDirectory() as tmp:
        for name, sp in FIXED.items():
            bx, by, bw, bh = sp["box"]
            rows = []
            for seed in sp["seeds"]:
                n = sp["frames"]
                if "segments" in sp:   # 多段：各段单独渲染、重采样，按 layout（[段, 帧]）或顺序拼
                    segs = []
                    for sg in sp["segments"]:
                        fr, (ox, oy) = render(a.lib, sp["fx"], dict(sp["opts"], phase=sg["phase"]), seed, tmp)
                        segs.append(resample(fr, sg["n"], sg["phase"] == "hold"))
                    pick = [segs[i][j] for i, j in sp["layout"]] if "layout" in sp else [f for sg in segs for f in sg]
                    frames = pick
                else:
                    frames, (ox, oy) = render(a.lib, sp["fx"], sp["opts"], seed, tmp)
                    pick = resample(frames, n, sp["opts"].get("phase") == "hold")
                assert len(pick) == n, (name, len(pick))
                row = Image.new("RGBA", (bw * n, bh), (0, 0, 0, 0))
                for i, f in enumerate(pick):
                    row.paste(f.crop((ox + bx, oy + by, ox + bx + bw, oy + by + bh)), (i * bw, 0))
                rows.append((row, len(frames)))
            grid = Image.new("RGBA", (bw * sp["frames"], bh * len(rows)), (0, 0, 0, 0))
            for i, (r, _) in enumerate(rows):
                grid.paste(r, (0, i * bh))
            p = os.path.join(OUT, name + sp["suffix"] + ".png")
            grid.quantize(colors=32, method=Image.Quantize.FASTOCTREE).save(p, optimize=True)
            print("%s%s  %d 列 × %d 行，帧 %d×%d（源 %s 帧），%.1f KB" % (name, sp["suffix"], sp["frames"], len(rows), bw, bh, "/".join(str(k) for _, k in rows), os.path.getsize(p) / 1024))


if __name__ == "__main__":
    main()
