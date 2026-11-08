# -*- coding: utf-8 -*-
"""PV v2（11-08 晚，参考官方水月 PV 剪法重剪）：按小节写镜头表 → edit.json 的 main2 / vert2 + music。

配乐 battle2 从第 77 小节一路连到曲尾（38.5 小节 ≈ 63.3 秒），中间不拼接；镜头只在小节线（少数半小节）上切。
  77      drop 前一小节        水月终结技立绘切入
  78–85   第一次 drop          钩子：终结技冲击帧落 78 重拍 → 怪潮 → 维什戴尔 → 弹幕 → 浊心斯卡蒂（82 重拍）→ 大字卡
  86–87   贝斯退出（安静）      水月独行
  88–95   律动段               登场卡 → 招募 → 小队 → 升级
  96–104  爬升                 指挥 → 灯标 → 怪潮 → 黑洞
  105–106 断（只剩底层）        中期 Boss 登场
  107     拾音                 水月终结技
  108     第二次 drop 重拍      击破，之后慢放
  110–111                     俯瞰灯火圈
  112–    曲尾                 标题
竖版：106.375 小节起 9.125 小节 = 15.0 秒。
  python tools/promo/gen_v2.py && python tools/promo/pv.py main2 <输出>
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import music

BAR = music.BAR
B0 = 70   # 11-08 加 3D 开头：配乐从第 70 小节起


def T(b, base=B0):
    return round((b - base) * BAR, 4)


def shot(b0, b1, base=B0, **kw):
    d = {"t0": T(b0, base), "t1": T(b1, base)}
    for k in ("ramp_tb",):
        pass
    if "ramp" in kw and len(kw["ramp"]) == 3 and isinstance(kw["ramp"][2], str):
        a, b, at = kw["ramp"]          # at = "bar:<小节>" 或 "+<秒>"
        tb = T(float(at[4:]), base) if at.startswith("bar:") else d["t0"] + float(at)
        kw["ramp"] = [a, b, round(tb, 4)]
    d.update(kw)
    d.setdefault("kind", "clip")
    return d


GL = 4   # 故障转场帧数
main = [
    shot(70, 77, src="P3D.mp4", f=0, _="3D 开头（tools/promo/pv3d.gd）：金边实体招募卡 / 升级卡漂浮下落 → 贴海床一排立起 → 74 重拍一张砸到镜头前推进"),
    shot(77, 79, src="H_seg_01_win_t058.0.mp4", ramp=[400, 610, "bar:78"], _="终结技立绘切入，冲击帧落 78 重拍"),
    shot(79, 80, src="L4_seg_01_win_t460.0.mp4", f=140, push=0.06, glitch=GL),
    shot(80, 81, src="UW_seg_01_win_t470.0.mp4", ramp=[508, 544, "+0.6"], flash=3),
    shot(81, 82, src="K1_seg_01_fwin_t150.0.mp4", f=520, glitch=GL),
    shot(82, 83, src="UK_seg_01_win_t470.0.mp4", ramp=[1400, 1414, "+0.12"], flash=4, _="吐息冲击落 82 重拍"),
    shot(83, 84, src="D_angelina_m4.mp4", ramp=[200, 250, "+0.6"], zoom=2.2, cx=0.55, cy=0.47, glitch=GL),
    shot(84, 85, kind="word", text="队长", sub="CAPTAIN", glitch=GL),
    shot(85, 88, src="E_seg_01_win_t000.3.mp4", f=3720 - 99, glitch=GL, _="贝斯退出：水月独行"),
    shot(88, 89, kind="card", card="op:mizuki", v2=True, tag="队长"),
    shot(89, 91, src="E_seg_01_win_t000.3.mp4", f=4290, flash=4, _="招募三选一 → 入队"),
    shot(91, 92, kind="card", card="op:skadi", v2=True),
    shot(92, 93, kind="card", card="op:texas", v2=True),
    shot(93, 94, kind="word", text="升级", sub="LEVEL UP", glitch=GL),
    shot(94, 96, src="T_seg_01_win_t240.0.mp4", f=925, glitch=GL, _="升级三选一 → 刀光变大"),
    shot(96, 97, kind="word", text="指挥", sub="COMMAND", col=[255, 61, 139], glitch=GL),
    shot(97, 99, src="S3_seg_01_win_t175.0.mp4", f=1345, glitch=GL, _="指挥圆盘 → 集火精英"),
    shot(99, 100, src="S3_seg_01_win_t175.0.mp4", f=1345 + 200),
    shot(100, 101, kind="word", text="灯火", sub="LAMPLIGHT", col=[244, 192, 78], glitch=GL),
    shot(101, 103, src="B_seg_01_beacon_t164.2.mp4", f=0, zoom=1.35, cy=0.45, glitch=GL),
    shot(103, 104, src="L4_seg_01_win_t460.0.mp4", f=300, push=0.06, glitch=GL),
    shot(104, 105, src="UW_seg_01_win_t470.0.mp4", ramp=[470, 544, "+0.8"], flash=3),
    shot(105, 107, src="K1_seg_01_fwin_t150.0.mp4", f=84, glitch=GL, _="断：中期 Boss 登场"),
    shot(107, 110, src="S5_seg_01_win_t205.0.mp4", ramp=[2900, 3100, "bar:108"], after=0.35, _="终结技 → 击破落 108 重拍，之后慢放"),
    shot(110, 112, src="F2_seg_01_win_t585.0.mp4", f=700, push=0.05, glitch=GL),
    shot(112, 115.5, kind="title"),
]
VB = 106.375
vert = [
    shot(106.375, 107, VB, src="K1_seg_01_fwin_t150.0.mp4", f=520),
    shot(107, 109.5, VB, src="S5_seg_01_win_t205.0.mp4", ramp=[2900, 3100, "bar:108"], after=0.4),
    shot(109.5, 110.5, VB, src="L4_seg_01_win_t460.0.mp4", f=200, glitch=GL),
    shot(110.5, 111.5, VB, src="UW_seg_01_win_t470.0.mp4", ramp=[500, 544, "+0.6"], flash=3),
    shot(111.5, 113, VB, src="D_angelina_m4.mp4", ramp=[195, 250, "+0.6"], zoom=2.2, cx=0.55, cy=0.47, glitch=GL),
    shot(113, 115.5, VB, kind="title"),
]
p = os.path.join(HERE, "edit.json")
ed = json.load(open(p, encoding="utf-8"))
ed["main2"], ed["vert2"] = main, vert
ed["music"] = {"main2": {"segs": [[70, 45.5]], "tail_fade": 1.6}, "vert2": {"segs": [[VB, 9.125]], "tail_fade": 1.2}}
json.dump(ed, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("main2 %.3f 秒 %d 镜；vert2 %.3f 秒" % (main[-1]["t1"], len(main), vert[-1]["t1"]))
