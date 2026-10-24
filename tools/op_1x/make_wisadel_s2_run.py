"""维什戴尔 S2 跑动帧条（10-24 用户「二技能的跑动动作得加上」）：S2 期间移动原来停在 s2_idle 上滑步。
做法同 make_op_1x 的 move_attack（docs/128 §3）：上半身按原作 Spine 的 Skill_2_Idle / Skill_2_Overload_Idle 采样，
腿换成跑步步态（run_trial.js mode=move_attack），逐部件 1 倍像素化；缩放与 make_op_1x 同口径（原待机首帧身高对齐），
帧格 / 脚底沿用 s2_idle（96 画布、foot 48.25, 75.86）。上半身采样按真实时间走 8 × 0.075 秒（= 跑步一圈 0.6 秒），浮游武器不会被快放抖动。
用法：python -X utf8 tools/op_1x/make_wisadel_s2_run.py [--out-dir 目录]（缺省直接写 art/incoming/<tex>@1x.png）
"""
import argparse, json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_op_1x as M

OP = "wisadel"
SLOTS = {   # 新帧条 → (原生动画, 帧格 / 脚底参照槽)
    "op_wisadel_s2_run": ("Skill_2_Idle", "s2_idle"),
    "op_wisadel_s2_over_run": ("Skill_2_Overload_Idle", "s2_over_idle"),
}
N = 8
STEP = 0.075


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    jd = json.load(open(os.path.join(M.CHARS, OP + ".json"), encoding="utf-8"))
    sprites = jd["sprites"]
    base = json.load(open(os.path.join(M.CFG, OP + ".json"), encoding="utf-8"))
    base["noMouth"] = True
    base["pixelEyes"] = True
    for k in ("keys", "poses", "sample"):
        base.pop(k, None)
    base["canvas"] = max(192, base.get("canvas", 128))
    sm0 = base.get("scaleMul") or 1
    # 缩放：同 make_op_1x.build_op（原待机首帧身高 1x ÷ Spine 1 倍待机身高）
    idle = M.spec(sprites, "idle")
    im = Image.open(os.path.join(M.INC, idle["tex"] + "@2x.png")).convert("RGBA")
    nfr = int(idle.get("frames", 8))
    h_old = M.bbox_h(im.crop((0, 0, im.width // nfr, im.height))) / 2
    mdir = os.path.join(M.OUT, OP, "_measure")
    M.run_node(M.write_cfg(OP, "_measure", dict(base, scaleMul=sm0 * 0.5)), mdir)
    h_new = M.bbox_h(Image.open(os.path.join(mdir, "idle_t0.png")))
    scale = sm0 * 0.5 * (h_old / h_new if h_new else 1.0)
    for tex, (anim, ref) in SLOTS.items():
        if a.only and tex not in a.only.split(","):
            continue
        sp = M.spec(sprites, ref)
        ref_im = Image.open(os.path.join(M.INC, sp["tex"] + "@1x.png"))
        fw, fh = ref_im.width // int(sp["frames"]), ref_im.height
        c = dict(base, scaleMul=scale, mode="move_attack", sample={"anim": anim, "times": [round(i * STEP, 6) for i in range(N)]})
        d = os.path.join(M.OUT, OP, tex)
        M.run_node(M.write_cfg(OP, tex, c), d)
        img = M.compose(d, N, fw, fh, sp["foot"], M.anchor_of(c))
        dst = os.path.join(a.out_dir or M.INC, tex + ("@1x.png" if not a.out_dir else ".png"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        img.save(dst)
        print(tex, img.size, "scale %.4f" % scale, "->", dst)


if __name__ == "__main__":
    main()
