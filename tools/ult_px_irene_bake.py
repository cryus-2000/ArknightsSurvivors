"""艾丽妮终结技「宣判」转平面（docs/275）：把用户 10-31 认可的审判纹章（game/art/fx/fx_irv_seal@2x.png）重采样到美术像素格并压扁贴地，
改成白色阶（11-05 用户改：纹章用白，紫留给斩击），烤成 game/art/fx/pxp/pxp_ult_ir_seal.png（游戏里只按 g.PX 整数放大，1 帧条像素 = 1 美术像素）。
纹章直径 = 终结技半径 550 × 2 世界像素 = 550 美术像素，高 × 0.72。用法：python tools/ult_px_irene_bake.py"""
import hashlib, os, sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ult_px_irene_art as A
from pxplane_bake_saria import IMPORT_TMPL

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "game", "art", "fx", "fx_irv_seal@2x.png")
OUT_DIR = os.path.join(ROOT, "game", "art", "fx", "pxp")
NAME = "pxp_ult_ir_seal.png"
D = 550


# 纹章色阶：白（11-05 用户「背景会不会太紫了，白的比较好，再加上白紫色斩击」）——偏冷的浅灰白，只在最暗一阶带一点紫，让紫留给斩击
SEAL_RAMP = ["#000000", "#000000", "#000000", "#7c7884", "#a8a4b0", "#d6d3dc", "#f6f4fa"]


def ramp():
    return np.array([A.hx3(c) for c in SEAL_RAMP], np.float32)


def main():
    src = Image.open(SRC).convert("RGBA")
    w, h = D, int(round(D * A.SQ))
    im = np.asarray(src.resize((w, h), Image.BOX)).astype(np.float32)
    a = im[..., 3] / 255.0
    rgb = im[..., :3] / 255.0
    lum = (0.3 * rgb[..., 0] + 0.59 * rgb[..., 1] + 0.11 * rgb[..., 2]) / np.maximum(a, 1e-3)
    lum = np.clip(lum, 0, 1)
    R = ramp()
    # 只留线稿（地面区域只画边，docs/246）：底盘的暗填充（亮度低于 LUM0）去掉；线稿亮度映射到 LT[3..6]，alpha 二值化成硬边
    LUM0 = 0.3
    t = np.clip((lum - LUM0) / (1.0 - LUM0), 0, 1)
    idx = np.clip(3 + (t * 4.0).astype(int), 3, 6)
    keep = (a > 0.3) & (lum >= LUM0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = R[idx].astype(np.uint8)
    out[..., 3] = np.where(keep, 255, 0).astype(np.uint8)
    print("线稿像素", int(keep.sum()), "/", w * h)
    p = os.path.join(OUT_DIR, NAME)
    Image.fromarray(out, "RGBA").save(p, optimize=True)
    ip = p + ".import"
    if not os.path.exists(ip):
        hsh = int(hashlib.sha1(("pxp_ult_ir/" + NAME).encode()).hexdigest(), 16)
        al = "abcdefghijklmnopqrstuvwxyz0123456789"
        uid = al[hsh % 26]
        hsh //= 26
        for _ in range(11):
            uid += al[hsh % 36]
            hsh //= 36
        md5 = hashlib.md5(("res://art/fx/pxp/" + NAME).encode()).hexdigest()
        with open(ip, "w", encoding="utf-8", newline="\n") as f:
            f.write(IMPORT_TMPL.format(uid=uid, name=NAME, md5=md5))
    print(NAME, w, h, "%.0f KB" % (os.path.getsize(p) / 1024))


if __name__ == "__main__":
    main()
