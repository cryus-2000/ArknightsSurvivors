# -*- coding: utf-8 -*-
"""组 E 帧条硬数字自检（docs/229 §0 / §2、docs/236）：按 targets_e.json 逐条（含变体）查
帧数 / 单帧尺寸 / fps / 本体 + glow 体积（≤ 14 KB）/ 调色板实用色数（≤ 32）/ 近白占比（≤ 12%）/ 余韵段最大 alpha（≤ 0.4）/
末帧最大 alpha / 水平外沿（世界像素，地面落点类应 ≤ 判定）。帧数从 art.gd 登记读。

    python tools/pixelfx_fx/foe/audit_e.py            打印表格并给合计；有超标的退出码 1
"""
import json, os, re, sys
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
FX = os.path.join(ROOT, "game", "art", "fx")
MAIN = {"impacts/ak-e-slam": 0.4}   # 主体时长（秒），其余 0.3；循环弹体不查余韵


def main():
    art = open(os.path.join(ROOT, "game", "scripts", "art.gd"), encoding="utf-8").read()
    tg = json.load(open(os.path.join(ROOT, "tools", "pixelfx_fx", "targets_e.json"), encoding="utf-8"))
    rows, bad, tot = [], 0, 0.0
    for name, spec in tg.items():
        if name.startswith("_"):
            continue
        for v in range(int(spec.get("variants", 3))):
            nm = name if v == 0 else "%s_v%d" % (name, v)
            suf = "@2x" if spec.get("hires") else ""
            p = os.path.join(FX, nm + suf + ".png")
            if not os.path.exists(p):
                rows.append("%-34s 缺文件" % nm); bad += 1; continue
            m = re.search(r'"%s": \[(\d+), ([0-9.]+)' % re.escape(nm), art)
            if not m:
                rows.append("%-34s 未登记 art.gd" % nm); bad += 1; continue
            n, fps = int(m.group(1)), float(m.group(2))
            im = Image.open(p)
            ncol = len(np.unique(np.asarray(im)))
            a = np.asarray(im.convert("RGBA")).astype(int)
            fw = a.shape[1] // n
            gp = os.path.join(FX, nm + "_glow" + suf + ".png")
            kb = (os.path.getsize(p) + (os.path.getsize(gp) if os.path.exists(gp) else 0)) / 1024
            tot += kb
            nz = a[:, :, 3] > 10
            white = (a[:, :, :3].min(axis=2) >= 230) & nz
            wpct = 100.0 * white.sum() / max(1, nz.sum())
            loop = "proj" in spec["fx"]
            t0 = MAIN.get(spec["fx"], 0.3)
            tail = [a[:, f * fw:(f + 1) * fw, 3].max() / 255 for f in range(n) if f / fps >= t0 - 1e-6]
            tmax = max(tail) if tail and not loop else 0.0
            last = a[:, (n - 1) * fw:, 3].max() / 255
            xs = np.nonzero((a[:, :, 3] > 40).any(axis=0))[0] % fw
            ext = (max(abs(xs - fw / 2 + 0.5)) * 2 * (1 if spec.get("hires") else 2)) if xs.size else 0
            flag = []
            if kb > 14: flag.append("体积")
            if ncol > 33: flag.append("色数")
            if wpct > 12: flag.append("近白")
            if tmax > 0.41: flag.append("余韵")
            if flag: bad += 1
            rows.append("%-34s %2d帧@%-4g %3dx%-3d %5.1f KB %2d色 近白%4.1f%% 余韵%4.2f 末帧%4.2f 外沿%4.0f %s" % (
                nm, n, fps, fw, a.shape[0], kb, ncol, wpct, tmax, last, ext, " ".join(flag)))
    print("\n".join(rows))
    print("合计 %.1f KB（本体 + glow，PNG）；超标 %d 条" % (tot, bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
