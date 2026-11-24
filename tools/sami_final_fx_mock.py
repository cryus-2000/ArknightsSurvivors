#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""萨米结局 Boss 招牌招特效方向样张（11-25，只出样张不实装）：pixelfx 效果 tools/pixelfx_fx/foe/ak-sami-final.js 按方向分两层
（贴地 under / 上层 over）导出，合成到萨米雪地（双王用临时调色的灰紫沙地）+ 本体帧条（claude/sami-enemy-sprites）上，
1 倍（1 纹素 = 2 屏幕像素）、原速、30 帧，出一条 mp4 + 一张关键帧总览。

需要：主仓库 build/pixelfx、node、imageio_ffmpeg、git 能读到 claude/sami-map-art-wip（雪地砖）与 claude/sami-enemy-sprites（本体）。
用法（仓库根目录）：python tools/sami_final_fx_mock.py [--out F:/sami_enemy_fx_ref/final_dirs] [--only willA,...]
"""
import argparse, io, json, os, shutil, subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "pixelfx")
SRC = os.path.join(ROOT, "tools", "pixelfx_fx", "foe", "ak-sami-final.js")
W, H, FPS = 1280, 720, 30
OUTLINE = (8, 14, 24)

# 与 ak-sami-final.js 的 POS / DURS / leadPos 对应
POS = {"will": (-150, 20), "lead": [(-150, 30), (-60, -25), (30, 30), (125, -20)], "cresFrom": (-130, 20), "cresTo": (110, 10), "khan": (-110, 15), "lion": (110, 15)}
DURS = {"willA": 6.0, "willB": 6.0, "leadA": 6.4, "leadB": 6.4, "cresA": 6.5, "cresB": 6.5, "kingsA": 7.4, "kingsB": 7.4}
LABEL = {
    "willA": ("萨米的意志 · 方向 A「坠冰」（特效原作白 + 冰蓝，弹环虹光紫）", "冰凌：落点影子 → 高处冰光 → 坠地碎开、冰屑余烬 ｜ 叹息：雪往胸口收 → 风雪碎块 + 弹幕「雪花」12 枝冰枝，缺口整枝空掉"),
    "willB": ("萨米的意志 · 方向 B「地生冰凌」（特效原作白 + 冰蓝，弹环虹光紫）", "冰凌：地裂沿列跑过 → 从地里顶出再碎 ｜ 叹息：脚下地裂外爬 → 冰凌一圈圈顶出 + 弹幕「冰凌」18 道针弹"),
    "leadA": ("「木裂」埃克提尔尼尔 · 方向 A 原作深青（smlead_buff）· 2 倍镜头", "自我泯灭（不出弹）：三段折线狂奔；身上冒深青黑气、黑白碎片剥落、脚下迸火星、深青残影、两道刮痕；越往后掉得越多"),
    "leadB": ("「木裂」埃克提尔尼尔 · 方向 B 黑红剥离 · 2 倍镜头", "自我泯灭（不出弹）：三段折线狂奔；身上裂出发光红缝、黑红碎片剥落、脚下迸火星、暗红残影 + 暗红拖痕"),
    "cresA": ("无垠回荡克雷松 · 方向 A 原作靛黑（实机：黑靛球体 + 白四芒星；苗圃淡紫）", "闪现：落点眼纹先睁 → 黑速度线收进身体 → 碎成几片空间碎片 + 四芒星闪 → 地缝挤出、苗圃铺开 ｜ 稳定场：格点随波前亮 + 场边光幕"),
    "cresB": ("无垠回荡克雷松 · 方向 B 苗圃淡紫（原作苗圃色）", "闪现：身体压成一条缝 + 淡紫残影碎掉、碎片漂开 → 眼纹 → 挤出、苗圃铺开 ｜ 稳定场：6 根锚桩升起、顶上光柱 + 光点沿边流"),
    "kingsA": ("哈兰杜汗 + 路加萨尔古斯 · 方向 A「裂地 + 日晷」（路加原作金橙；底图时光之沙）", "征服：圈边沙丘隆起、裂纹爬向圆心 → 沙流迸散 + 余烬 + 弹幕「裂地」 ｜ 敕令：刻度 + 指针 → 沙流迸散 + 弹幕「日晷」12 刻度顺时针逐发射出"),
    "kingsB": ("哈兰杜汗 + 路加萨尔古斯 · 方向 B「鞭阵 + 箭阵」（路加原作金橙；底图时光之沙）", "征服：三道鞭痕越抽越快 → 收进圆心、沙流迸散 + 弹幕「鞭」三条螺旋臂 ｜ 敕令：16 支金箭立在圈外 → 扎下 → 弹幕「箭雨」两波针弹"),
}
ZOOM = {"leadA": 2.0, "leadB": 2.0}   # 木裂人小、路线短：这两段用 2 倍镜头（其余 1 倍）
CAM = {"leadA": (-12, 2), "leadB": (-12, 2)}   # 镜头中心（纹素）：木裂三段路线居中
LIGHT_K = 0.8
CX, CY = 0, 0   # 光层（rice 弹光 / 余烬 / 光柱）加色强度
Z = 1.0
SPR = {"will": "will", "lead": "lead", "cres": "cresson", "khan": "khan", "lion": "lion"}


def ease_iq(u):
    return 2 * u * u if u < 0.5 else 1 - (-2 * u + 2) ** 2 / 2


def lead_pos(t):
    P = POS["lead"]
    for i in range(3):
        d0 = 1.4 + 1.6 * i
        if t < d0:
            return P[i][0], P[i][1], -1
        if t < d0 + 1.0:
            u = ease_iq((t - d0) / 1.0)
            return P[i][0] + (P[i + 1][0] - P[i][0]) * u, P[i][1] + (P[i + 1][1] - P[i][1]) * u, i
    return P[3][0], P[3][1], -1


def outline(f):
    solid = f[..., 3] >= 128
    nb = np.zeros(solid.shape, np.int32)
    nb[1:, :] += solid[:-1, :]; nb[:-1, :] += solid[1:, :]; nb[:, 1:] += solid[:, :-1]; nb[:, :-1] += solid[:, 1:]
    core = solid & (nb >= 2)
    grow = core.copy()
    grow[1:, :] |= core[:-1, :]; grow[:-1, :] |= core[1:, :]; grow[:, 1:] |= core[:, :-1]; grow[:, :-1] |= core[:, 1:]
    edge = grow & ~solid
    out = f.copy()
    out[edge, :3] = OUTLINE
    out[edge, 3] = 255
    return out


def render(part, layer, tmp):
    d = os.path.join(tmp, part + "_" + layer)
    os.makedirs(d, exist_ok=True)
    opts = json.dumps({"part": part, "layer": layer, "seed": 7})
    subprocess.run(["node", "tools/ak_layers.mjs", "foe/ak-sami-final", "--out", d, "--opts", opts], cwd=PFX, check=True, capture_output=True)
    meta = json.load(open(os.path.join(d, "meta.json")))
    w, h = meta["frameSize"]
    col = np.asarray(Image.open(os.path.join(d, "color.png")).convert("RGBA"))
    lit = np.asarray(Image.open(os.path.join(d, "light.png")).convert("RGB"))
    n = min(meta["frames"], int(round(DURS[part] * 15)))
    return [outline(col[:, i * w:(i + 1) * w]) for i in range(n)], [lit[:, i * w:(i + 1) * w] for i in range(n)]


def git_png(ref, path):
    return Image.open(io.BytesIO(subprocess.run(["git", "show", "%s:%s" % (ref, path)], cwd=ROOT, check=True, capture_output=True).stdout)).convert("RGBA")


def background(sand, w, h):
    """世界像素大小 w×h 的地面：萨米雪地图素材（claude/sami-map-art-wip，与 sami.json 同一套）拼出来；sand 时换原作时光之沙米黄沙地 + 风沙条"""
    ref = "claude/sami-map-art-wip"
    art = lambda n: git_png(ref, "game/art/world/sami/%s.png" % n)
    tiles = np.asarray(art("sami_tiles")).astype(np.float32)
    rng = np.random.default_rng(3)
    bg = np.zeros((h, w, 3), np.float32)
    for gy in range(0, h, 32):
        for gx in range(0, w, 32):
            v = rng.integers(0, 4)
            t = tiles[:, v * 16:(v + 1) * 16, :3].repeat(2, 0).repeat(2, 1)
            bg[gy:gy + 32, gx:gx + 32] = t[: h - gy, : w - gx]
    k = np.array([168, 176, 196], np.float32) / bg.reshape(-1, 3).mean(0)   # 按局内截图（sami-map-art/ingame/sami/shot_t20.png）空地中位色
    img = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8)).convert("RGBA")
    if not sand:
        pat = art("sami_patches")
        for i in range(max(2, w * h // 260000)):   # 露出的苔原 / 雪堆斑块（256 世界像素）
            kind = rng.integers(0, 3)
            im = pat.crop((kind * 128, 0, kind * 128 + 128, 128)).resize((256, 256), Image.NEAREST)
            img.alpha_composite(im, (int(rng.integers(-80, w - 160)), int(rng.integers(-80, h - 160))))
        small = ["sami_shrub", "sami_snowtuft", "sami_stones", "sami_iceflower", "sami_antler", "sami_mushroom", "sami_snowtuft", "sami_shrub"]
        for i in range(w * h // 70000):
            im = art(small[i % len(small)])
            if im.width > 16 and im.height < 10:
                im = im.crop((0, 0, im.width // 2, im.height))
            im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
            img.alpha_composite(im, (int(rng.integers(0, w - im.width)), int(rng.integers(0, h - im.height))))
        for n, (fx, fy) in (("prop_sami_tree", (0.95, 0.02)), ("prop_sami_icerock", (0.02, 0.78))):
            im = art(n)
            im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
            img.alpha_composite(im, (int(fx * w - im.width / 2), int(fy * h)))
    a = np.asarray(img).astype(np.float32)[..., :3] * k
    if sand:   # 时光之沙：亮度映射到米黄沙色阶 + 斜向深色风沙条（实机 BV1Ds421A7E3 3615 s）
        lum = a.mean(2, keepdims=True) / 180.0
        a = np.clip(lum * np.array([198, 172, 134], np.float32), 0, 255)
        out = Image.fromarray(a.astype(np.uint8))
        d = ImageDraw.Draw(out)
        for i in range(w * h // 9000):
            x, y, L = int(rng.integers(0, w)), int(rng.integers(0, h)), int(rng.integers(30, 120))
            d.line((x, y, x + L, y + L // 6), fill=(150, 124, 92) if i % 3 else (120, 96, 70), width=int(rng.integers(1, 3)))
        a = np.asarray(out).astype(np.float32)
    return np.clip(a, 0, 255)


def sprites():
    meta = json.loads(subprocess.run(["git", "show", "claude/sami-enemy-sprites:game/themes/sami/data/enemy_pixels.json"], cwd=ROOT, check=True, capture_output=True).stdout)
    out = {}
    for k, n in SPR.items():
        im = git_png("claude/sami-enemy-sprites", "game/art/enemies/sami/e_sami_%s@2x.png" % n)
        m = meta["e_sami_" + n]
        fw, fh = m["frame_size"]
        frames = [im.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(m["frames"])]   # @2x 原图：1 倍镜头缩一半，2 倍镜头原样
        out[k] = (frames, m["anchor"])
    return out


def paste(canvas, spr, x, y, t, sx=1.0, sy=1.0, flip=False, tint=None, rowdrop=0):
    frames, (ax, ay) = spr
    im = frames[int(t * 8) % len(frames)]
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        ax = 1 - ax
    w, h = im.size
    nw, nh = max(1, int(w * sx * Z / 2)), max(1, int(h * sy * Z / 2))
    if (nw, nh) != (w, h):
        im = im.resize((nw, nh), Image.NEAREST)
    a = np.asarray(im).copy()
    if tint is not None:
        m = a[..., 3] > 0
        a[m, :3] = tint
    if rowdrop:
        a[::rowdrop + 1, :, 3] = 0
    im = Image.fromarray(a)
    sx0, sy0 = int(640 + 2 * Z * (x - CX) - ax * nw), int(360 + 2 * Z * (y - CY) - ay * nh)
    canvas.alpha_composite(im, (sx0, sy0)) if sx0 >= 0 and sy0 >= 0 else canvas.paste(im, (sx0, sy0), im)


def bodies(part, canvas, t, S):
    if part.startswith("will"):
        paste(canvas, S["will"], *POS["will"], t)
    elif part.startswith("lead"):
        x, y, dash = lead_pos(t)
        tint = (11, 74, 53) if part == "leadA" else (85, 16, 16)
        if dash >= 0 or (t > 1.4 and t < 6.0):
            for k in (5, 4, 3, 2, 1):   # 残影：每 0.07 秒一个，越旧越碎（隔行掉）
                tx = t - 0.07 * k
                px, py, dk = lead_pos(tx)
                if dk >= 0:
                    a, b = POS["lead"][dk], POS["lead"][dk + 1]
                    paste(canvas, S["lead"], px, py, tx, flip=b[0] < a[0], tint=tint, rowdrop=2 if k <= 2 else 1)
        fl = False
        if dash >= 0:
            a, b = POS["lead"][dash], POS["lead"][dash + 1]
            fl = b[0] < a[0]
        paste(canvas, S["lead"], x, y, t, flip=fl)
    elif part.startswith("cres"):
        A = part == "cresA"
        if t < 0.6:
            paste(canvas, S["cres"], *POS["cresFrom"], t)
        elif t < 0.9:
            k = 1 - (t - 0.6) / 0.3
            paste(canvas, S["cres"], *POS["cresFrom"], t, sx=max(0.04, k), sy=max(0.04, k) if A else 1.0)
        if not A and 0.9 <= t < 1.6:   # 病绿残影留在原地，一层层碎掉
            paste(canvas, S["cres"], *POS["cresFrom"], t, tint=(156, 124, 200), rowdrop=max(1, 4 - int((t - 0.9) / 0.2)))
        if t >= 1.5:
            k = min(1.0, 0.08 + (t - 1.5) / 0.25)
            paste(canvas, S["cres"], *POS["cresTo"], t, sy=k, sx=1.0 if k >= 1 else 0.85 + 0.15 * k)
    else:
        flash_l = 2.5 <= t < 2.57
        flash_k = 6.1 <= t < 6.17
        paste(canvas, S["khan"], *POS["khan"], t, tint=(255, 255, 255) if flash_k else None)
        paste(canvas, S["lion"], *POS["lion"], t, flip=True, tint=(255, 255, 255) if flash_l else None)


def compose(part, under, over, light, S, bg, fonts):
    global Z, CX, CY
    Z = ZOOM.get(part, 1.0)
    CX, CY = CAM.get(part, (0, 0))
    out = []
    n = len(over)
    cw, chh = int(640 / Z), int(360 / Z)
    x0, y0 = 320 + CX - cw // 2, 180 + CY - chh // 2
    crop = lambda a: a[y0:y0 + chh, x0:x0 + cw]
    bgz = Image.fromarray(bg.astype(np.uint8)).resize((W, H), Image.NEAREST)
    for i in range(n * 2):
        t = i / FPS
        fi = min(n - 1, i // 2)
        canvas = bgz.convert("RGBA")
        canvas.alpha_composite(Image.fromarray(crop(under[fi])).resize((W, H), Image.NEAREST))
        bodies(part, canvas, t, S)
        canvas.alpha_composite(Image.fromarray(crop(over[fi])).resize((W, H), Image.NEAREST))
        lt = np.asarray(Image.fromarray(crop(light[fi])).resize((W, H), Image.BILINEAR)).astype(np.float32)
        rgb = np.clip(np.asarray(canvas)[..., :3].astype(np.float32) + lt * LIGHT_K, 0, 255).astype(np.uint8)
        canvas = Image.fromarray(np.dstack([rgb, np.full((H, W), 255, np.uint8)]), "RGBA")
        d = ImageDraw.Draw(canvas)
        t1, t2 = LABEL[part]
        for txt, y, f in ((t1, 14, fonts[0]), (t2, 46, fonts[1])):
            d.text((22 + 2, y + 2), txt, font=f, fill=(0, 0, 0, 255))
            d.text((22, y), txt, font=f, fill=(255, 255, 255, 255))
        d.text((24, H - 30), "方向样张（未实装）· %g 倍 · 原速 · %.1f s" % (Z, t), font=fonts[1], fill=(0, 0, 0, 255))
        d.text((22, H - 32), "方向样张（未实装）· %g 倍 · 原速 · %.1f s" % (Z, t), font=fonts[1], fill=(255, 255, 255, 255))
        out.append(np.asarray(canvas.convert("RGB")))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="F:/sami_enemy_fx_ref/final_dirs")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    shutil.copy(SRC, os.path.join(PFX, "src", "fx", "foe", "ak-sami-final.js"))
    tmp = os.path.join(a.out, "tmp")
    S = sprites()
    ff = "C:/Windows/Fonts/msyhbd.ttc" if os.path.exists("C:/Windows/Fonts/msyhbd.ttc") else os.path.join(ROOT, "game", "fonts", "ui.ttf")   # ui.ttf 缺「垠 / 晷 / 敕」
    fonts = (ImageFont.truetype(ff, 24), ImageFont.truetype(ff, 17))
    bgs = {}
    parts = [p for p in DURS if not a.only or p in a.only.split(",")]
    import imageio_ffmpeg
    allf, keys = [], []
    for part in parts:
        under, _ = render(part, "under", tmp)
        over, light = render(part, "over", tmp)
        z = ZOOM.get(part, 1.0)
        key = (part.startswith("kings"), z)
        if key not in bgs:
            bgs[key] = background(key[0], int(W / z), int(H / z))
        fr = compose(part, under, over, light, S, bgs[key], fonts)
        Image.fromarray(fr[0]).save(os.path.join(a.out, part + "_f0.png"))
        np.save(os.path.join(tmp, part + "_n.npy"), np.array([len(fr)]))
        for k, f in enumerate(fr):
            if k % 6 == 0:
                Image.fromarray(f).save(os.path.join(tmp, "%s_%03d.png" % (part, k)))
        allf += fr
        print(part, len(fr), "frames")
    mp4 = os.path.join(a.out, "sami_final_boss_fx_dirs_1125.mp4")
    wr = imageio_ffmpeg.write_frames(mp4, (W, H), fps=FPS, codec="libx264", output_params=["-crf", "22", "-pix_fmt", "yuv420p", "-an"], macro_block_size=1)
    wr.send(None)
    for f in allf:
        wr.send(np.ascontiguousarray(f))
    wr.close()
    print(mp4, os.path.getsize(mp4) // 1024, "KB")


if __name__ == "__main__":
    main()
