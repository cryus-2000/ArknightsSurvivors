# -*- coding: utf-8 -*-
"""敌方 pixelfx 特效导出（docs/236）：把 tools/pixelfx_foe/<cat>/<name>.js 拷进 pixelfx 检出（缺省 <主仓库>/build/pixelfx），
render --sheet 出网格表，再裁所有帧的并集边框、去掉首尾空帧、排成横排帧条、量化到 ≤ COLORS 色，写进 game/art/fx/<贴图名>.png。
打印帧数 / 单帧尺寸 / 锚点（单帧内，1x 纹素）/ 文件大小，供登记 art.gd V6_FRAMES 与调用点 anchor_px。

    python tools/pixelfx_foe/export.py foe/slam-quake fx_carmen_smash fx_immortal_burst
    （同一份表可写成几个贴图名；--opts '{"seed":5}' 透传给 render）
"""
import json, os, shutil, subprocess, sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.dirname(os.path.abspath(__file__))
PFX = os.environ.get("PIXELFX_DIR") or os.path.join(ROOT.split(os.sep + ".claude" + os.sep)[0], "build", "pixelfx")
OUT = os.path.join(ROOT, "game", "art", "fx")
COLORS = 32


def main():
    args = sys.argv[1:]
    opts = None
    if "--opts" in args:
        i = args.index("--opts")
        opts = args[i + 1]
        del args[i:i + 2]
    fid, names = args[0], args[1:]
    cat, nm = fid.split("/")
    os.makedirs(os.path.join(PFX, "src", "fx", cat), exist_ok=True)
    for f in os.listdir(os.path.join(SRC, cat)):
        shutil.copy(os.path.join(SRC, cat, f), os.path.join(PFX, "src", "fx", cat, f))
    cmd = ["node", "tools/render.mjs", fid, "--sheet"] + (["--opts", opts] if opts else [])
    subprocess.run(cmd, cwd=PFX, check=True)
    rec = os.path.join(PFX, "records", cat, nm)
    meta = json.load(open(os.path.join(rec, nm + ".json"), encoding="utf-8"))
    sheet = Image.open(os.path.join(rec, nm + ".png")).convert("RGBA")
    fr = [v["frame"] for v in (meta["frames"].values() if isinstance(meta["frames"], dict) else [x for x in meta["frames"]])]
    ims = [sheet.crop((f["x"], f["y"], f["x"] + f["w"], f["y"] + f["h"])) for f in fr]
    keep = [i for i, im in enumerate(ims) if im.getbbox() is not None]
    ims = ims[keep[0]:keep[-1] + 1]
    box = None
    for im in ims:
        b = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    w, h = box[2] - box[0], box[3] - box[1]
    strip = Image.new("RGBA", (w * len(ims), h), (0, 0, 0, 0))
    for i, im in enumerate(ims):
        strip.paste(im.crop(box), (i * w, 0))
    q = strip.quantize(colors=COLORS, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    px = meta["meta"]["pixelfx"]
    piv = px.get("pivot") or px.get("origin")
    if isinstance(piv, dict):
        piv = [piv["x"], piv["y"]]
    anchor = (piv[0] - box[0], piv[1] - box[1])
    for n in names:
        p = os.path.join(OUT, n + ".png")
        q.save(p, optimize=True)
        print("%s  %d 帧 × %d×%d  fps %s  锚点 %s  %.1f KB" % (p, len(ims), w, h, px.get("fps"), anchor, os.path.getsize(p) / 1024.0))


if __name__ == "__main__":
    main()
