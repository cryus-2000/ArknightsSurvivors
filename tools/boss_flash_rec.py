# -*- coding: utf-8 -*-
"""Boss 战频闪录像（docs/137）：开一个窗口局（走 godot_runner：副屏 / 屏幕外、静音、全机并发上限），按 --flashrec 逐帧存缩小图 + 状态 CSV。
用法：python tools/boss_flash_rec.py <tag> <场景> [附加游戏参数…]
场景：
  final    —— 正常对局把 Boss 时刻提前（--bosstimes=20,40,60），最终 Boss（标准结局 = 偏执泡影）走完整的入场 / 登场 / 两阶段 / 茧；
              从 58 秒录 30 秒（900 帧 @30fps）
  p1 / p2 / cocoon / knight —— 第 20 帧在主控旁直接刷出 偏执泡影一阶段 / 二阶段 / 茧 / 骑士（--flashspawn），从 2 秒录 8 秒
输出 build/boss_flash/<tag>_<场景>/（fr_*.png、flashrec.csv、run.log）；之后 python tools/boss_flash_measure.py <目录>
只开 1 个 Godot、--fixed-fps 30、限帧；结束只靠进程自己退出（超时由 godot_runner 按自己的 PID 结束）。
"""
import os, sys, shutil
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

tag, scene = sys.argv[1], sys.argv[2]
extra = sys.argv[3:]
out = os.path.join(ROOT, "build", "boss_flash", "%s_%s" % (tag, scene))
shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
squad = "--squad=skadi,saria,texas,exusiai,eyjafjalla"
base = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
        "--balance", "--realtime", "--nodeath", "--seed=1", "--op=mizuki", squad, "--prog=6", "--bot=master",
        "--shotdir=" + out.replace(os.sep, "/")]
if scene == "final":
    args = base + ["--bosstimes=20,40,60", "--rtfrom=50", "--flashrec=58,900", "--maxt=200"]
else:
    boss = {"p1": "paranoia", "p2": "paranoia2", "cocoon": "paranoia_cocoon", "knight": "knight_boss"}[scene]
    args = base + ["--rtfrom=0", "--flashspawn=" + boss, "--flashrec=2,240", "--maxt=60"]
o, e, to = gr.run_godot(args + extra, 900)
open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
n = len([f for f in os.listdir(out) if f.startswith("fr_")])
print("frames:", n, "errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")
