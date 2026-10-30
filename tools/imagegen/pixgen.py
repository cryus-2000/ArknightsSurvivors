"""Gemini（Nano Banana）出图 + 像素化，配套技能 .claude/skills/pixgen/SKILL.md。

  python tools/imagegen/pixgen.py gen   --tag relic265 --prompt "..." [--ref a.png ...] [--n 4]
  python tools/imagegen/pixgen.py pixel --tag relic265 [--size 32] [--colors 14] [--ref ...]
  python tools/imagegen/pixgen.py sheet --tag relic265 [--ref ...]

- 只用标准库 urllib 直连 generativelanguage.googleapis.com，不经 Gemini CLI，不装任何东西。
- key 只从环境变量 GEMINI_API_KEY 读，不打印、不写盘。
- 产物都在 build/imagegen/<tag>/（不进 git）：raw_*.png 原图、pix_*.png 成品、sheet.png 对照、log.json 提示词与参数。
"""
import argparse, base64, io, json, os, sys, time, urllib.request, urllib.error
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "imagegen"
API = "https://generativelanguage.googleapis.com/v1beta/models/{m}:generateContent"
MODEL = os.environ.get("PIXGEN_MODEL", "gemini-2.5-flash-image")
BG = (255, 0, 255)  # 要求模型用纯洋红底，抠图用
OUTLINE = (8, 14, 24)  # 现有 264 个藏品图标外轮廓 98% 是这个色
PALETTE_DIR = "game/art/ui/relics"  # 量化后吸附到这批图标的全体颜色（约 437 色），色相不跑

STYLE = ("Pixel-art game item icon in the exact style of the reference icons: single object, centered, "
         "front three-quarter view, 1-pixel dark navy outline, soft cel shading, limited palette, "
         "small sparkle accents allowed. Flat solid magenta #FF00FF background filling the whole canvas, "
         "no shadow on background, no text, no frame, no border.")


def _key():
    k = os.environ.get("GEMINI_API_KEY", "").strip()
    if not k:
        sys.exit("GEMINI_API_KEY 未设置（用户环境变量）")
    return k


def _png_b64(path, up=256):
    im = Image.open(path).convert("RGBA")
    if max(im.size) < up:  # 小图放大再送，保持硬边
        k = up // max(im.size)
        im = im.resize((im.width * k, im.height * k), Image.NEAREST)
    bg = Image.new("RGBA", im.size, BG + (255,))
    bg.alpha_composite(im)
    buf = io.BytesIO()
    bg.convert("RGB").save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def _call(prompt, refs, model):
    parts = [{"inline_data": {"mime_type": "image/png", "data": _png_b64(r)}} for r in refs]
    parts.append({"text": prompt})
    body = {"contents": [{"parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": "1:1"}}}
    req = urllib.request.Request(API.format(m=model), data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "x-goog-api-key": _key()})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            res = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode(errors='replace')[:400]}")
    for c in res.get("candidates", []):
        for p in c.get("content", {}).get("parts", []):
            d = p.get("inline_data") or p.get("inlineData")
            if d:
                return base64.b64decode(d["data"])
    sys.exit("返回里没有图片：" + json.dumps(res, ensure_ascii=False)[:400])


def cmd_gen(a):
    d = OUT / a.tag
    d.mkdir(parents=True, exist_ok=True)
    prompt = (a.prompt + "\n\n" + STYLE) if not a.raw_prompt else a.prompt
    log = {"model": a.model, "prompt": prompt, "refs": a.ref, "files": []}
    for i in range(a.n):
        png = _call(prompt, a.ref, a.model)
        f = d / f"raw_{int(time.time())}_{i}.png"
        f.write_bytes(png)
        log["files"].append(f.name)
        print("raw", f.relative_to(ROOT))
    (d / "log.json").write_text(json.dumps(log, ensure_ascii=False, indent=1), encoding="utf-8")


def _palette(pdir):
    if not pdir:
        return None
    px = []
    for f in sorted((ROOT / pdir).glob("*.png")):
        im = np.array(Image.open(f).convert("RGBA"))
        px.append(im[im[..., 3] > 0][:, :3])
    return np.unique(np.concatenate(px), axis=0).astype(int) if px else None


def pixelize(src, size=32, colors=14, margin=1, outline=True, pdir=PALETTE_DIR, tol=90):
    im = np.array(Image.open(src).convert("RGB")).astype(int)
    h, w, _ = im.shape
    corners = np.array([im[0, 0], im[0, -1], im[-1, 0], im[-1, -1]])
    bg = np.median(corners, axis=0)
    fg = np.abs(im - bg).sum(-1) > tol
    ys, xs = np.nonzero(fg)
    if len(xs) == 0:
        raise ValueError("抠图后为空：" + str(src))
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    side = max(y1 - y0, x1 - x0)
    cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
    rgba = np.zeros((h, w, 4), np.uint8)
    rgba[..., :3] = im
    rgba[..., 3] = fg * 255
    crop = Image.fromarray(rgba).crop((cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side))
    inner = size - 2 * margin
    small = crop.resize((inner, inner), Image.BOX)
    a = np.array(small)
    alpha = a[..., 3] >= 128
    rgb = Image.fromarray(a[..., :3])
    q = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = np.array(q).astype(int)
    pal = _palette(pdir)
    if pal is not None and len(pal):
        d = ((out[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(-1)
        out = pal[d.argmin(-1)]
    res = np.zeros((size, size, 4), np.uint8)
    res[margin:margin + inner, margin:margin + inner, :3] = out
    res[margin:margin + inner, margin:margin + inner, 3] = alpha * 255
    if outline:
        A = res[..., 3] > 0
        pad = np.pad(A, 1)
        edge = A & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        res[edge, :3] = OUTLINE
    return Image.fromarray(res)


def cmd_pixel(a):
    d = OUT / a.tag
    for f in sorted(d.glob("raw_*.png")):
        out = d / f.name.replace("raw_", "pix_")
        pixelize(f, a.size, a.colors, a.margin, not a.no_outline, a.palette or None).save(out)
        print("pix", out.relative_to(ROOT))


def cmd_sheet(a):
    d = OUT / a.tag
    items = [Image.open(r).convert("RGBA") for r in a.ref] + [Image.open(f).convert("RGBA") for f in sorted(d.glob("pix_*.png"))]
    s, pad = 128, 8
    sheet = Image.new("RGBA", (len(items) * (s + pad) + pad, s + 2 * pad), (40, 40, 48, 255))
    for i, im in enumerate(items):
        sheet.alpha_composite(im.resize((s, s), Image.NEAREST), (pad + i * (s + pad), pad))
    sheet.save(d / "sheet.png")
    print("sheet", (d / "sheet.png").relative_to(ROOT), f"（前 {len(a.ref)} 张是参照）")


def main():
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="cmd", required=True)
    g = sp.add_parser("gen"); g.add_argument("--prompt", required=True); g.add_argument("--raw-prompt", action="store_true")
    g.add_argument("--n", type=int, default=4); g.add_argument("--model", default=MODEL)
    x = sp.add_parser("pixel"); x.add_argument("--size", type=int, default=32); x.add_argument("--colors", type=int, default=14)
    x.add_argument("--margin", type=int, default=1); x.add_argument("--no-outline", action="store_true")
    x.add_argument("--palette", default=PALETTE_DIR, help="吸附色板来源目录；传空串不吸附")
    s = sp.add_parser("sheet")
    for q in (g, x, s):
        q.add_argument("--tag", required=True); q.add_argument("--ref", nargs="*", default=[])
    a = p.parse_args()
    {"gen": cmd_gen, "pixel": cmd_pixel, "sheet": cmd_sheet}[a.cmd](a)


if __name__ == "__main__":
    main()
