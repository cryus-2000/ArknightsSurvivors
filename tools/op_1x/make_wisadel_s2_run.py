"""维什戴尔 S2 跑动帧条（10-24 用户「二技能的跑动动作得加上」）：S2 期间移动原来停在 s2_idle 上滑步。
做法同普通跑步 op_wisadel_run（tools/spine_run_trial cfg/wisadel.json 的步态）：底稿换成原作 Spine 的 Skill_2_Idle /
Skill_2_Overload_Idle 首帧（S2 架炮姿态与展开的浮游武器），逐部件 1 倍像素化；缩放与 make_op_1x 同口径（原待机首帧身高对齐），
帧格 / 脚底沿用 s2_idle（96 画布、foot 48.25, 75.86）。参数见下面 EXTRA。
用法：python -X utf8 tools/op_1x/make_wisadel_s2_run.py [--out-dir 目录]（缺省直接写运行时 <tex>@1x.png（asset_paths.out_png））
"""
import argparse, json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_op_1x as M
import asset_paths

OP = "wisadel"
SLOTS = {   # 新帧条 → (原生动画, 帧格 / 脚底参照槽)
    "op_wisadel_s2_run": ("Skill_2_Idle", "s2_idle"),
    "op_wisadel_s2_over_run": ("Skill_2_Overload_Idle", "s2_over_idle"),
}
N = 8
# 第二版（用户 10-24「S2 跑动我没看到腿」）：第一版用 move_attack（上半身照抄 S2 待机、只换腿），步幅小，
# 四件浮游武器又横在膝盖高度，腿几乎看不出。改成普通跑步同一套（前倾、下蹲、摆臂收小）、底稿换成 S2 待机首帧，
# 步幅 ×1.6、离地抬高，四件武器随身体上抬 5 像素 / 后收 2 像素，腿露在武器下面
EXTRA = {"mode": "run", "sample": None, "params": {"armAmp": 6, "holdAmp": 2, "stride": 1.6},
         "gaitLiftPx": [None, None, None, None, 14, 16, 7, 3],
         "carry": {k: [-2, 5, 0] for k in ("C_Weapon_A_01", "C_Weapon_B_01", "C_Weapon_C_01", "C_Weapon_D_01")}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--cfg", default="", help="JSON：追加到 run_trial 配置（试 maCarry / hide / params 用）")
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
    im = Image.open(asset_paths.runtime_png(idle["tex"] + "@2x")).convert("RGBA")
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
        ref_im = Image.open(asset_paths.runtime_png(sp["tex"] + "@1x"))
        fw, fh = ref_im.width // int(sp["frames"]), ref_im.height
        c = dict(base, scaleMul=scale, base={"anim": anim, "t": 0})
        c.update(EXTRA)
        c["params"] = dict(base.get("params", {}), **EXTRA["params"])
        if a.cfg:
            extra = json.loads(a.cfg)
            if "params" in extra:
                extra["params"] = dict(c.get("params", {}), **extra["params"])
            c.update(extra)
        d = os.path.join(M.OUT, OP, tex)
        M.run_node(M.write_cfg(OP, tex, c), d)
        img = M.compose(d, N, fw, fh, sp["foot"], M.anchor_of(c))
        dst = os.path.join(a.out_dir, tex + ".png") if a.out_dir else asset_paths.out_png(tex + "@1x")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        img.save(dst)
        print(tex, img.size, "scale %.4f" % scale, "->", dst)
    if not a.out_dir:
        M.write_index()


if __name__ == "__main__":
    main()
