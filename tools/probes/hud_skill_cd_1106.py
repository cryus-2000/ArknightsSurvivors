# -*- coding: utf-8 -*-
"""docs/290 指挥台技能细格示意（11-06）：实机截图，在 GCP（tools/gcp_render.py --job custom）上跑。
同一局（seed 3、水月队长 + 德克萨斯 / 能天使 / 塞雷娅，队友直接精二、队长不推进 → 队长 S2 / S3 没解锁），
90 秒起每 0.5 秒存一张，挑技能状态混着的那帧。场景（11-06 用户定 A 常驻 + 等级旁 + 冲刺沿轮廓 + 悬停，不做展开）：
  pc / ph      桌面 1920×1080 / 触屏手机横屏 1170×540，缺省开关
  pc_hover     桌面，--hoverop=2 当作鼠标停在能天使头像上
  pc_tab       桌面，91 秒打开 Tab 属性面板（编队栏技能细格）
整台闲时变淡（ui/console_idle）拍图时关掉，方便看清。
用法：python3 tools/probes/hud_skill_cd_1106.py --out <目录> [--only pc_l1,...]
"""
import argparse, os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

BASE = ["--balance", "--realtime", "--nodeath", "--seed=3", "--op=mizuki", "--slot4", "--squad=texas,exusiai,saria", "--elite2",
        "--bot=master", "--bal=ui/console_idle=1", "--rtfrom=86", "--maxt=101", "--dashat=90.2,90.6"]
PC = (["--resolution", "1920x1080"], ["--flashrec=90,330,1920"])
PH = (["--resolution", "1170x540"], ["--touch", "--flashrec=90,330,1170"])
SCENES = {
    "pc": (PC, []),                       # 缺省：技能细格队长在等级旁（console_skills 2）+ 冲刺沿轮廓充能
    "pc_hover": (PC, ["--hoverop=2"]),    # 悬停提示：当作鼠标停在第 2 名队友（能天使）上
    "pc_tab": (PC, ["--tabat=91"]),       # Tab 属性面板编队栏的技能细格（存 shot_tab.png）
    "ph": (PH, []),
}

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--only", default=",".join(SCENES))
a = ap.parse_args()
for name in a.only.split(","):
    (pre, post), extra = SCENES[name]
    d = os.path.join(ROOT, "build", "hud_skill_cd", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
            "--fixed-fps", "30"] + pre + ["--"] + BASE + post + extra + ["--shotdir=" + d.replace(os.sep, "/")]
    o, e, to = gr.run_godot(args, 1500)
    open(os.path.join(d, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    fr = sorted(f for f in os.listdir(d) if f.startswith("fr_"))
    print(name, "frames", len(fr), "errors", gr.script_errors(o, e)[:3], "timeout" if to else "")
    dst = os.path.join(a.out, name)
    os.makedirs(dst, exist_ok=True)
    for f in fr[::15] + [x for x in os.listdir(d) if x.startswith("shot_")]:
        shutil.copy(os.path.join(d, f), os.path.join(dst, f))
    shutil.copy(os.path.join(d, "run.log"), os.path.join(dst, "run.log"))
