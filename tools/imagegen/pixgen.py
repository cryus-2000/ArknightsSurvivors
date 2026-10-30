"""Gemini（Nano Banana）出图 + 像素化，配套技能 .claude/skills/pixgen/SKILL.md。

  python tools/imagegen/pixgen.py gen   --tag relic265 --prompt "..." [--ref a.png ...] [--n 4]
  python tools/imagegen/pixgen.py pixel --tag relic265 [--size 32] [--colors 14] [--ref ...]
  python tools/imagegen/pixgen.py pixel --tag ul_crack --fx 200 [--cell 3] [--lum 0.9]   # 世界特效口径
  python tools/imagegen/pixgen.py sheet --tag relic265 [--ref ...]
  python tools/imagegen/pixgen.py strip --tag ka_charge --name fx_x --grid 4x2 --frame 64x64 [--align 0.03]   # 精灵表 → 帧条

- 只用标准库 urllib 直连，不经 Gemini CLI，不装任何东西。两种后端（PIXGEN_BACKEND）：
  vertex（缺省）：Vertex AI，按 Cloud 项目计费；令牌每次调 `gcloud auth print-access-token` 现取，项目取 gcloud 当前项目。
  studio：AI Studio Gemini API，key 读环境变量 GEMINI_API_KEY（预付制）。
  令牌 / key 都不打印、不写盘。
- 产物都在 build/imagegen/<tag>/（不进 git）：raw_*.png 原图、pix_*.png 成品、sheet.png 对照、log.json 提示词与参数。
"""
import argparse, base64, io, json, os, sys, time, urllib.request, urllib.error
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "imagegen"
API = "https://generativelanguage.googleapis.com/v1beta/models/{m}:generateContent"
VERTEX = "https://aiplatform.googleapis.com/v1/projects/{p}/locations/global/publishers/google/models/{m}:generateContent"
BACKEND = os.environ.get("PIXGEN_BACKEND", "vertex")
MODEL = os.environ.get("PIXGEN_MODEL", "gemini-3.1-flash-lite-image")
BG = (255, 0, 255)  # 要求模型用纯洋红底，抠图用
OUTLINE = (8, 14, 24)  # 现有 264 个藏品图标外轮廓 98% 是这个色
PALETTE_DIR = "game/art/ui/relics"  # 量化后吸附到这批图标的全体颜色（约 437 色），色相不跑

STYLE = ("Pixel-art game item icon in the exact style of the reference icons: single object, centered, "
         "front three-quarter view, 1-pixel dark navy outline, soft cel shading, limited palette, "
         "small sparkle accents allowed. Flat solid magenta #FF00FF background filling the whole canvas, "
         "no shadow on background, no text, no frame, no border.")


def _gcloud(*args):
    import shutil, subprocess
    g = shutil.which("gcloud") or shutil.which("gcloud.cmd")
    if not g:
        cand = Path(os.environ.get("LOCALAPPDATA", "")) / "Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd"
        g = str(cand) if cand.exists() else None
    if not g:
        sys.exit("找不到 gcloud；装 Google Cloud CLI 并 gcloud auth login，或设 PIXGEN_BACKEND=studio")
    r = subprocess.run([g, *args], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit("gcloud " + args[0] + " 失败：" + r.stderr.strip()[:300])
    return r.stdout.strip()


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


def _call(prompt, refs, model, aspect="1:1", size=""):
    parts = [{"inline_data": {"mime_type": "image/png", "data": _png_b64(r)}} for r in refs]
    parts.append({"text": prompt})
    body = {"contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": aspect, **({"imageSize": size} if size else {})}}}
    if BACKEND == "vertex":
        url = VERTEX.format(p=_gcloud("config", "get-value", "project"), m=model)
        auth = {"Authorization": "Bearer " + _gcloud("auth", "print-access-token")}
    else:
        url, auth = API.format(m=model), {"x-goog-api-key": _key()}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", **auth})
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
    log = {"backend": BACKEND, "model": a.model, "aspect": a.aspect, "size": a.size, "prompt": prompt, "refs": a.ref, "files": []}
    for i in range(a.n):
        png = _call(prompt, a.ref, a.model, a.aspect, a.size)
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
    r_, g_, b_ = im[..., 0], im[..., 1], im[..., 2]
    fg &= ~((np.minimum(r_, b_) - g_ > 60) & (np.abs(r_ - b_) < 90))
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
    # 每格取众数色（5 位分箱，只数物体像素）：平均会把描边、暗纹混进本色发灰；再只对物体像素量化，名额不浪费在底色上
    c = np.array(crop)
    m = c[..., 3] > 0
    key = (c[..., 0].astype(int) >> 3) << 10 | (c[..., 1].astype(int) >> 3) << 5 | (c[..., 2].astype(int) >> 3)
    edges = np.linspace(0, side, inner + 1).astype(int)
    out = np.zeros((inner, inner, 3), int)
    alpha = np.zeros((inner, inner), bool)
    for yi in range(inner):
        for xi in range(inner):
            sl = (slice(edges[yi], edges[yi + 1]), slice(edges[xi], edges[xi + 1]))
            cm = m[sl]
            if cm.size == 0 or cm.mean() < 0.5:
                continue
            ks = key[sl][cm]
            vals, cnt = np.unique(ks, return_counts=True)
            k = vals[cnt.argmax()]
            out[yi, xi] = c[sl][cm][ks == k][:, :3].mean(0)
            alpha[yi, xi] = True
    px = out[alpha].astype(np.uint8)
    if len(px):
        strip = Image.fromarray(px.reshape(1, -1, 3))
        qs = strip.quantize(colors=min(colors, len(np.unique(px, axis=0))), method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        out[alpha] = np.array(qs.convert("RGB")).reshape(-1, 3)
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
        # 亮色（光线、闪点）不描边，和现有图标里不带轮廓的闪光一致
        luma = res[..., :3].astype(int) @ np.array([299, 587, 114]) // 1000
        res[edge & (luma < 190), :3] = OUTLINE
    return Image.fromarray(res)


def _cutout(src, tol=90, fringe=0):
    """洋红底抠图：返回 (rgb int 数组, 前景掩码)。fringe > 0：红、蓝两通道都比绿高出 fringe 的像素也算底
    （模型常画一圈和洋红混出来的淡紫光晕；只在设定色里没有紫 / 粉时用）"""
    im = np.array(Image.open(src).convert("RGB")).astype(int)
    corners = np.array([im[0, 0], im[0, -1], im[-1, 0], im[-1, -1]])
    fg = np.abs(im - np.median(corners, axis=0)).sum(-1) > tol
    r_, g_, b_ = im[..., 0], im[..., 1], im[..., 2]
    fg &= ~((np.minimum(r_, b_) - g_ > 60) & (np.abs(r_ - b_) < 90))
    if fringe > 0:
        fg &= ~(np.minimum(r_, b_) - g_ > fringe)
    return im, fg


def pixelize_fx(src, cells=96, cell=3, colors=12, lum=0.9, cover=0.4, accent=0.0):
    """世界特效口径（docs/199 §7.4）：不裁正方形、按物体外框保持宽高比；长边 cells 格，每格众数色，只对物体像素量化，
    亮度封顶 lum（最大通道 ≤ lum × 255，同 ult.gd _pc），无描边、不吸附图标色板；每格放大成 cell×cell 纹素（@2x 贴图 1 纹素 = 1 世界像素，
    cell = 3 即 ult/px_grid 的 3 世界像素格）。cover：格内物体占比过此才算实心（细裂缝取低些）。
    accent > 0：格里比本格暗部亮 60 以上的像素（发光裂缝）占比过 accent 就取它们的众数，细亮线缩小后不被底色吃掉"""
    im, fg = _cutout(src)
    ys, xs = np.nonzero(fg)
    if len(xs) == 0:
        raise ValueError("抠图后为空：" + str(src))
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    W, H = x1 - x0, y1 - y0
    step = max(W, H) / cells
    nx, ny = max(1, round(W / step)), max(1, round(H / step))
    c, m = im[y0:y1, x0:x1], fg[y0:y1, x0:x1]
    ex, ey = np.linspace(0, W, nx + 1).astype(int), np.linspace(0, H, ny + 1).astype(int)
    out, alpha = _grid_mode(c, m, ex, ey, cover, accent)
    _quant_cap([out], [alpha], colors, lum)
    return _rgba(out, alpha).resize((nx * cell, ny * cell), Image.NEAREST)


def _grid_mode(c, m, ex, ey, cover, accent):
    """按格边界 ex / ey 每格取众数色：返回 (颜色 int 数组, 实心掩码)。cover / accent 见 pixelize_fx"""
    key = (c[..., 0] >> 3) << 10 | (c[..., 1] >> 3) << 5 | (c[..., 2] >> 3)
    ny, nx = len(ey) - 1, len(ex) - 1
    out = np.zeros((ny, nx, 3), int)
    alpha = np.zeros((ny, nx), bool)
    for yi in range(ny):
        for xi in range(nx):
            sl = (slice(ey[yi], ey[yi + 1]), slice(ex[xi], ex[xi + 1]))
            cm = m[sl]
            if cm.size == 0 or cm.mean() < cover:
                continue
            ks = key[sl][cm]
            pc = c[sl][cm]
            if accent > 0:
                lu = pc @ np.array([299, 587, 114]) // 1000
                hi = lu > np.percentile(lu, 30) + 60
                if hi.mean() >= accent:
                    ks, pc = ks[hi], pc[hi]
            vals, cnt = np.unique(ks, return_counts=True)
            out[yi, xi] = pc[ks == vals[cnt.argmax()]].mean(0)
            alpha[yi, xi] = True
    return out, alpha


def _quant_cap(outs, alphas, colors, lum, snap=None):
    """几帧合在一起量化到同一套 ≤colors 色（帧间不跳色），再亮度封顶 lum；就地改 outs。
    snap：[(r, g, b), …] 量化后每色吸附到最近的设定色（模型掺进的灰紫、跑偏色相一律拉回干员色阶）"""
    px = np.concatenate([o[a] for o, a in zip(outs, alphas)]).astype(np.uint8)
    if len(px):
        qs = Image.fromarray(px.reshape(1, -1, 3)).quantize(colors=min(colors, len(np.unique(px, axis=0))),
                                                             method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        q = np.array(qs.convert("RGB")).reshape(-1, 3)
        i = 0
        for o, a in zip(outs, alphas):
            n = int(a.sum())
            o[a] = q[i:i + n]
            i += n
    if snap:
        sp = np.array(snap, float)
        for o, a in zip(outs, alphas):
            v = o[a].astype(float)
            o[a] = sp[((v[:, None, :] - sp[None]) ** 2).sum(-1).argmin(1)]
    cap = lum * 255
    for o in outs:
        mx = o.max(-1, keepdims=True).clip(1)
        o[...] = np.where(mx > cap, o * cap / mx, o).round()


def _rgba(out, alpha):
    res = np.zeros(out.shape[:2] + (4,), np.uint8)
    res[..., :3] = out.clip(0, 255)
    res[..., 3] = alpha * 255
    return Image.fromarray(res)


def sprite_strip(src, grid=(4, 2), frame=(64, 64), cell=3, colors=16, lum=0.9, cover=0.4, accent=0.0,
                 anchor=(0.5, 0.5), align=0.0, fill=0.92, drop=0, order=None, fringe=0, snap=None):
    """精灵表 → 帧条（docs/199 §7.2 格式，pixfx 技能 §7）：模型在一张图里画好 grid = (列, 行) 格连续帧（行优先、洋红底），
    每格切开后按同一个比例落到 frame = (宽, 高) 格（每格 cell×cell 纹素），全部帧合起来量化到同一套 ≤colors 色、亮度封顶、硬 alpha，横排拼成帧条。
    anchor：原点在帧里的位置（0–1）。align > 0：每格取最亮的 align 比例像素的重心当这一格的锚点（模型画的帧位置常有几像素漂移，
    对齐后原点不抖）；0 = 用格子的同一相对位置。比例：所有帧里离锚点最远的物体像素恰好落到帧边的 fill 处（帧帧同一比例，不缩放跳变）。
    drop：删掉 4 连通块小于 drop 格的孤立碎点（缩小后的噪点会逐帧闪）。order：输出用哪几格、什么顺序（格号行优先从 0 数；
    重排 / 复用格子凑循环）。fringe 见 _cutout，snap 见 _quant_cap。返回 (帧条 Image, 信息)"""
    im, fg = _cutout(src, fringe=fringe)
    H, W = fg.shape
    gx, gy = grid
    fw, fh = frame
    cw, ch = W / gx, H / gy
    lw = np.array([299, 587, 114])
    boxes, anchors, ext = [], [], 1e-6
    for r in range(gy):
        for q in range(gx):
            x0, y0, x1, y1 = int(q * cw), int(r * ch), int((q + 1) * cw), int((r + 1) * ch)
            m = fg[y0:y1, x0:x1]
            ax, ay = anchor[0] * (x1 - x0), anchor[1] * (y1 - y0)
            if align > 0 and m.sum() > 0.01 * m.size:  # 太稀（零星火花）的帧对不准，用格子相对位置
                lu = im[y0:y1, x0:x1][m] @ lw // 1000
                thr = np.percentile(lu, 100 - align * 100)
                yy, xx = np.nonzero(m)
                k = lu >= thr
                ax, ay = xx[k].mean(), yy[k].mean()
            yy, xx = np.nonzero(m)
            if len(xx):
                ext = max(ext, (ax - xx.min()) / (anchor[0] * fw), (xx.max() - ax) / ((1 - anchor[0]) * fw),
                          (ay - yy.min()) / (anchor[1] * fh), (yy.max() - ay) / ((1 - anchor[1]) * fh))
            boxes.append((x0, y0, x1, y1))
            anchors.append((x0 + ax, y0 + ay))
    step = ext / fill  # 原图像素 / 格
    outs, alphas, info = [], [], []
    for (x0, y0, x1, y1), (ax, ay) in zip(boxes, anchors):
        m = np.zeros_like(fg)
        m[y0:y1, x0:x1] = fg[y0:y1, x0:x1]  # 只取本格，邻格越界的不算
        ex = np.clip(np.round(ax - anchor[0] * fw * step + np.arange(fw + 1) * step), 0, W).astype(int)
        ey = np.clip(np.round(ay - anchor[1] * fh * step + np.arange(fh + 1) * step), 0, H).astype(int)
        o, a = _grid_mode(im, m, ex, ey, cover, accent)
        if drop > 0:
            a = _drop_specks(a, drop)
        outs.append(o)
        alphas.append(a)
        info.append({"cells": int(a.sum()), "anchor_raw": [round(float(ax)), round(float(ay))]})
    if order:
        outs = [outs[i].copy() for i in order]
        alphas = [alphas[i] for i in order]
        info = [info[i] for i in order]
    _quant_cap(outs, alphas, colors, lum, snap)
    frames = [_rgba(o, a).resize((fw * cell, fh * cell), Image.NEAREST) for o, a in zip(outs, alphas)]
    strip = Image.new("RGBA", (fw * cell * len(frames), fh * cell), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * fw * cell, 0))
    arr = np.array(strip)
    return strip, {"step": round(step, 2), "frames": info, "colors": int(len(np.unique(arr[..., :3][arr[..., 3] > 0], axis=0)))}


def _drop_specks(a, n):
    """去掉 4 连通块小于 n 格的孤立点"""
    a = a.copy()
    seen = np.zeros_like(a)
    H, W = a.shape
    for y0 in range(H):
        for x0 in range(W):
            if not a[y0, x0] or seen[y0, x0]:
                continue
            st, comp = [(y0, x0)], []
            seen[y0, x0] = True
            while st:
                y, x = st.pop()
                comp.append((y, x))
                for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= yy < H and 0 <= xx < W and a[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        st.append((yy, xx))
            if len(comp) < n:
                for y, x in comp:
                    a[y, x] = False
    return a


def strip_preview(strip, nf, zoom=3, bg=(30, 30, 40), anchor_px=None):
    """帧条放大预览：深色底、帧间留缝，anchor_px（@2x 单帧内的原点）画洋红十字"""
    fw, fh = strip.width // nf, strip.height
    pad = 6
    sheet = Image.new("RGBA", (nf * (fw * zoom + pad) + pad, fh * zoom + 2 * pad), bg + (255,))
    for i in range(nf):
        f = strip.crop((i * fw, 0, (i + 1) * fw, fh)).resize((fw * zoom, fh * zoom), Image.NEAREST)
        x = pad + i * (fw * zoom + pad)
        sheet.alpha_composite(f, (x, pad))
        if anchor_px:
            cx, cy = x + int(anchor_px[0] * zoom), pad + int(anchor_px[1] * zoom)
            for d in range(-8, 9):
                if abs(d) > 3:
                    sheet.putpixel((cx + d, cy), (255, 0, 255, 255))
                    sheet.putpixel((cx, cy + d), (255, 0, 255, 255))
    return sheet


def _seam(x, y, w, dys=range(-2, 3)):
    """两条像素带 x（左）、y（右）各取 w 列重叠：y 先上下挪 ±2 格对齐 x，然后每一行在重叠区里选 x / y 最一致的位置切换。
    返回 (x 去掉末 w 列的部分 + 重叠区 + y 去掉头 w 列, 重叠区不一致格数)"""
    (xc, xa), (yc, ya) = x, y
    best = None
    for dy in dys:
        yc2, ya2 = np.roll(yc, dy, 0), np.roll(ya, dy, 0)
        d = (np.abs(xc[:, -w:] - yc2[:, :w]).sum(-1) * (xa[:, -w:] & ya2[:, :w]) + 255 * (xa[:, -w:] != ya2[:, :w])).sum()
        if best is None or d < best[0]:
            best = (d, yc2, ya2)
    _, yc, ya = best
    oc, oa = np.zeros((xc.shape[0], w, 3), int), np.zeros((xc.shape[0], w), bool)
    bad = 0
    for r in range(xc.shape[0]):
        # 第 r 行：前 j 格取 x、后面取 y；挑切换处两边一致（同为空，或同实心且颜色相近）的 j
        diff = [(xa[r, -w + j] != ya[r, j]) * 255 + (np.abs(xc[r, -w + j] - yc[r, j]).sum() if xa[r, -w + j] and ya[r, j] else 0) for j in range(w)]
        j = int(np.argmin(diff))
        bad += diff[j] > 90
        oc[r, :j], oa[r, :j] = xc[r, -w:-w + j], xa[r, -w:-w + j]
        oc[r, j:], oa[r, j:] = yc[r, j:w], ya[r, j:w]
    return (np.concatenate([xc[:, :-w], oc, yc[:, w:]], 1), np.concatenate([xa[:, :-w], oa, ya[:, w:]], 1)), bad


def seam_loop(src, rows=3, seg=(128, 16), cell=3, colors=12, lum=0.9, cover=0.4, accent=0.0, fill=0.9, overlap=8,
              snap=None, fringe=0, drop=0):
    """无缝段（pixfx §8）：模型在一张图里画 rows 条横向长带（每行一条），每条落到 seg = (长, 高) 格 + overlap 格重叠，
    按 A→B→C→A 首尾相接、接缝逐行挑切换点（_seam），得到周期 rows × 长 的一整圈。
    返回 (圈贴图（多拼一段头，任何起点截 seg 长都不用绕回）, 信息)。变体 v = 圈上 [v × 长, (v + 1) × 长)，按 A→B→C→A 轮换铺必然无缝；
    流动交给代码滚动截取起点（ux），不靠逐帧画。"""
    im, fg = _cutout(src, fringe=fringe)
    H, W = fg.shape
    L, h = seg
    bands, hs = [], []
    for r in range(rows):
        y0, y1 = int(r * H / rows), int((r + 1) * H / rows)
        ys, xs = np.nonzero(fg[y0:y1])
        if len(xs) == 0:
            raise ValueError(f"第 {r} 行抠图后为空")
        bands.append((y0 + ys.min(), y0 + ys.max() + 1, xs.min(), xs.max() + 1))
        hs.append(ys.max() + 1 - ys.min())
    sy = max(hs) / (h * fill)
    parts, info = [], {"rows": []}
    for (b0, b1, x0, x1) in bands:
        cy = (b0 + b1) / 2
        ey = np.clip(np.round(cy - h * sy / 2 + np.arange(h + 1) * sy), 0, H).astype(int)
        ex = np.round(np.linspace(x0, x1, L + overlap + 1)).astype(int)
        o, al = _grid_mode(im, fg, ex, ey, cover, accent)
        if drop:
            al = _drop_specks(al, drop)
        parts.append([o, al])
        info["rows"].append({"x_stretch": round((x1 - x0) / (L + overlap) / sy, 2)})
    _quant_cap([q[0] for q in parts], [q[1] for q in parts], colors, lum, snap)
    # 首尾相接：每段先去掉头 overlap/2、尾 overlap/2 之外的多余，再两两 _seam；最后一段接回第一段的头
    w = overlap
    loop, bads = parts[0], []
    for q in parts[1:]:
        loop, b = _seam(loop, q, w)
        bads.append(int(b))
    # 收圈：把第一段的头 w 列接到末尾做接缝，再把圈的头 w 列换成这段接缝结果（圈长 = rows × L）
    head = (parts[0][0][:, :w], parts[0][1][:, :w])
    tail_c, tail_a = loop[0][:, -2 * w:], loop[1][:, -2 * w:]
    (jc, ja), b = _seam((tail_c, tail_a), head, w, (0,))  # 收圈不能挪 A 的头，否则绕回处上下错位
    bads.append(int(b))
    total = rows * L
    lc = np.concatenate([loop[0][:, :-2 * w], jc], 1)
    la = np.concatenate([loop[1][:, :-2 * w], ja], 1)
    # 现在 lc 的末 w 列等于第一段的头 w 列：去掉圈头那 w 列，圈即首尾相接；长度对齐到 total（多的从各段中部均匀抽掉、少的复制）
    lc, la = lc[:, w:], la[:, w:]
    idx = np.round(np.linspace(0, lc.shape[1] - 1, total)).astype(int) if lc.shape[1] != total else np.arange(total)
    lc, la = lc[:, idx], la[:, idx]
    ext_c = np.concatenate([lc, lc[:, :L]], 1)
    ext_a = np.concatenate([la, la[:, :L]], 1)
    img = _rgba(ext_c, ext_a).resize((ext_c.shape[1] * cell, h * cell), Image.NEAREST)
    info.update({"period_cells": total, "seam_bad_rows": bads, "y_step": round(sy, 2), "size": list(img.size)})
    return img, info


def loop_preview(img, L, rows, cell=3, zoom=2, bg=(30, 30, 40), orders=("012012", "021102")):
    """无缝段预览：按几种轮换顺序把变体首尾相接铺两遍（第一行按 A→B→C 轮换，后几行乱序作反例），每段交界画洋红短竖线"""
    seg = L * cell
    h = img.height
    out = []
    for od in orders:
        row = Image.new("RGBA", (seg * len(od), h), bg + (255,))
        for i, ch in enumerate(od):
            v = int(ch)
            row.alpha_composite(img.crop((v * seg, 0, (v + 1) * seg, h)), (i * seg, 0))
        out.append(row)
    pad = 10
    sheet = Image.new("RGBA", (out[0].width * zoom, len(out) * (h * zoom + pad) + pad), bg + (255,))
    for k, row in enumerate(out):
        y = pad + k * (h * zoom + pad)
        sheet.alpha_composite(row.resize((row.width * zoom, h * zoom), Image.NEAREST), (0, y))
        for i in range(1, len(orders[k])):
            for t in range(4):
                sheet.putpixel((i * seg * zoom, y + t), (255, 0, 255, 255))
                sheet.putpixel((i * seg * zoom, y + h * zoom - 1 - t), (255, 0, 255, 255))
    return sheet


def cmd_loop(a):
    d = OUT / a.tag
    src = Path(a.src) if a.src else sorted(d.glob("raw_*.png"))[-1]
    L, h = (int(v) for v in a.seg.split("x"))
    snap = [tuple(int(x.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for x in a.snap.split(",")] if a.snap else None
    img, info = seam_loop(src, a.rows, (L, h), a.cell, a.colors, a.lum, a.cover, a.accent, a.fill, a.overlap, snap, a.fringe, a.drop)
    out = d / (a.name + "@2x.png")
    img.save(out)
    loop_preview(img, L, a.rows, a.cell, orders=("012012", "021120") if a.rows == 3 else ("0" * 4,)).save(d / (a.name + "_preview.png"))
    info["src"] = src.name
    (d / (a.name + "_info.json")).write_text(json.dumps(info, ensure_ascii=False, indent=1), encoding="utf-8")
    print("loop", out.relative_to(ROOT), img.size, "周期", info["period_cells"], "格；接缝不一致行数", info["seam_bad_rows"])


def cmd_strip(a):
    d = OUT / a.tag
    src = Path(a.src) if a.src else sorted(d.glob("raw_*.png"))[-1]
    gx, gy = (int(v) for v in a.grid.split("x"))
    fw, fh = (int(v) for v in a.frame.split("x"))
    ax, ay = (float(v) for v in a.anchor.split(","))
    order = [int(v) for v in a.order.split(",")] if a.order else None
    st, info = sprite_strip(src, (gx, gy), (fw, fh), a.cell, a.colors, a.lum, a.cover, a.accent, (ax, ay), a.align, a.fill, a.drop, order, a.fringe,
                            [tuple(int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for h in a.snap.split(",")] if a.snap else None)
    nf = len(order) if order else gx * gy
    out = d / (a.name + "@2x.png")
    st.save(out)
    strip_preview(st, nf, a.zoom, anchor_px=(ax * fw * a.cell, ay * fh * a.cell)).save(d / (a.name + "_preview.png"))
    info["src"] = src.name
    info["size"] = list(st.size)
    (d / (a.name + "_info.json")).write_text(json.dumps(info, ensure_ascii=False, indent=1), encoding="utf-8")
    print("strip", out.relative_to(ROOT), st.size, "色数", info["colors"], "每格原图像素", info["step"])
    for i, f in enumerate(info["frames"]):
        print(f"  帧 {i}: {f['cells']} 格  锚点 {f['anchor_raw']}")


def cmd_pixel(a):
    d = OUT / a.tag
    for f in sorted(d.glob("raw_*.png")):
        out = d / f.name.replace("raw_", "pix_")
        if a.fx:
            pixelize_fx(f, a.fx, a.cell, a.colors, a.lum, a.cover, a.accent).save(out)
        else:
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
    g.add_argument("--aspect", default="1:1", help="出图宽高比：1:1 / 16:9 / 21:9 …（长条特效用宽图）")
    g.add_argument("--size", default="", help="出图分辨率档 1K / 2K / 4K（缺省模型自定，约 1K；帧多的精灵表要 2K 以上，各模型支持不同）")
    x = sp.add_parser("pixel"); x.add_argument("--size", type=int, default=32); x.add_argument("--colors", type=int, default=14)
    x.add_argument("--margin", type=int, default=1); x.add_argument("--no-outline", action="store_true")
    x.add_argument("--palette", default=PALETTE_DIR, help="吸附色板来源目录；传空串不吸附")
    x.add_argument("--fx", type=int, default=0, help="世界特效口径：长边格数（>0 启用；保持宽高比、亮度封顶、无描边、不吸附）")
    x.add_argument("--cell", type=int, default=3, help="--fx：每格放大成几纹素（@2x 贴图 3 = ult/px_grid 3 世界像素格）")
    x.add_argument("--lum", type=float, default=0.9, help="--fx：亮度封顶（最大通道 / 255）")
    x.add_argument("--cover", type=float, default=0.4, help="--fx：格内物体占比过此才算实心")
    x.add_argument("--accent", type=float, default=0.0, help="--fx：格内亮像素占比过此就取亮色（保住细发光裂缝；0 = 关）")
    t = sp.add_parser("strip", help="精灵表 → 帧条（pixfx §7）")
    t.add_argument("--src", default="", help="原图（缺省本 tag 最新 raw）"); t.add_argument("--name", required=True, help="帧条名（不含 @2x）")
    t.add_argument("--grid", default="4x2", help="列x行"); t.add_argument("--frame", default="64x64", help="单帧格数 宽x高")
    t.add_argument("--cell", type=int, default=3); t.add_argument("--colors", type=int, default=16); t.add_argument("--lum", type=float, default=0.9)
    t.add_argument("--cover", type=float, default=0.4); t.add_argument("--accent", type=float, default=0.0)
    t.add_argument("--anchor", default="0.5,0.5", help="原点在帧里的相对位置"); t.add_argument("--align", type=float, default=0.0, help="最亮像素比例当锚点对齐（0 = 不对齐）")
    t.add_argument("--fill", type=float, default=0.92); t.add_argument("--drop", type=int, default=0, help="去掉小于此格数的孤立碎点")
    t.add_argument("--fringe", type=int, default=0, help="去淡紫光晕：红蓝都比绿高出此值的算底（0 = 关）")
    t.add_argument("--snap", default="", help="设定色阶 hex，逗号分隔：量化后吸附到最近的一个")
    t.add_argument("--order", default="", help="输出格号顺序，如 0,1,2,3,4,5,6,7"); t.add_argument("--zoom", type=int, default=3)
    lp = sp.add_parser("loop", help="几条长带 → 首尾相接的无缝周期贴图（pixfx §8）")
    lp.add_argument("--src", default=""); lp.add_argument("--name", required=True)
    lp.add_argument("--rows", type=int, default=3, help="图里几条带（= 变体数）"); lp.add_argument("--seg", default="128x16", help="每个变体 长x高 格")
    lp.add_argument("--cell", type=int, default=3); lp.add_argument("--colors", type=int, default=12); lp.add_argument("--lum", type=float, default=0.9)
    lp.add_argument("--cover", type=float, default=0.4); lp.add_argument("--accent", type=float, default=0.0); lp.add_argument("--fill", type=float, default=0.9)
    lp.add_argument("--overlap", type=int, default=8, help="接缝重叠格数"); lp.add_argument("--snap", default=""); lp.add_argument("--fringe", type=int, default=0)
    lp.add_argument("--drop", type=int, default=0)
    s = sp.add_parser("sheet")
    for q in (g, x, s, t, lp):
        q.add_argument("--tag", required=True); q.add_argument("--ref", nargs="*", default=[])
    a = p.parse_args()
    {"gen": cmd_gen, "pixel": cmd_pixel, "sheet": cmd_sheet, "strip": cmd_strip, "loop": cmd_loop}[a.cmd](a)


if __name__ == "__main__":
    main()
