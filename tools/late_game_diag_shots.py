#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期诊断截图与分层量测（docs/243）：同种子同一局在 3:00 / 8:00 / 9:30 / 10:40 各拍一张 1280×720（云端 xvfb + opengl3）。
同一局再用 --clutterdbg=nofriend / noenemy / nofoe 各跑一遍（该层全透明、代码照跑），逐像素差出各层掩码，量
我方攻击特效 / 敌人 / 敌方弹幕的占屏面积、亮度、对比度，和地面比。特效新版开关一律缺省（关）。

用法（仓库根目录，Linux 云端）：
    python tools/late_game_diag_shots.py shoot  --ops texas,exusiai,eyjafjalla,skalter --seed 11
    python tools/late_game_diag_shots.py measure --out docs/assets/late_game_diag
"""
import argparse, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

SHOT = os.path.join(ROOT, "build", "late_diag", "shots")
SPF = 0.0659                       # 非实时平衡模式约 0.0659 局内秒 / 渲染帧（late_clutter.py 同口径）
TARGETS = [180, 480, 570, 640]     # 3:00 / 8:00 / 9:30 后期满屏 / 10:40 最终 Boss 战
LAYERS = ["full", "nofriend", "noenemy", "nofoe"]
WORLD_BOX = (180, 150, 1100, 560)  # 中央战场区（避开顶栏 / 小地图 / 编队卡）


def frames():
    out = []
    for t in TARGETS:
        f = int(round(t / SPF))
        out += [f, f + 4]
    return out


EXTRA = []   # shoot --squad / --relics 透传（召唤物专项，docs/243 §5）
TAG = ""


def shoot_one(job):
    op, seed, layer = job
    d = os.path.join(SHOT, "%s%s_s%d_%s" % (op, TAG, seed, layer))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", GR.find_godot(), "--rendering-driver", "opengl3", "--path", os.path.join(ROOT, "game"),
            "--resolution", "1280x720", "--audio-driver", "Dummy", "--fixed-fps", "60", "--",
            "--balance", "--nodeath", "--seed=%d" % seed, "--op=" + op, "--maxt=%d" % (TARGETS[-1] + 5),
            "--shots=" + ",".join(str(f) for f in frames()), "--clutterlog", "--shotdir=" + d]
    args += EXTRA
    if layer != "full":
        args.append("--clutterdbg=" + layer)
    p = subprocess.run(args, capture_output=True, text=True, timeout=5400)
    errs = [l for l in (p.stdout + p.stderr).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    return job, len(os.listdir(d)), errs[:3]


def cmd_shoot(a):
    global TAG
    if a.squad:
        EXTRA.append("--squad=" + a.squad)
    if a.relics:
        EXTRA.append("--relics=" + a.relics)
    TAG = a.tag
    jobs = [(op, a.seed, ly) for op in a.ops.split(",") for ly in a.layers.split(",")]
    with ThreadPoolExecutor(a.jobs) as ex:
        for job, n, errs in ex.map(shoot_one, jobs):
            print(job, "files", n, errs, flush=True)


def _load(op, seed, layer, f):
    from PIL import Image
    import numpy as np
    p = os.path.join(SHOT, "%s_s%d_%s" % (op, seed, layer), "shot_%d.png" % f)
    if not os.path.exists(p):
        return None
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0


def _luma(im):
    return 0.2126 * im[..., 0] + 0.7152 * im[..., 1] + 0.0722 * im[..., 2]


def cmd_measure(a):
    import numpy as np
    from PIL import Image
    from scipy import ndimage as ndi
    os.makedirs(a.out, exist_ok=True)
    x0, y0, x1, y1 = WORLD_BOX
    rows = []
    for op in a.ops.split(","):
        for ti, t in enumerate(TARGETS):
            f = frames()[ti * 2]
            full = _load(op, a.seed, "full", f)
            if full is None:
                continue
            meta = json.load(open(os.path.join(SHOT, "%s_s%d_full" % (op, a.seed), "shot_%d.json" % f)))
            box = lambda im: im[y0:y1, x0:x1]
            F = box(full)
            masks = {}
            for ly in ["nofriend", "noenemy", "nofoe"]:
                im = _load(op, a.seed, ly, f)
                masks[ly] = (np.abs(box(im) - F).max(axis=2) > 0.06) if im is not None else np.zeros(F.shape[:2], bool)
            mf, me, mb = masks["nofriend"], masks["noenemy"], masks["nofoe"]
            ground = ~(mf | me | mb)
            L = _luma(F)
            mx = F.max(axis=2)
            mn = F.min(axis=2)
            sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
            # 敌人白闪 / 高亮：敌人掩码里接近白色（亮度 > 0.8、饱和度 < 0.25）的像素
            white_e = me & (L > 0.8) & (sat < 0.25)
            # 我方特效对比度：掩码内平均亮度 − 掩码外 6 像素环带的平均亮度
            def ring_contrast(m):
                if m.sum() < 30:
                    return None
                ring = ndi.binary_dilation(m, iterations=6) & ~m
                return float(L[m].mean() - L[ring].mean())
            # 我方特效被盖：我方掩码里有多少像素同时落在敌人 / 敌弹掩码上（层叠在一起）
            ov_e = float((mf & me).sum() / max(1, mf.sum()))
            ov_b = float((mf & mb).sum() / max(1, mf.sum()))
            pct = lambda m: float(m.mean() * 100)
            mean_l = lambda m: float(L[m].mean()) if m.sum() else None
            # 我方特效的连通块：数量与中位面积（像素），看「碎点」还是「实心主形」
            lab, n = ndi.label(mf)
            sizes = np.bincount(lab.ravel())[1:] if n else np.array([0])
            rows.append({"op": op, "t_target": t, "t": meta.get("t"), "frame": f, "enemies_on": meta.get("enemies_on"), "fx_friend": meta.get("fx_friend"),
                         "crowd": round(meta.get("crowd", 0), 3), "ecrowd": round(meta.get("ecrowd", 0), 3), "dcrowd": round(meta.get("dcrowd", 0), 3),
                         "fx_dim": round(meta.get("fx_dim", 1), 3),
                         "friend_pct": pct(mf), "enemy_pct": pct(me), "foe_pct": pct(mb), "white_in_enemy_pct": pct(white_e),
                         "L_friend": mean_l(mf), "L_enemy": mean_l(me), "L_foe": mean_l(mb), "L_ground": mean_l(ground),
                         "L_ground_std": float(L[ground].std()) if ground.sum() else None,
                         "C_friend": ring_contrast(mf), "C_enemy": ring_contrast(me),
                         "friend_on_enemy": ov_e, "friend_on_foe": ov_b,
                         "friend_blobs": int(n), "friend_blob_med": float(np.median(sizes)) if n else 0, "friend_blob_p90": float(np.percentile(sizes, 90)) if n else 0})
            # 掩码可视化：原图 + 我方（青）/ 敌人（品红）/ 敌弹（橙）描边
            vis = (full * 255).astype(np.uint8).copy()
            sub = vis[y0:y1, x0:x1]
            for m, c in [(me, (255, 60, 200)), (mb, (255, 150, 0)), (mf, (0, 255, 255))]:
                edge = m & ~ndi.binary_erosion(m, iterations=1)
                sub[edge] = c
            Image.fromarray(vis).save(os.path.join(a.out, "mask_%s_%d.png" % (op, t)))
            Image.fromarray((full * 255).astype(np.uint8)).save(os.path.join(a.out, "shot_%s_%d.png" % (op, t)))
    json.dump(rows, open(os.path.join(a.out, "visual_metrics.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for r in rows:
        print({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})


def main():
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="cmd")
    s = sp.add_parser("shoot")
    s.add_argument("--ops", default="texas,exusiai,eyjafjalla,skalter")
    s.add_argument("--seed", type=int, default=11)
    s.add_argument("--jobs", type=int, default=4)
    s.add_argument("--squad", default="")
    s.add_argument("--relics", default="")
    s.add_argument("--tag", default="")
    s.add_argument("--layers", default=",".join(LAYERS))
    m = sp.add_parser("measure")
    m.add_argument("--ops", default="texas,exusiai,eyjafjalla,skalter")
    m.add_argument("--seed", type=int, default=11)
    m.add_argument("--out", default=os.path.join(ROOT, "docs", "assets", "late_game_diag"))
    a = p.parse_args()
    {"shoot": cmd_shoot, "measure": cmd_measure}.get(a.cmd, lambda _: p.print_help())(a)


if __name__ == "__main__":
    main()
