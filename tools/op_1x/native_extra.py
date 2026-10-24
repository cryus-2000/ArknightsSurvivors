"""10-24 动作审计（docs/140）补的原生 1 倍帧条：在 make_op_1x.py 算好的同一缩放上，从原作 Spine 再出几条。

  · 星熊 op_hoshiguma_s1_guard_move：S1「战意」格挡定格的上半身（原生 Skill t=0）+ 跑步步态腿（run_trial move_attack 模式），
    8 帧与跑步条同相位播放（序列 sprites.skills.s1.run）。原来格挡窗口里移动只播单帧定格 = 原地滑行。
  · 塞雷娅 S3「钙质化」三条按原生 Skill_Begin / Skill_Loop / Skill_End 重出：原作起手把盾平放在身后地上、武器放在身前地上，
    收势第 4 帧把盾拿回手里。循环期间全程空手（10-24 用户定）：站着播原生 Loop，移动播 op_saria_skill_s3_run（Loop 上半身 + 跑步腿），
    普攻换成空手拳击 op_saria_skill_s3_attack / 跑动版 op_saria_move_skill_s3_attack（逐帧姿势见 PUNCH）。
    旧帧条第 2 帧起盾凭空消失（用户 10-24「三技能丢盾牌显得很奇怪」）。帧数 / 逐帧时长 / 出手帧不变，只换画面。

用法：python -X utf8 tools/op_1x/native_extra.py [--only hoshiguma,saria]
需要：先跑过 make_op_1x.py（主仓库 build/op_1x/<op>/_cfg 下有 attack_move.json / idle_stand.json，带算好的 scaleMul）。
输出 art/incoming/<tex>@1x.png；中间帧在 build/op_1x/<op>/<name>/。
"""
import argparse, json, os, shutil, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_op_1x as M


def render(op, base_cfg, name, anim, times, mode=None):
    c = json.load(open(os.path.join(M.OUT, op, "_cfg", base_cfg), encoding="utf-8"))
    c["sample"] = {"anim": anim, "times": times}
    if mode:
        c["mode"] = mode
    else:
        c.pop("mode", None)
    d = os.path.join(M.OUT, op, name)
    M.run_node(M.write_cfg(op, name, c), d)
    return d, M.anchor_of(c)


def hoshiguma():
    d, anc = render("hoshiguma", "attack_move.json", "s1_guard_move", "Skill", [0.0] * 8, "move_attack")
    img = M.compose(d, 8, 64, 64, [32, 60], anc)
    img.save(os.path.join(M.INC, "op_hoshiguma_s1_guard_move@1x.png"))
    return ["op_hoshiguma_s1_guard_move"]


# 塞雷娅 S3 空手拳击（10-24 用户「技能期间改成跑动拳击」）：原生 Skill_Loop t=0 的空手站姿上逐帧转左臂（面朝右时在前的那只）。
# 帧数 / 出手帧与普攻条相同（8 帧，第 4 帧出手），时序由 json 抄普攻的 attack_timing。[上臂, 前臂, 胸] 转角增量（度，负 = 向前下）
PUNCH = [(0, 0, 0), (20, 45, 4), (28, 70, 6), (-42, -18, -8), (-40, -15, -6), (-20, 15, -2), (0, 30, 0), (5, 15, 0)]
SARIA_HIDE = ["F_Shield", "F_Weapon", "F_Pinhead"]   # 盾 / 武器已放下


def render_poses(op, base_cfg, name, poses, mode=None):
    c = json.load(open(os.path.join(M.OUT, op, "_cfg", base_cfg), encoding="utf-8"))
    c.pop("sample", None)
    c["poses"] = poses
    if mode:
        c["mode"] = mode
    else:
        c.pop("mode", None)
    d = os.path.join(M.OUT, op, name)
    M.run_node(M.write_cfg(op, name, c), d)
    return d, M.anchor_of(c)


def saria():
    begin = [round(0.69 * i / 7, 4) for i in range(8)]
    loop = [round(0.4 * i / 8, 4) for i in range(8)]
    end = [round(0.49 * i / 7, 4) for i in range(8)]
    # 起手按原作放下盾和武器；循环 / 收势 / 拳击都空手（地上的盾不画：区域跟着队长走，停走之间盾会一闪一闪，用户 10-24 定全程空手打）
    db, anc = render("saria", "idle_stand.json", "s3_begin", "Skill_Begin", begin)
    dl, _ = render("saria", "idle_stand.json", "s3_loop_raw", "Skill_Loop", loop)
    de, _ = render("saria", "idle_stand.json", "s3_end_raw", "Skill_End", end)
    dr, _ = render("saria", "attack_move.json", "s3_run", "Skill_Loop", loop, "move_attack")
    poses = [{"anim": "Skill_Loop", "t": 0, "rot": {"F_L_Arm": a, "F_L_Shoulder": f, "F_Chest": c, "F_R_Arm": 12 if a < 0 else 0}, "hide": SARIA_HIDE} for a, f, c in PUNCH]
    dp, _ = render_poses("saria", "attack_move.json", "s3_punch", poses)
    dm, _ = render_poses("saria", "attack_move.json", "s3_punch_move", poses, "move_attack")
    foot = [31.75, 59.57669522183914]
    out = {"op_saria_skill": (db, foot), "op_saria_skill_s3_loop": (dl, foot), "op_saria_skill_s3_end": (de, foot),
           "op_saria_skill_s3_run": (dr, [32, 60]), "op_saria_skill_s3_attack": (dp, foot), "op_saria_move_skill_s3_attack": (dm, foot)}
    for tex, (d, ft) in out.items():
        M.compose(d, 8, 64, 64, ft, anc).save(os.path.join(M.INC, tex + "@1x.png"))
    return list(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="hoshiguma,saria")
    a = ap.parse_args()
    for op in a.only.split(","):
        print(op, globals()[op]())


if __name__ == "__main__":
    main()
