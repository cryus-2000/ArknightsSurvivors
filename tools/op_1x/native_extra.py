"""10-24 动作审计（docs/140）补的原生 1 倍帧条：在 make_op_1x.py 算好的同一缩放上，从原作 Spine 再出几条。

  · 星熊 op_hoshiguma_s1_guard_move：S1「战意」格挡定格的上半身（原生 Skill t=0）+ 跑步步态腿（run_trial move_attack 模式），
    8 帧与跑步条同相位播放（序列 sprites.skills.s1.run）。原来格挡窗口里移动只播单帧定格 = 原地滑行。
  · 塞雷娅 S3「钙质化」三条按原生 Skill_Begin / Skill_Loop / Skill_End 重出：原作起手把盾平放在身后地上、武器放在身前地上，
    循环期间留在地上（原生 Loop 不改这两个槽，运行时保留 Begin 末帧的状态），收势第 4 帧把盾拿回手里；
    循环期间移动改播 op_saria_skill_s3_run（原生 Loop 空手上半身 + 跑步腿，序列 sprites.skills.s3.run），不再原地滑行。
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


def saria():
    begin = [round(0.69 * i / 7, 4) for i in range(8)]
    loop = [round(0.4 * i / 8, 4) for i in range(8)]
    end = [round(0.49 * i / 7, 4) for i in range(8)]
    db, anc = render("saria", "idle_stand.json", "s3_begin", "Skill_Begin", begin)
    dl, _ = render("saria", "idle_stand.json", "s3_loop_raw", "Skill_Loop", loop)
    de, _ = render("saria", "idle_stand.json", "s3_end_raw", "Skill_End", end)
    # 地上的盾与武器：起手末帧里、循环首帧本体以外的像素（只取脚边几行，免得把姿势差带进来）
    b7 = Image.open(os.path.join(db, "f07.png")).convert("RGBA")
    l0 = Image.open(os.path.join(dl, "f00.png")).convert("RGBA")
    ground = Image.new("RGBA", b7.size, (0, 0, 0, 0))
    gy = int(anc[1]) - 18
    for y in range(gy, b7.height):
        for x in range(b7.width):
            p = b7.getpixel((x, y))
            if p[3] and not l0.getpixel((x, y))[3]:
                ground.putpixel((x, y), p)

    def with_ground(src, name, keep):
        d = os.path.join(M.OUT, "saria", name)
        os.makedirs(d, exist_ok=True)
        for i in range(8):
            f = Image.open(os.path.join(src, f"f{i:02d}.png")).convert("RGBA")
            if i in keep:
                g = ground.copy()
                g.alpha_composite(f)   # 盾 / 武器在身后：本体压在上面
                f = g
            f.save(os.path.join(d, f"f{i:02d}.png"))
        return d

    dl2 = with_ground(dl, "s3_loop", range(8))
    de2 = with_ground(de, "s3_end", range(3))   # 收势第 4 帧（零基 3）盾回到手上
    # 循环期间移动：原生 Loop 空手上半身 + 跑步腿（盾 / 武器留在原地画不出来，跑起来不带；停下回到脚边）
    dr, _ = render("saria", "attack_move.json", "s3_run", "Skill_Loop", loop, "move_attack")
    foot = [31.75, 59.57669522183914]
    out = {"op_saria_skill": db, "op_saria_skill_s3_loop": dl2, "op_saria_skill_s3_end": de2}
    M.compose(dr, 8, 64, 64, [32, 60], anc).save(os.path.join(M.INC, "op_saria_skill_s3_run@1x.png"))
    for tex, d in out.items():
        M.compose(d, 8, 64, 64, foot, anc).save(os.path.join(M.INC, tex + "@1x.png"))
    return list(out) + ["op_saria_skill_s3_run"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="hoshiguma,saria")
    a = ap.parse_args()
    for op in a.only.split(","):
        print(op, globals()[op]())


if __name__ == "__main__":
    main()
