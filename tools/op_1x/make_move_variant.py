"""通用「跑动版」动作帧条（11-08，拉普兰德 S2 掷刃试点；做法同维什戴尔 S2 跑动开炮 make_wisadel_s2_run.py MOVE_SLOTS）：
引擎 _move_swap 在出手动作期间移动、且有 sprites.move_<槽> 帧条（帧数相同）时，只换贴图——上半身同原条逐帧、腿是跑步步态。
本脚本从原作 Spine 出这条 move_ 帧条：
  1) --match：把原生动画每 STEP 秒渲一帧，按原条帧格 / 脚底贴好，与原条 @1x 逐帧比上半身（脚底以上 72%），每帧取最近的时间；
  2) 用这组时间以 run_trial move_attack 模式渲（上半身 = 原生动作该时刻的骨架，腿 = 跑步步态），帧格 / 脚底同原条。
缩放与 make_op_1x.build_op 同口径（原待机首帧身高对齐）；写完跑 eye_fix（瞳色保护）与 asset_index。
用法：python -X utf8 tools/op_1x/make_move_variant.py --op lappland --slot throw --anim Attack --match
      python -X utf8 tools/op_1x/make_move_variant.py --op lappland --slot throw --anim Attack --times 0,0.1,...（8 个）[--out-dir 目录]
步幅等：--stride（缺省 1.6）、--lift（摆动腿离地 @2x 像素，相位 4–7，缺省 14,16,7,3），同 S2 / S3 跑动开炮
"""
import argparse, json, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_op_1x as M
import asset_paths

STEP = 0.05


def base_cfg(op, sprites):
    base = json.load(open(os.path.join(M.CFG, op + ".json"), encoding="utf-8"))
    base["noMouth"] = True
    base["pixelEyes"] = op in {"wisadel", "specter_unchained", "skalter"}
    for k in ("keys", "poses", "sample"):
        base.pop(k, None)
    base["canvas"] = max(192, base.get("canvas", 128))
    sm0 = base.get("scaleMul") or 1
    idle = M.spec(sprites, "idle")
    im = Image.open(asset_paths.runtime_png(idle["tex"] + "@2x")).convert("RGBA")
    nfr = int(idle.get("frames", 8))
    h_old = M.bbox_h(im.crop((0, 0, im.width // nfr, im.height))) / 2
    mdir = os.path.join(M.OUT, op, "_measure")
    M.run_node(M.write_cfg(op, "_measure", dict(base, scaleMul=sm0 * 0.5)), mdir)
    h_new = M.bbox_h(Image.open(os.path.join(mdir, "idle_t0.png")))
    return base, sm0 * 0.5 * (h_old / h_new if h_new else 1.0)


def slot_ref(sprites, slot):
    sp = M.spec(sprites, slot)
    rim = Image.open(asset_paths.runtime_png(sp["tex"] + "@1x")).convert("RGBA")
    n = int(sp["frames"])
    return sp, rim, n, rim.width // n, rim.height


def match(op, sprites, base, scale, slot, anim, dur):
    sp, rim, n, fw, fh = slot_ref(sprites, slot)
    refs = [np.asarray(rim.crop((i * fw, 0, (i + 1) * fw, fh))).astype(float) for i in range(n)]
    times = [round(STEP * i, 3) for i in range(int(dur / STEP) + 1)]
    cand = []
    for k in range(0, len(times), n):
        chunk = times[k:k + n]
        ts = (chunk + [chunk[-1]] * n)[:n]
        c = dict(base, scaleMul=scale, sample={"anim": anim, "times": ts})
        name = "mvp_%s_%02d" % (slot, k)
        d = os.path.join(M.OUT, op, name)
        M.run_node(M.write_cfg(op, name, c), d)
        img = M.compose(d, n, fw, fh, sp["foot"], M.anchor_of(c), mirror=bool(sp.get("mirror")))
        for j, t in enumerate(chunk):
            cand.append((t, np.asarray(img.crop((j * fw, 0, (j + 1) * fw, fh)).convert("RGBA")).astype(float)))
    cut = int(float(sp["foot"][1]) * 0.72)
    best = []
    for i, r in enumerate(refs):
        sc = sorted((float(np.abs(a[:cut] - r[:cut]).mean()), t) for t, a in cand)
        best.append(sc[0][1])
        print("frame %d best %s" % (i, ", ".join("%.2f@%.2f" % x for x in sc[:3])))
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", required=True)
    ap.add_argument("--slot", required=True, help="原条槽名（sprites.<槽>），产出 op_<op>_move_<槽>")
    ap.add_argument("--anim", required=True, help="原作 Spine 动画名")
    ap.add_argument("--match", action="store_true")
    ap.add_argument("--times", default="")
    ap.add_argument("--stride", type=float, default=1.6)
    ap.add_argument("--lift", default="14,16,7,3")
    ap.add_argument("--out-dir", default="")
    a = ap.parse_args()
    sprites = json.load(open(os.path.join(M.CHARS, a.op + ".json"), encoding="utf-8"))["sprites"]
    base, scale = base_cfg(a.op, sprites)
    if a.match:
        anims = M.info(a.op)
        print("TIMES", ",".join("%g" % t for t in match(a.op, sprites, base, scale, a.slot, a.anim, float(anims[a.anim]["dur"]))))
        return
    sp, rim, n, fw, fh = slot_ref(sprites, a.slot)
    times = [float(x) for x in a.times.split(",")]
    assert len(times) == n, "times 要 %d 个" % n
    lift = [None] * 4 + [int(x) for x in a.lift.split(",")]
    c = dict(base, scaleMul=scale, mode="move_attack", sample={"anim": a.anim, "times": times},
             gaitLiftPx=lift, params=dict(base.get("params", {}), stride=a.stride))
    tex = "op_%s_move_%s" % (a.op, a.slot)
    d = os.path.join(M.OUT, a.op, tex)
    M.run_node(M.write_cfg(a.op, tex, c), d)
    img = M.compose(d, n, fw, fh, sp["foot"], M.anchor_of(c), mirror=bool(sp.get("mirror")))
    dst = os.path.join(a.out_dir, tex + ".png") if a.out_dir else asset_paths.out_png(tex + "@1x")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save(dst)
    print(tex, img.size, "scale %.4f" % scale, "->", dst)
    if not a.out_dir:
        import eye_fix
        eye_fix.fix_op(a.op)
        M.write_index()


if __name__ == "__main__":
    main()
