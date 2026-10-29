"""乌尔比安 S2 锚击的跑动版（10-29 用户「三技能期间几乎是平移」）：原作 Spine Skill_2_Loop 上半身 + 跑步步态腿（run_trial move_attack 模式），
时刻同 Codex S2Attack 八帧（cw_ulpianus_skill_pixel_cleanup_1020/job.json）。S2 永久生效后普攻换 attack_s2，原来没有跑动版，
移动中挥锚（含 S3 抡锚三连）整条是站姿 = 原地滑行。画布 / 脚底与 attack_s2 相同（1 倍 128 画布，foot [64, 90]），
引擎 character._move_swap 按 move_<槽> 自动换贴图。

用法：python -X utf8 tools/op_1x/ulpianus_move_s2.py
需要：先跑过 make_op_1x.py（主仓库 build/op_1x/ulpianus/_cfg/attack_move.json 带算好的 scaleMul）。
输出运行时 op_ulpianus_move_attack_s2@1x.png（asset_paths.out_png）；中间帧在 build/op_1x/ulpianus/s2_attack_move/。
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import native_extra as N
import make_op_1x as M
import asset_paths

S2_TIMES = [0, 0.3, 0.6, 0.699999988, 0.72, 0.79, 1.7, 2.5]


def main():
    d, anc = N.render("ulpianus", "attack_move.json", "s2_attack_move", "Skill_2_Loop", S2_TIMES, "move_attack")
    img = M.compose(d, 8, 128, 128, [64, 90], anc)
    p = asset_paths.out_png("op_ulpianus_move_attack_s2@1x")
    img.save(p)
    M.write_index()
    print(p, img.size)


if __name__ == "__main__":
    main()
