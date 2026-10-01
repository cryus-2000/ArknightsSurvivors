# -*- coding: utf-8 -*-
"""宣传截图（界面与美术 2026-09-30）：确定性批跑 + tools/promo_shots.gd 监视六种场面，存候选到 build/promo/shots_<tag>/。
用法：python tools/promo_shots.py [tag] [附加游戏参数…]
缺省：水月主控 + 斯卡蒂 / 塞雷娅，Ⅳ，高手机器人，seed=1，1920×1080 高画质，--fixed-fps 60（每帧 1 步，逐帧可复现）
走 tools/godot_runner（全机并发上限）；只按自己的 PID 结束。
"""
import os, sys, tempfile, shutil
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

tag = sys.argv[1] if len(sys.argv) > 1 else "a"
extra = sys.argv[2:]
out = os.path.join(ROOT, "build", "promo", "shots_" + tag)
os.makedirs(out, exist_ok=True)
app = tempfile.mkdtemp(prefix="promo_app_")
os.makedirs(os.path.join(app, "ArknightsSurvivors"))
open(os.path.join(app, "ArknightsSurvivors", "settings.cfg"), "w").write(
    '[video]\nfullscreen=false\nres_index=1\nquality="high"\n\n[audio]\nmaster=0.0\nmusic=0.0\nsfx=0.0\nvoice=0.0\n')
os.environ["APPDATA"] = app
os.environ["ARK_REAL_USERDIR"] = "1"   # 否则 c2c1528 后的 godot_runner 会换成它自己的 1280×720 设置，盖掉上面的 1920×1080
args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60",
        "-s", os.path.join(ROOT, "tools", "promo_shots.gd"), "--",
        "--balance", "--realtime", "--nodeath", "--seed=1", "--op=mizuki", "--squad=skadi,saria", "--bot=master", "--diff=4",
        "--promo_out=" + out.replace(os.sep, "/"), "--promo_maxt=660"] + extra   # extra 可再给 --promo_maxt= / --promo_only=（后给的覆盖）
o, e, to = gr.run_godot(args, 2400)
shutil.rmtree(app, ignore_errors=True)
open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
print("\n".join(l for l in o.splitlines() if l.startswith("PROMO")))
print("errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")
