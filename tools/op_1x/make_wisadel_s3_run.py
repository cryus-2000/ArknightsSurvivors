"""维什戴尔 S3 跑动帧条（11-03 用户「三技能也加」跑动）：S3 期间移动原来停在蹲射循环 skill_s3_loop 上滑步。
做法同 S2 跑动（make_wisadel_s2_run.py，10-24）：底稿换成原作 Spine 的 S3 姿态，逐部件 1 倍像素化，缩放同 make_op_1x 口径。
  · op_wisadel_skill_s3_run：原作 Skill_3_Idle 首帧（架炮瞄准）上半身 + 跑步步态腿，8 帧与跑步条共用相位（序列 sprites.skills.s3.run）；
    帧格 / 脚底沿用 skill_s3_loop（64 画布、foot 32.25, 59.86）。
  · op_wisadel_move_skill_s3_attack：跑动版开炮（引擎 _move_swap：S3 期间移动时普攻变体 skill_s3_attack 换成 move_ 版），
    原作 Skill_3_Loop 开炮段逐帧姿势（--times，缺省 ATK_TIMES）+ 跑步腿（run_trial move_attack 模式）；
    帧数 / 出手帧 / 逐帧时长同 skill_s3_attack（8 帧、fire 3），帧格 / 脚底同它（96 画布、foot 48.25, 75.86）。
用法：python -X utf8 tools/op_1x/make_wisadel_s3_run.py [--only 名] [--out-dir 目录] [--times t0,t1,...] [--probe]
  --probe：把 Skill_3_Loop 每 0.125 秒一帧渲出来（找开炮段时间用），不写运行时贴图
"""
import argparse, json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_op_1x as M
import asset_paths

OP = "wisadel"
N = 8
# 开炮段：Skill_3_Loop 里炮口抬起后坐、再压回的那一下（--probe 量出来的时间）；8 帧对齐 skill_s3_attack 的 fire 3
ATK_TIMES = [0.2, 0.32, 0.45, 0.625, 0.75, 1.0, 1.25, 1.4]
# 第二版（11-03 整合会话：移动时仍看着像蹲射）：架炮上半身 + 小步幅在 1 倍像素下和蹲射分不出。照 S2 跑动第二版：
# 步幅 ×1.8、离地抬高，四件浮游武器随身体上抬 6 像素 / 后收 2 像素，腿露在炮下面；跑动开炮同样加大步幅
RUN_EXTRA = {"mode": "run", "sample": None, "params": {"armAmp": 2, "holdAmp": 1, "stride": 1.8},
             "gaitLiftPx": [None, None, None, None, 16, 18, 8, 4],
             "carry": {k: [-2, 6, 0] for k in ("C_Weapon_A_01", "C_Weapon_B_01", "C_Weapon_C_01", "C_Weapon_D_01")}}
MOVE_ATK_EXTRA = {"params": {"stride": 1.6}, "gaitLiftPx": [None, None, None, None, 14, 16, 7, 3]}


def base_cfg(sprites):
    base = json.load(open(os.path.join(M.CFG, OP + ".json"), encoding="utf-8"))
    base["noMouth"] = True
    base["pixelEyes"] = True
    for k in ("keys", "poses", "sample"):
        base.pop(k, None)
    base["canvas"] = max(256, base.get("canvas", 128))   # 架炮姿态的大炮比 S2 更长
    sm0 = base.get("scaleMul") or 1
    idle = M.spec(sprites, "idle")
    im = Image.open(asset_paths.runtime_png(idle["tex"] + "@2x")).convert("RGBA")
    nfr = int(idle.get("frames", 8))
    h_old = M.bbox_h(im.crop((0, 0, im.width // nfr, im.height))) / 2
    mdir = os.path.join(M.OUT, OP, "_measure")
    M.run_node(M.write_cfg(OP, "_measure", dict(base, scaleMul=sm0 * 0.5)), mdir)
    h_new = M.bbox_h(Image.open(os.path.join(mdir, "idle_t0.png")))
    return base, sm0 * 0.5 * (h_old / h_new if h_new else 1.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--times", default="")
    ap.add_argument("--probe", action="store_true")
    a = ap.parse_args()
    sprites = json.load(open(os.path.join(M.CHARS, OP + ".json"), encoding="utf-8"))["sprites"]
    base, scale = base_cfg(sprites)
    if a.probe:
        times = [round(0.125 * i, 3) for i in range(40)]
        for k in range(0, 40, 8):
            c = dict(base, scaleMul=scale, sample={"anim": "Skill_3_Loop", "times": times[k:k + 8]})
            d = os.path.join(M.OUT, OP, "s3_probe_%02d" % k)
            M.run_node(M.write_cfg(OP, "s3_probe_%02d" % k, c), d)
            print("probe", times[k:k + 8], "->", d)
        return
    atk_t = [float(x) for x in a.times.split(",")] if a.times else ATK_TIMES
    jobs = {
        "op_wisadel_skill_s3_run": ("skill_s3_loop", dict(base, scaleMul=scale, base={"anim": "Skill_3_Idle", "t": 0}, **{k: v for k, v in RUN_EXTRA.items() if k != "params"},
                                                          params=dict(base.get("params", {}), **RUN_EXTRA["params"]))),
        "op_wisadel_move_skill_s3_attack": ("skill_s3_attack", dict(base, scaleMul=scale, mode="move_attack", sample={"anim": "Skill_3_Loop", "times": atk_t},
                                                                    gaitLiftPx=MOVE_ATK_EXTRA["gaitLiftPx"], params=dict(base.get("params", {}), **MOVE_ATK_EXTRA["params"]))),
    }
    for tex, (ref, c) in jobs.items():
        if a.only and tex not in a.only.split(","):
            continue
        sp = M.spec(sprites, ref)
        ref_im = Image.open(asset_paths.runtime_png(sp["tex"] + "@1x"))
        fw, fh = ref_im.width // int(sp["frames"]), ref_im.height
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
