# -*- coding: utf-8 -*-
"""乌尔比安 S3 冲锋特效（docs/140）：录帧对照 / 同局轮换量帧时。走 tools/godot_runner（并发上限、窗口放副屏 / 屏幕外、静音）。
用法：
  python tools/probes/ulp_charge_shot.py rec  <输出目录> [old] [mid] [n=100]   第一次放技能起连存 90 帧 rec_*.png（old = 冲锋颗粒关 / 旧画法；mid = 中画质）
  python tools/probes/ulp_charge_shot.py perf <输出目录> [casts=24] [n=100]     同局轮换：单数次冲锋颗粒开 / 双数次关（前 2 次预热不计），打印 ULPPERF
缺省 1280x720、高画质、--fixed-fps 60（录帧逐帧确定）；perf 不加 --fixed-fps 也照样按真实帧间隔记
"""
import os, sys, json, shutil, tempfile
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr


def run(out, extra, quality="high", timeout=300):
    os.makedirs(out, exist_ok=True)
    app = tempfile.mkdtemp(prefix="ulpcharge_app_")
    os.makedirs(os.path.join(app, "ArknightsSurvivors"))
    open(os.path.join(app, "ArknightsSurvivors", "settings.cfg"), "w").write(
        '[video]\nfullscreen=false\nres_index=0\nquality="%s"\n\n[audio]\nmaster=0.0\nmusic=0.0\nsfx=0.0\nvoice=0.0\n\n[progress]\ndifficulty=0\n' % quality)
    os.environ["APPDATA"] = app
    os.environ["ARK_REAL_USERDIR"] = "1"
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60",
            "--resolution", "1280x720", "res://tests/ulp_charge_shot.tscn", "--",
            "--balance", "--realtime", "--nodeath", "--bot=afk", "--seed=1", "--op=ulpianus",
            "--shotdir=" + out.replace(os.sep, "/")] + extra
    o, e, to = gr.run_godot(args, timeout)
    shutil.rmtree(app, ignore_errors=True)
    open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    for l in o.splitlines():
        if l.startswith("ULP"):
            print(l)
    print("errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")


if __name__ == "__main__":
    mode, out = sys.argv[1], os.path.abspath(sys.argv[2])
    rest = sys.argv[3:]
    n = next((a[2:] for a in rest if a.startswith("n=")), "100")
    if mode == "rec":
        extra = ["--ulprec", "--ulpn=" + n] + (["--ulpold"] if "old" in rest else [])
        run(out, extra, "mid" if "mid" in rest else "high")
    else:
        casts = next((a[6:] for a in rest if a.startswith("casts=")), "24")
        run(out, ["--ulpperf=" + casts, "--ulpn=" + n], timeout=600)
