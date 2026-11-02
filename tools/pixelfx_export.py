# -*- coding: utf-8 -*-
"""pixelfx 特效导出成游戏帧条（docs/228 §7）。

tools/pixelfx_fx/<类>/<名>.js 是本作写的 pixelfx 特效源码；本脚本把它们拷进 pixelfx 库检出（缺省 build/pixelfx，
不进 git），用库自带的 render.mjs --sheet 导精灵表，再：
  - 以原点为中心对称裁边（游戏按帧中心放置；枪口这类非居中的用 keep_canvas 保留原画布），
  - 还原 pixelfx 精灵表的预乘色（半透明处 rgb / a，否则 Godot 里 a² 发灰，D 组 11-02 发现），
  - 去掉末尾全空帧，
  - 量化到 ≤ 32 色（带透明，按条目 colors 改），存调色板 PNG，
  - 拼成单行横向帧条写进 game/art/fx/<名>[ @2x].png。
最后打印 art.gd V6_FRAMES 要登记的 [帧数, fps]。改完记得跑 python tools/asset_index.py。

用法：python tools/pixelfx_export.py [--lib build/pixelfx] [--only 名字,...] [--dry]
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "tools", "pixelfx_fx")
OUT = os.path.join(ROOT, "game", "art", "fx")

# 导出目标：tools/pixelfx_fx/targets_*.json（每个并行会话一份，互不改别人的文件，docs/229 §9）。
# 每条：游戏贴图名 → {"fx": 特效 id, "opts": 选项, "hires": 是否 @2x, "keep": 是否保留原画布（枪口这类原点不居中）, "colors": 色数（缺省 32）}
def load_targets():
    t = {}
    for f in sorted(os.listdir(SRC)):
        if f.startswith("targets") and f.endswith(".json"):
            for name, spec in json.load(open(os.path.join(SRC, f), encoding="utf-8")).items():
                if name.startswith("_"):
                    continue
                if name in t:
                    sys.exit("导出目标重名：%s（%s）" % (name, f))
                t[name] = spec
    return t


def install(lib):
    shutil.copy2(os.path.join(SRC, "house.js"), os.path.join(lib, "src", "fx", "house.js"))   # 公共规范模块：特效里 import "../house.js"
    for cat in os.listdir(SRC):
        if not os.path.isdir(os.path.join(SRC, cat)):
            continue
        for f in os.listdir(os.path.join(SRC, cat)):
            if f.endswith(".js"):
                shutil.copy2(os.path.join(SRC, cat, f), os.path.join(lib, "src", "fx", cat, f))


def unpremultiply(im):
    """pixelfx 的 canvas().paste() 往全透明画布上贴帧时把 rgb 乘了 alpha、alpha 原样保留（预乘色 + 原 alpha）；
    Godot 按直通 alpha 画，半透明处会变成 a² 发暗发灰。这里还原：a > 0 时 rgb = min(255, rgb * 255 / a)。"""
    import numpy as np
    a = np.asarray(im, dtype=np.float32).copy()
    al = a[..., 3:4]
    a[..., :3] = np.where(al > 0, np.minimum(255.0, a[..., :3] * 255.0 / np.maximum(al, 1.0) + 0.5), 0.0)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def export(lib, name, spec, tmp, dry):
    fx_id, opts, hires, keep = spec["fx"], spec.get("opts", {}), spec.get("hires", False), spec.get("keep", False)
    out = os.path.join(tmp, name)
    r = subprocess.run(["node", "tools/render.mjs", fx_id, "--sheet", "--opts", json.dumps(opts), "--out", out],
                       cwd=lib, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    base = fx_id.split("/")[1]
    meta = json.load(open(os.path.join(out, fx_id, base + ".json")))
    sheet = unpremultiply(Image.open(os.path.join(out, fx_id, base + ".png")).convert("RGBA"))
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
    q = strip.quantize(colors=int(spec.get("colors", 32)), method=Image.Quantize.FASTOCTREE)   # 存调色板 PNG（比转回 RGBA 小约 2.5 倍）
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
        for name, spec in load_targets().items():
            if not only or name in only:
                export(a.lib, name, spec, tmp, a.dry)


if __name__ == "__main__":
    main()
