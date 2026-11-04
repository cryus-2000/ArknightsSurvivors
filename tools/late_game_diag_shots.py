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
LOOK_LAYERS = ["noflash"]          # 走 --lookdbg=（render/look.gd）：noflash = 敌人受击白闪不画
# 色彩与层级预算（docs/243 §6）用的全部分层：我方特效 / 敌人本体 / 敌方弹幕预警 / 环境颗粒 / 结晶 / 伤害数字 / 溟痕 / 地面光环叠层 / 地面 / 受击白闪
BUDGET_LAYERS = ["full", "nofriend", "noenemy", "nofoe", "noamb", "nogem", "nonum", "nomire", "noaura", "noground", "noflash"]
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
    os.makedirs(d, exist_ok=True)
    if layer in LOOK_LAYERS:
        args.append("--lookdbg=" + layer)
    elif layer != "full":
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
    for kv in (a.bal.split(",") if a.bal else []):
        EXTRA.append("--bal=" + kv)   # 旋钮覆盖（放置物对照 docs/246：--bal render/placeable_v2=1）
    if a.extra:
        EXTRA.extend(a.extra.split())   # docs/247：如 "--bal=render/late_read=1"
    TAG = a.tag
    if a.targets:
        TARGETS[:] = [int(x) for x in a.targets.split(",")]
    jobs = [(op, a.seed, ly) for op in a.ops.split(",") for ly in a.layers.split(",")]
    with ThreadPoolExecutor(a.jobs) as ex:
        for job, n, errs in ex.map(shoot_one, jobs):
            print(job, "files", n, errs, flush=True)


def _load(op, seed, layer, f):
    from PIL import Image
    import numpy as np
    p = os.path.join(SHOT, "%s%s_s%d_%s" % (op, TAG, seed, layer), "shot_%d.png" % f)
    if not os.path.exists(p):
        return None
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0


def _luma(im):
    return 0.2126 * im[..., 0] + 0.7152 * im[..., 1] + 0.0722 * im[..., 2]


def cmd_measure(a):
    global TAG
    TAG = a.tag
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
            meta = json.load(open(os.path.join(SHOT, "%s%s_s%d_full" % (op, TAG, a.seed), "shot_%d.json" % f)))
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
            Image.fromarray(vis).save(os.path.join(a.out, "mask_%s%s_%d.png" % (op, TAG, t)))
            Image.fromarray((full * 255).astype(np.uint8)).save(os.path.join(a.out, "shot_%s%s_%d.png" % (op, TAG, t)))
    json.dump(rows, open(os.path.join(a.out, "visual_metrics%s.json" % TAG), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for r in rows:
        print({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})


def _hsv(F):
    mx = F.max(axis=2)
    mn = F.min(axis=2)
    d = mx - mn
    import numpy as np
    h = np.zeros_like(mx)
    r, g, b = F[..., 0], F[..., 1], F[..., 2]
    nz = d > 1e-6
    i = nz & (mx == r)
    h[i] = ((g[i] - b[i]) / d[i]) % 6
    i = nz & (mx == g) & ~(mx == r)
    h[i] = (b[i] - r[i]) / d[i] + 2
    i = nz & (mx == b) & ~(mx == r) & ~(mx == g)
    h[i] = (r[i] - g[i]) / d[i] + 4
    return h * 60.0, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0), mx


HUE_NAMES = [(345, 15, "红"), (15, 45, "橙"), (45, 70, "金黄"), (70, 160, "绿"), (160, 200, "青"), (200, 255, "蓝"), (255, 300, "紫"), (300, 345, "洋红")]


def _hue_name(h):
    for a, b, n in HUE_NAMES:
        if (a > b and (h >= a or h < b)) or (a <= h < b):
            return n
    return "?"


def cmd_budget(a):
    """色彩与层级预算：同一帧各层（全透明差分）的占屏面积、主色、平均亮度及排名、红 / 洋红像素占比"""
    import numpy as np
    from PIL import Image
    global TAG
    TAG = a.tag
    TARGETS[:] = [int(x) for x in a.targets.split(",")]
    x0, y0, x1, y1 = WORLD_BOX
    names = {"nofriend": "我方攻击特效", "noenemy": "敌人本体", "nofoe": "敌方弹幕 / 预警", "noamb": "环境颗粒 / 光尘",
             "nogem": "经验结晶等掉落", "nonum": "伤害数字", "nomire": "溟痕", "noaura": "地面光环叠层", "noground": "地面纹理",
             "noflash": "敌人受击闪白"}
    res = []
    for ti, t in enumerate(TARGETS):
        f = frames()[ti * 2]
        full = _load(a.op, a.seed, "full", f)
        if full is None:
            continue
        F = full[y0:y1, x0:x1]
        H, S, V = _hsv(F)
        L = _luma(F)
        red = ((H >= 330) | (H < 20)) & (S > 0.35) & (V > 0.25)
        rows = []
        for ly in BUDGET_LAYERS[1:]:
            im = _load(a.op, a.seed, ly, f)
            if im is None:
                continue
            m = np.abs(im[y0:y1, x0:x1] - F).max(axis=2) > 0.06
            if m.sum() == 0:
                rows.append({"layer": ly, "name": names[ly], "area_pct": 0.0})
                continue
            hs = H[m & (S > 0.2)]
            hist = np.histogram(hs, bins=24, range=(0, 360))[0] if hs.size else np.zeros(24)
            dom = _hue_name(float(np.argmax(hist) * 15 + 7.5)) if hs.size > 20 else "灰（低饱和）"
            rows.append({"layer": ly, "name": names[ly], "area_pct": float(m.mean() * 100), "L_mean": float(L[m].mean()),
                         "L_p90": float(np.percentile(L[m], 90)), "L_p95": float(np.percentile(L[m], 95)), "sat_mean": float(S[m].mean()), "dominant": dom,
                         "red_pct_of_layer": float((red & m).sum() / m.sum() * 100), "share_of_red_px": float((red & m).sum() / max(1, red.sum()) * 100)})
        for i, r in enumerate(sorted([r for r in rows if "L_mean" in r], key=lambda r: -r["L_mean"])):
            r["L_rank"] = i + 1
        meta = json.load(open(os.path.join(SHOT, "%s%s_s%d_full" % (a.op, TAG, a.seed), "shot_%d.json" % f)))
        H2, S2, V2 = _hsv(full)
        red_all = ((H2 >= 330) | (H2 < 20)) & (S2 > 0.35) & (V2 > 0.25)
        res.append({"t": meta.get("t"), "frame": f, "red_px_pct_frame": float(red.mean() * 100), "red_px_pct_fullframe": float(red_all.mean() * 100), "leader_scr": meta.get("leader_scr"),
                    "enemies_on": meta.get("enemies_on"), "dcrowd": meta.get("dcrowd"), "fx_dim": meta.get("fx_dim"), "layers": rows})
        Image.fromarray((full * 255).astype(np.uint8)).save(os.path.join(a.out, "budget_%s_%d.png" % (a.op, t)))
        # 红色像素图：红 / 洋红像素原色、其余压灰，直观看「红从哪来」
        g = np.repeat(L[..., None], 3, axis=2) * 0.35
        g[red] = F[red]
        vis = (full * 255).astype(np.uint8).copy()
        vis[y0:y1, x0:x1] = (g * 255).astype(np.uint8)
        Image.fromarray(vis).save(os.path.join(a.out, "budget_red_%s_%d.png" % (a.op, t)))
    json.dump(res, open(os.path.join(a.out, "budget_%s.json" % a.op), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps(res, ensure_ascii=False, indent=1))


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
    s.add_argument("--targets", default="")
    s.add_argument("--bal", default="", help="逗号分隔的 段/键=值，逐个转成 --bal=（docs/246）")
    s.add_argument("--extra", default="", help="透传给游戏的额外参数（空格分隔），docs/247 开 / 关对照用")
    b = sp.add_parser("budget")
    b.add_argument("--op", default="logos")
    b.add_argument("--tag", default="_user")
    b.add_argument("--seed", type=int, default=11)
    b.add_argument("--targets", default="586")
    b.add_argument("--out", default=os.path.join(ROOT, "docs", "assets", "late_game_diag"))
    m = sp.add_parser("measure")
    m.add_argument("--ops", default="texas,exusiai,eyjafjalla,skalter")
    m.add_argument("--seed", type=int, default=11)
    m.add_argument("--out", default=os.path.join(ROOT, "docs", "assets", "late_game_diag"))
    m.add_argument("--tag", default="")
    a = p.parse_args()
    {"shoot": cmd_shoot, "measure": cmd_measure, "budget": cmd_budget}.get(a.cmd, lambda _: p.print_help())(a)


if __name__ == "__main__":
    main()
