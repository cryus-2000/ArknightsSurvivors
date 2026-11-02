# -*- coding: utf-8 -*-
"""pixelfx 特效导出成游戏帧条（docs/228 §7）。

tools/pixelfx_fx/<类>/<名>.js 是本作写的 pixelfx 特效源码；本脚本把它们拷进 pixelfx 库检出（缺省 build/pixelfx，
不进 git），用库自带的 render.mjs --sheet 导精灵表，再：
  - 以原点为中心对称裁边（游戏按帧中心放置；枪口这类非居中的用 keep_canvas 保留原画布），
  - 去掉末尾全空帧，
  - 量化到 ≤ 64 色（带透明），
  - 拼成单行横向帧条写进 game/art/fx/<名>[ @2x].png。
最后打印 art.gd V6_FRAMES 要登记的 [帧数, fps]。改完记得跑 python tools/asset_index.py。

用法：python tools/pixelfx_export.py [--lib build/pixelfx] [--only 名字,...] [--dry]
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "tools", "pixelfx_fx")
OUT = os.path.join(ROOT, "game", "art", "fx")

EXU = {
    "s1": ["#0a2240", "#12528a", "#48ccff", "#b8f2ff", "#f0fdff", "#ffffff"],
    "s2": ["#3a1606", "#b04e10", "#ff9a2e", "#ffdca4", "#fffaec", "#ffffff"],
    "s3": ["#4a0a14", "#d42a3a", "#ff7a7a", "#ffd0c8", "#fff4ee", "#ffffff"],
}

# 游戏贴图名 → (特效 id, 选项, 是否 @2x, 是否保留原画布)
TARGETS = {
    "fx_skadi_px_sweep": ("melee/ak-skadi-sweep", {}, False, False),
    "fx_skadi_px_cleave": ("melee/ak-skadi-sweep", {"heavy": 1, "seed": 7}, False, False),
    "fx_skadi_px_surge": ("water/ak-skadi-surge", {}, False, False),
    "fx_hoshiguma_px_saw": ("melee/ak-hoshiguma-saw", {}, False, False),
}
for k, pal in EXU.items():
    TARGETS["fx_exusiai_px_muzzle_" + k] = ("projectiles/ak-exu-muzzle", {"palette": pal}, True, True)
    TARGETS["fx_exusiai_px_hit_" + k] = ("impacts/ak-exu-hit", {"palette": pal}, True, False)


def install(lib):
    for cat in os.listdir(SRC):
        for f in os.listdir(os.path.join(SRC, cat)):
            if f.endswith(".js"):
                shutil.copy2(os.path.join(SRC, cat, f), os.path.join(lib, "src", "fx", cat, f))


def export(lib, name, spec, tmp, dry):
    fx_id, opts, hires, keep = spec
    out = os.path.join(tmp, name)
    r = subprocess.run(["node", "tools/render.mjs", fx_id, "--sheet", "--opts", json.dumps(opts), "--out", out],
                       cwd=lib, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    base = fx_id.split("/")[1]
    meta = json.load(open(os.path.join(out, fx_id, base + ".json")))
    sheet = Image.open(os.path.join(out, fx_id, base + ".png")).convert("RGBA")
    px = meta["meta"]["pixelfx"]
    frames = [sheet.crop((f["frame"]["x"], f["frame"]["y"], f["frame"]["x"] + f["frame"]["w"], f["frame"]["y"] + f["frame"]["h"])) for f in meta["frames"]]
    alpha = lambda im: im.getchannel("A").point(lambda a: 255 if a > 10 else 0)
    while frames and alpha(frames[-1]).getbbox() is None:
        frames.pop()
    fw, fh = px["frameSize"]
    if keep:
        box = (0, 0, fw, fh)
    else:
        ox, oy = px["pivot"]
        x0, y0, x1, y1 = fw, fh, 0, 0
        for f in frames:
            b = alpha(f).getbbox()
            if b:
                x0, y0, x1, y1 = min(x0, b[0]), min(y0, b[1]), max(x1, b[2]), max(y1, b[3])
        hw, hh = max(ox - x0, x1 - ox), max(oy - y0, y1 - oy)   # 以原点为中心对称
        box = (ox - hw, oy - hh, ox + hw, oy + hh)
    w, h = box[2] - box[0], box[3] - box[1]
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f.crop(box), (i * w, 0))
    q = strip.quantize(colors=64, method=Image.Quantize.FASTOCTREE).convert("RGBA")
    path = os.path.join(OUT, name + ("@2x" if hires else "") + ".png")
    if not dry:
        q.save(path, optimize=True)
    size = os.path.getsize(path) if not dry else 0
    print('"%s": [%d, %.1f],   # %dx%d × %d 帧，%.1f KB，显存 %.0f KB' % (name, len(frames), px["fps"], w, h, len(frames), size / 1024, w * len(frames) * h * 4 / 1024))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=os.path.join(ROOT, "build", "pixelfx"))
    ap.add_argument("--only", default="")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    if not os.path.exists(os.path.join(a.lib, "tools", "render.mjs")):
        sys.exit("找不到 pixelfx 库：先 git clone https://github.com/patch-gg/pixelfx " + a.lib)
    install(a.lib)
    only = set(filter(None, a.only.split(",")))
    with tempfile.TemporaryDirectory() as tmp:
        for name, spec in TARGETS.items():
            if not only or name in only:
                export(a.lib, name, spec, tmp, a.dry)


if __name__ == "__main__":
    main()
