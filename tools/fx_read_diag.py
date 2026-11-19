# -*- coding: utf-8 -*-
"""后期满队画面可读性诊断（docs/398，B站玩家 11-19「视觉效果太多容易看花眼」）。

在 tools/late_clutter.py 的分层量测上改口径：四人编队（--slot4）、全员满成长（--prog=20）、高画质、伤害数字开、
后期满屏 8:40 / 9:10 / 9:40 与最终 Boss 10:20 / 10:40 / 11:00 各连拍 3 张（本作 10:00 出最终 Boss，没有 15 分钟以后）。
三套阵容：A 三辅助（能天使 + 安洁莉娜 / 铃兰 / 浊心斯卡蒂）、B 重法术（逻各斯 + 维什戴尔 / 艾雅法拉 / 斯卡蒂）、
C 近战 + 召唤（德克萨斯 + 乌尔比安 / 歌蕾蒂娅 / 凯尔希）。

用法（工作树根目录）：
  python tools/fx_read_diag.py capture <标签> [--squads=A,B,C] [--dbg=a,b] [--more=--bal=x=y;...] [--par=2]
  python tools/fx_read_diag.py layers <前缀> [--squads=..] [--par=2]    # full + 各分层
  python tools/fx_read_diag.py share <前缀> [--squads=..]               # 分层占屏 / 亮度表（markdown）
Godot 只经 godot_runner 启动（副屏 / 屏幕外、静音、全机上限）。
"""
import os, sys, json
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import late_clutter as lc

lc.SQUADS = {"A": ["exusiai", "angelina", "suzuran", "skalter"],
             "B": ["logos", "wisadel", "eyjafjalla", "skadi"],
             "C": ["texas", "ulpianus", "gladiia", "kaltsit"]}
lc.SEED = 11
SPF = 0.0659
_T = {"late1": 520, "late2": 550, "late3": 580, "boss1": 645, "boss2": 652, "boss3": 659}
lc.SCENES = {k: [int(round(t / SPF)) + d for d in ((0, 15, 30) if k.startswith("late") else (0, 20, 40))] for k, t in _T.items()}
lc.MAXT = 700
lc.OUT = os.path.join(lc._gr.common_root(lc.ROOT), "build", "fx_read")
lc.SHOT = os.path.join(lc.OUT, "shots")
LAYERS = ["nofriend", "nolead", "nospark", "nonum", "noenemy", "nofoe", "nowarn", "nogem", "nomire"]
NAME = {"nofriend": "我方特效合计", "nolead": "队长特效", "mates": "队友特效（合计 − 队长）", "nospark": "命中 / 击杀火花",
        "nonum": "伤害数字", "noenemy": "敌人本体", "nofoe": "敌方弹幕 + 预警 + 敌方特效", "nowarn": "地面预警圈",
        "nogem": "掉落物", "nomire": "地面残迹（溟痕）"}

_orig_run_args = lc.run_args


def run_args(sq, extra, shots=True):
    a = _orig_run_args(sq, ["--prog=20", "--quality=high"] + list(extra), shots)
    i = next(k for k, x in enumerate(a) if x.startswith("--squad="))
    return a[:i] + ["--slot4"] + a[i:]   # --slot4 必须在 --squad= 前面（run_setup 按顺序处理），否则第 4 人进不去


lc.run_args = run_args


def _opt(name, default=""):
    for a in sys.argv:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


def _lum(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def share(prefix, squads):
    """每层：占屏 %（差 > 8/255 的像素）、实心 %（差 > 0.3）、该层贡献的平均亮度增量（0–255，全战场区平均）、
    该层像素上的平均亮度（这一层本身多亮）；分 late / boss 两组、三连拍平均"""
    rows = {}
    for grp, scs in lc.SC_GROUP.items():
        for sq in squads:
            full = lc.files(prefix + "_full", sq, True)
            for ly in LAYERS + ["mates"]:
                for sc in scs:
                    for (pf, js, f) in full.get(sc, []):
                        if ly == "mates":
                            a_ = lc._img(os.path.join(lc.SHOT, prefix + "_nofriend", sq, "shot_%d.png" % f)) if os.path.exists(os.path.join(lc.SHOT, prefix + "_nofriend", sq, "shot_%d.png" % f)) else None
                            b_ = lc._img(os.path.join(lc.SHOT, prefix + "_nolead", sq, "shot_%d.png" % f)) if os.path.exists(os.path.join(lc.SHOT, prefix + "_nolead", sq, "shot_%d.png" % f)) else None
                            if a_ is None or b_ is None:
                                continue
                            A = lc._img(pf)
                            d_all = np.abs(A - a_).max(axis=2)
                            d_lead = np.abs(A - b_).max(axis=2)
                            m = (d_all > 8) & ~(d_lead > 8)
                            ms = (d_all > 76) & ~(d_lead > 76)
                            dl = float((_lum(b_) - _lum(a_)).mean())
                            lm = float(_lum(A)[m].mean()) if m.any() else 0.0
                        else:
                            pl = os.path.join(lc.SHOT, prefix + "_" + ly, sq, "shot_%d.png" % f)
                            if not os.path.exists(pl):
                                continue
                            A, B = lc._img(pf), lc._img(pl)
                            d = np.abs(A - B).max(axis=2)
                            m, ms = d > 8, d > 76
                            dl = float((_lum(A) - _lum(B)).mean())
                            lm = float(_lum(A)[m].mean()) if m.any() else 0.0
                        r = rows.setdefault((grp, sq, ly), [])
                        r.append((m.mean() * 100, ms.mean() * 100, dl, lm))
    out = {}
    print("| 分组 | 阵容 | 层 | 占屏 % | 实心 % | 亮度增量 | 该层像素亮度 |")
    print("|---|---|---|---|---|---|---|")
    for (grp, sq, ly), v in sorted(rows.items(), key=lambda kv: (kv[0][0], kv[0][1], (LAYERS + ["mates"]).index(kv[0][2]))):
        a = np.mean(np.array(v), axis=0)
        out.setdefault(grp, {}).setdefault(sq, {})[ly] = [float(x) for x in a]
        print("| %s | %s | %s | %.1f | %.1f | %+.1f | %.0f |" % (grp, sq, NAME[ly], a[0], a[1], a[2], a[3]))
    json.dump(out, open(os.path.join(lc.OUT, prefix + "_share.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return out


def main():
    cmd = sys.argv[1]
    sqs = tuple(_opt("squads", "A,B,C").split(","))
    par = int(_opt("par", "2"))
    more = [x for x in _opt("more").split(";") if x]
    if cmd == "capture":
        lc.run_jobs(lc.capture_jobs(sys.argv[2], None, _opt("dbg"), sqs, more), par)
    elif cmd == "layers":
        js = []
        for ly in ["full"] + LAYERS:
            js += lc.capture_jobs(sys.argv[2] + "_" + ly, None, "" if ly == "full" else ly, sqs, more)
        lc.run_jobs(js, par)
    elif cmd == "share":
        share(sys.argv[2], sqs)


if __name__ == "__main__":
    main()
