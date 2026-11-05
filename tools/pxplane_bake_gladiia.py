#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""歌蕾蒂娅「转平面」帧条烘焙（docs/263，开关 fx/px_plane）：用 pixelfx 库按目标尺寸逐件生成，裁边后进 game/art/fx/pxp/pxp_gl_*.png。

效果源：tools/pixelfx_fx/water/ak-gladiia-pp.js（拷进本机 pixelfx 库 build/pixelfx 的 src/fx/water/ 再跑 tools/ak_layers.mjs）。
单独一份（不改 tools/pxplane_bake.py，免得和同批其他干员的 OPS 表冲突），做法同 pxplane_bake.bake：
  pxp_gl_<键>.png       单行帧条，色层（直通 alpha，不含光晕）；raw_ 开头的是旧做法对照（光晕烤进颜色）；
  data/pxp_gladiia.json 帧数、fps、帧尺寸、原点（脚底 / 地面点）、loop、每帧 emit 点表；
  .png.import           按现有帧条的格式生成（GCP 上会再 --import 一次）。
和 pxplane_bake 的一处不同：循环件的周期按每件自己写（S3 龙卷 0.6 秒 = 9 帧，流纹三重对称、每圈转 120°），不固定 0.4 秒。

用法（仓库根目录）：python tools/pxplane_bake_gladiia.py [--only 键前缀]
"""
import argparse, hashlib, json, os, random, shutil, subprocess
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PFX = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else os.path.dirname(ROOT), "build", "pixelfx")
if not os.path.isdir(PFX):
    PFX = os.path.join(ROOT, "build", "pixelfx")
OUT_ART = os.path.join(ROOT, "game", "art", "fx", "pxp")
OUT_META = os.path.join(ROOT, "game", "data", "pxp_gladiia.json")
FX_ID = "water/ak-gladiia-pp"
PREFIX = "gl_"
TMP = os.path.join(ROOT, "build", "pxp_bake")
FPS = 15
DIRS = [-90, -45, 0, 45, 90]
EMIT_LUMA = 0.95
EMIT_MAX = 48
ACC_RG = [(0xb3, 0xa8)]   # 精二深渊紫点缀也进发光层


def variants():
    """判定从 gladiia.json 读，美术像素 = 世界 / 2。键不含干员前缀（烘焙时加 gl_）。"""
    v = []
    T = (0, 1, 2)
    # 普攻钩索落地（hook_r 77 → 38）；范围成长（late_shape 控场 +25% / 档、范围卡）放大判定，按三档半径预生成
    for R in (38, 52, 66):
        for el in T:
            for ly in ("up", "gd"):
                v.append(("hit_r%d_e%d_%s" % (R, el, ly), {"part": "hit", "layer": ly, "R": R, "el": el, "seed": 3 + el}, 0.47))
    # S1 重钩落地（s1_r 70 → 35）
    for R in (35, 48, 61):
        for el in T:
            for ly in ("up", "gd"):
                v.append(("s1hit_r%d_e%d_%s" % (R, el, ly), {"part": "s1hit", "layer": ly, "R": R, "el": el, "seed": 5 + el}, 0.6))
    # 拖回到位：拍水 + 精一起锚印（锚定眩晕 1.4 秒，锚印 1.05 秒散完）
    for el in T:
        v.append(("arr_e%d_up" % el, {"part": "arrive", "layer": "up", "el": el, "big": 0, "seed": 7}, 0.4))
        v.append(("arr_e%d_gd" % el, {"part": "arrive", "layer": "gd", "el": el, "big": 0, "seed": 7}, 0.6 if el == 0 else 1.1))
        v.append(("s1arr_e%d_up" % el, {"part": "arrive", "layer": "up", "el": el, "big": 1, "seed": 9}, 0.4))
        v.append(("s1arr_e%d_gd" % el, {"part": "arrive", "layer": "gd", "el": el, "big": 1, "seed": 9}, 0.6 if el == 0 else 1.1))
    # 精二「冲撞」（ram_r 80 → 40）/ 反震（pop_r 120 → 60）/ 扩散（splash_r 60 → 30）：往外走的浪环
    for k, R, H, el, dur in (("ram", 40, 13, 2, 0.45), ("pop", 60, 9, 1, 0.5), ("splash", 30, 5, 0, 0.3)):
        for ly in ("bk", "up", "gd"):
            v.append(("%s_%s" % (k, ly), {"part": "wave", "layer": ly, "R": R, "H": H, "el": el, "dur": dur, "seed": 11 + R}, dur + 0.04))
    # S2 起手水环（远半圈 bk / 近半圈 + 水柱 up / 地面 gd）、持续脚下浪沫圈（循环）、每次掷钩拉近身边（s2_pull_r 160 → 80）
    for el in (1, 2):
        for ly in ("bk", "up", "gd"):
            v.append(("s2cast_e%d_%s" % (el, ly), {"part": "s2cast", "layer": ly, "R": 46, "el": el, "seed": 13}, 0.62))
        v.append(("s2aura_e%d_gd" % el, {"part": "s2aura", "layer": "gd", "R": 17, "el": el, "dur": 0.6, "seed": 15, "_loop": 0.6}, 0.6))
        for ly in ("bk", "up", "gd"):
            v.append(("s2pull_e%d_%s" % (el, ly), {"part": "backwash", "layer": ly, "R": 80, "H": 4, "el": el, "dur": 0.3, "big": 0, "seed": 17}, 0.34))
    # S3 龙卷（s3_r 130 → 65，高 56）：起 / 循环 / 收，每段三层；每跳地上收拢弧
    for mode, dur in (("open", 0.34), ("loop", 0.6), ("close", 0.56)):
        for ly in ("bk", "up", "gd"):
            o = {"part": "tornado", "layer": ly, "mode": mode, "R": 65, "H": 48, "el": 2, "dur": dur, "seed": 19}
            if mode == "loop":
                o["_loop"] = 0.6
            v.append(("s3%s_%s" % (mode, ly), o, dur))
    v.append(("s3tick_gd", {"part": "tick", "layer": "gd", "R": 65, "seed": 21}, 0.34))
    # 回收斩（成长节点，slash_r 160 / 半角 65° → 半径 80、弧 2.27），方向件
    for d in DIRS:
        for ly in ("up", "gd"):
            v.append(("slash_%s_d%d" % (ly, d), {"part": "slash", "layer": ly, "R": 80, "span": 2.27, "W": 12, "dir": d, "dur": 0.3, "seed": 23}, 0.34))
    # 怒海·暗涌水柱（geyser_r 30 → 15）
    for ly in ("up", "gd"):
        v.append(("geyser_%s" % ly, {"part": "geyser", "layer": ly, "R": 15, "H": 30, "W": 3, "el": 1, "seed": 25}, 0.5))
    # 连携「聚拢」（技能连携 v2 gather，区域 150 → 75）：四周海水往中心倒卷，汇到中心冲起一柱
    for ly in ("bk", "up", "gd"):
        v.append(("link_%s" % ly, {"part": "backwash", "layer": ly, "R": 75, "H": 7, "H2": 46, "el": 1, "dur": 0.28, "big": 1, "seed": 27}, 0.82))
    # raw：旧做法（不压扁、光晕烤进颜色），游戏里小数缩放贴上去
    v.append(("raw_hit", {"part": "hit", "layer": "up", "view": "raw", "R": 38, "el": 1, "seed": 3}, 0.47))
    v.append(("raw_s1hit", {"part": "s1hit", "layer": "up", "view": "raw", "R": 35, "el": 1, "seed": 5}, 0.6))
    v.append(("raw_ram", {"part": "wave", "layer": "up", "view": "raw", "R": 40, "H": 13, "el": 2, "dur": 0.45, "seed": 51}, 0.49))
    v.append(("raw_s3loop", {"part": "tornado", "layer": "up", "view": "raw", "mode": "loop", "R": 65, "H": 48, "el": 2, "dur": 0.6, "seed": 19, "_loop": 0.6}, 0.6))
    return v


def render(key, opts, dur):
    d = os.path.join(TMP, "ak-gladiia-pp", key)
    os.makedirs(d, exist_ok=True)
    o = {k: x for k, x in opts.items() if not k.startswith("_")}
    o.setdefault("dur", min(0.46, dur - 0.04))
    p = subprocess.run(["node", "tools/ak_layers.mjs", FX_ID, "--out", d, "--fps", str(FPS), "--opts", json.dumps(o)], cwd=PFX, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(key + ": " + p.stderr[-600:])
    return key, d, dur, opts.get("_loop", 0)


def bake(key, d, dur, loop):
    meta = json.load(open(os.path.join(d, "meta.json")))
    fw, fh = meta["frameSize"]
    n = meta["frames"]
    fps = meta["fps"]
    ox, oy = meta["pivot"]
    col = np.asarray(Image.open(os.path.join(d, "color.png")).convert("RGBA")).astype(np.float32) / 255.0
    lit = np.asarray(Image.open(os.path.join(d, "light.png")).convert("RGB")).astype(np.float32) / 255.0
    nf = int(round(loop * fps)) if loop else min(n, int(round(dur * fps)))
    frames = [col[:, i * fw:(i + 1) * fw] for i in range(nf)]
    lights = [lit[:, i * fw:(i + 1) * fw] for i in range(nf)]
    raw = key.startswith("raw_")
    if raw:
        out = []
        for c, l in zip(frames, lights):
            a = c[..., 3:4]
            rgb = np.clip(c[..., :3] * a + l * 0.9, 0, 1)
            al = np.clip(np.maximum(a[..., 0], l.max(axis=2) * 0.9), 0, 1)
            safe = np.where(al > 0.001, al, 1.0)[..., None]
            out.append(np.concatenate([np.clip(rgb / safe, 0, 1), al[..., None]], axis=2))
        frames = out
    while not loop and len(frames) > 1 and frames[-1][..., 3].max() <= 0.0:
        frames.pop()
    alpha = np.max(np.stack([f[..., 3] for f in frames]), axis=0)
    ys, xs = np.nonzero(alpha > 0.0)
    if len(xs) == 0:
        return key, None
    x0, x1, y0, y1 = max(0, xs.min() - 1), min(fw, xs.max() + 2), max(0, ys.min() - 1), min(fh, ys.max() + 2)
    w, h = x1 - x0, y1 - y0
    strip = np.zeros((h, w * len(frames), 4), np.float32)
    emit = []
    for i, f in enumerate(frames):
        c = f[y0:y1, x0:x1]
        strip[:, i * w:(i + 1) * w] = c
        if raw:
            emit.append([])
            continue
        luma = c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722
        acc = np.zeros(c.shape[:2], bool)
        for ar, ag in ACC_RG:
            acc |= (np.abs(c[..., 0] - ar / 255) < 0.02) & (np.abs(c[..., 1] - ag / 255) < 0.02)
        m = (c[..., 3] > 0.5) & ((luma >= EMIT_LUMA) | acc)
        py, px = np.nonzero(m)
        idx = np.arange(len(px))
        if len(idx) > EMIT_MAX:
            idx = idx[np.linspace(0, len(idx) - 1, EMIT_MAX).astype(int)]
        emit.append([[int(px[j]), int(py[j]), "%02x%02x%02x" % tuple(int(v * 255) for v in c[py[j], px[j], :3])] for j in idx])
    name = "pxp_%s%s.png" % (PREFIX, key)
    Image.fromarray((strip * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT_ART, name), optimize=True)
    write_import(name)
    return key, {"n": len(frames), "fps": fps, "w": int(w), "h": int(h), "ox": int(ox - x0), "oy": int(oy - y0), "loop": bool(loop), "emit": emit}


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://%s"
path="res://.godot/imported/%s-%s.ctex"
metadata={
"vram_texture": false
}

[deps]

source_file="res://art/fx/pxp/%s"
dest_files=["res://.godot/imported/%s-%s.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def write_import(name):
    p = os.path.join(OUT_ART, name + ".import")
    uid = None
    if os.path.exists(p):   # 重烘时保留原 uid
        for line in open(p, encoding="utf-8"):
            if line.startswith("uid="):
                uid = line.split("uid://")[1].strip().strip('"')
    if uid is None:
        rnd = random.Random(name)
        uid = "".join(rnd.choice("abcdefghijklmnopqrstuvwxy0123456789") for _ in range(13))
    md5 = hashlib.md5(("res://art/fx/pxp/" + name).encode()).hexdigest()
    open(p, "w", encoding="utf-8", newline="\n").write(IMPORT % (uid, name, md5, name, name, md5))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    shutil.copy(os.path.join(ROOT, "tools", "pixelfx_fx", "water", "ak-gladiia-pp.js"), os.path.join(PFX, "src", "fx", "water", "ak-gladiia-pp.js"))
    os.makedirs(OUT_ART, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    vs = [x for x in variants() if x[0].startswith(a.only)]
    reg = json.load(open(OUT_META, encoding="utf-8")) if os.path.exists(OUT_META) and a.only else {}
    reg.pop("_doc", None)
    with ThreadPoolExecutor(a.jobs) as ex:
        rs = list(ex.map(lambda x: render(*x), vs))
    for key, d, dur, lp in rs:
        k, m = bake(key, d, dur, lp)
        if m is None:
            print("空", k)
            continue
        reg[k] = m
        print("%-22s %2d 帧 %3d×%3d emit %d" % (k, m["n"], m["w"], m["h"], max((len(e) for e in m["emit"]), default=0)))
    reg = {k: reg[k] for k in sorted(reg)}
    reg["_doc"] = "docs/263 歌蕾蒂娅转平面帧条（tools/pxplane_bake_gladiia.py 生成，勿手改；游戏里键加前缀 gl_）：n 帧数、fps、w×h 帧尺寸（美术像素）、ox / oy 原点（脚底地面点）、loop、emit 每帧热芯点 [x, y, 颜色]"
    json.dump(reg, open(OUT_META, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print("共 %d 件" % (len(reg) - 1))


if __name__ == "__main__":
    main()
