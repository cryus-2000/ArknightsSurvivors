"""10-24 动作审计（docs/140）补的原生 1 倍帧条：在 make_op_1x.py 算好的同一缩放上，从原作 Spine 再出几条。

  · 星熊 op_hoshiguma_s1_guard_move：S1「战意」格挡定格的上半身（原生 Skill t=0）+ 跑步步态腿（run_trial move_attack 模式），
    8 帧与跑步条同相位播放（序列 sprites.skills.s1.run）。原来格挡窗口里移动只播单帧定格 = 原地滑行。
  · 塞雷娅 S3「钙质化」三条按原生 Skill_Begin / Skill_Loop / Skill_End 重出：原作起手把盾平放在身后地上、武器放在身前地上，
    收势第 4 帧把盾拿回手里。循环期间全程空手（10-24 用户定）：站着播原生 Loop，移动播 op_saria_skill_s3_run（Loop 上半身 + 跑步腿），
    普攻换成空手拳击 op_saria_skill_s3_attack / 跑动版 op_saria_move_skill_s3_attack（逐帧姿势见 PUNCH）。
    旧帧条第 2 帧起盾凭空消失（用户 10-24「三技能丢盾牌显得很奇怪」）。帧数 / 逐帧时长 / 出手帧不变，只换画面。

用法：python -X utf8 tools/op_1x/native_extra.py [--only hoshiguma,saria]
需要：先跑过 make_op_1x.py（主仓库 build/op_1x/<op>/_cfg 下有 attack_move.json / idle_stand.json，带算好的 scaleMul）。
输出运行时 <tex>@1x.png（asset_paths.out_png）；中间帧在 build/op_1x/<op>/<name>/。
"""
import argparse, json, os, shutil, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_op_1x as M
import asset_paths


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
    img.save(asset_paths.out_png("op_hoshiguma_s1_guard_move@1x"))
    return ["op_hoshiguma_s1_guard_move"]


# 塞雷娅 S3 空手冲拳（10-24 用户「技能期间改成跑动拳击」…「拳击就改成冲拳」）：原生 Skill_Loop t=0 的空手站姿上逐帧转手臂。
# 前手（左臂，面朝右时在前）直线打出、后手（右臂）收到腰侧，胸口顺势前倾；手臂大半被白毛领挡住，打出的几帧把前臂提到毛领上层画（top）。
# 不拉长、不放大（用户：放大显得奇怪）；蓄力只收到腰前，不抬过胸（用户：举过头奇怪）。
# 帧数 / 出手帧与普攻条相同（8 帧，第 4 帧出手），时序由 json 抄普攻的 attack_timing。
# 每帧：(前手上臂, 前手前臂, 后手上臂, 胸, 前手提到上层) ；角度为转角增量（度）
# 直拳轨迹（10-24 用户「现在像是捶，不像是直拳」）：手腕沿肩高水平线直线推出，按两节 IK 反算（肩 (96, 128.4)、上臂 4.35 px、前臂 3.83 px，
# 肘在下；转角换算见 docs/140 §7.2）。用户「第一帧应该是手变成拳击的准备工作，然后才是冲拳」：先抬手成拳击架势
# （前拳在下巴前 (100.6, 126.2)，画在毛领上层；后手转到胸前、留在身后层，免得大白袖子盖住脸），再收拳、直拳打出、回架势、放下。
# 每帧：(前手上臂, 前手前臂, 后手上臂, 后手前臂, 胸, 前手提到上层)
PUNCH = [(-28, 52, -60, -20, 0, False), (-10, 48, -120, -40, 0, True), (-20, 60, -120, -40, 2, True),
         (0, -30, -120, -40, -5, True), (-5, -20, -120, -40, -4, True), (-15, 35, -120, -40, -2, True),
         (-10, 48, -120, -40, 0, True), (-30, 52, -60, -20, 0, False)]
GUARD = (-45, 55)   # 前手放到腰前的转角（上臂, 前臂）
SARIA_HIDE = ["F_Shield", "F_Weapon", "F_Pinhead"]   # 盾 / 武器已放下
SARIA_FRONT_ARM = ["F_L_Arm", "F_L_Shoulder", "F_L_Wrap", "F_L_Ring", "F_L_Hand_C", "F_L_Hand_B", "F_L_Hand", "F_L_Finger", "F_L_Finger_2"]


def punch_poses():
    return [{"anim": "Skill_Loop", "t": 0, "rot": {"F_L_Arm": la, "F_L_Shoulder": lf, "F_R_Arm": ra, "F_R_Shoulder": rf, "F_Chest": ch},
             "top": SARIA_FRONT_ARM if top else [], "hide": SARIA_HIDE} for la, lf, ra, rf, ch, top in PUNCH]


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
    # 循环 / 空手跑也把前手放到腰前（同冲拳起势 GUARD），出拳前后不跳
    guard = [{"anim": "Skill_Loop", "t": t, "rot": {"F_L_Arm": GUARD[0], "F_L_Shoulder": GUARD[1]}, "hide": SARIA_HIDE} for t in loop]
    dl, _ = render_poses("saria", "attack_move.json", "s3_loop_raw", guard)
    de, _ = render("saria", "idle_stand.json", "s3_end_raw", "Skill_End", end)
    dr, _ = render_poses("saria", "attack_move.json", "s3_run", guard, "move_attack")
    poses = punch_poses()
    dp, _ = render_poses("saria", "attack_move.json", "s3_punch", poses)
    dm, _ = render_poses("saria", "attack_move.json", "s3_punch_move", poses, "move_attack")
    foot = [31.75, 59.57669522183914]
    out = {"op_saria_skill": (db, foot), "op_saria_skill_s3_loop": (dl, foot), "op_saria_skill_s3_end": (de, foot),
           "op_saria_skill_s3_run": (dr, [32, 60]), "op_saria_skill_s3_attack": (dp, foot), "op_saria_move_skill_s3_attack": (dm, foot)}
    for tex, (d, ft) in out.items():
        M.compose(d, 8, 64, 64, ft, anc).save(asset_paths.out_png(tex + "@1x"))
    return list(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="hoshiguma,saria")
    a = ap.parse_args()
    for op in a.only.split(","):
        print(op, globals()[op]())
    M.write_index()


if __name__ == "__main__":
    main()
