# -*- coding: utf-8 -*-
"""Boss 改版样板截图（docs/142b §9）：逐个开窗口局（走 godot_runner：副屏 / 屏幕外、静音、全机并发上限），
--autotest --bossmoves=<spec> 逐招放：预警 60% 截 shot_bossmove_<type>_<招>.png、结算后 8 帧截 _hit.png。
一次只开 1 个 Godot；结束靠进程自己退出（超时由 godot_runner 按自己的 PID 结束）。

    python tools/probes/boss_proto_shots.py                 # iberia / iberia2 / knight_boss / knight_boss2
    python tools/probes/boss_proto_shots.py iberia2         # 只跑一个
输出 build/boss_proto/<spec>/
"""
import os, shutil, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

specs = sys.argv[1:] or ["iberia", "iberia2", "knight_boss", "knight_boss2"]
for spec in specs:
    out = os.path.join(ROOT, "build", "boss_proto", spec)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--autotest", "--seed=1", "--op=mizuki", "--bossmoves=" + spec, "--shotdir=" + out.replace(os.sep, "/")]
    o, e, to = gr.run_godot(args, 300)
    open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    n = len([f for f in os.listdir(out) if f.endswith(".png")])
    print(spec, "shots:", n, "errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")
