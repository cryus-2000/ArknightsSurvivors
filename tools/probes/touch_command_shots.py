# -*- coding: utf-8 -*-
"""触屏指挥「点选 → 预选 → 再点确认」示意截图（docs/312）。走 tools/godot_runner（并发上限、窗口放副屏 / 屏幕外、静音）。
用法：
  python tools/probes/touch_command_shots.py [out=<目录>] [mode=focus,point] [res=phone] [old]
    focus：刷两只精英 → 圆盘选「集火」→ 点第二只（预选）→ 点第一只（换预选）→ 再点预选（下令）
    point：圆盘选「部署」→ 点地面（预选）→ 点另一处（换落点）→ 再点标记（下令）
    old：command/touch_confirm=0（旧的按住拖），对照用
每种存 6 张关键帧 <mode>_<res>_<步>.png（wheel / pick / pre / switch / done / order）
"""
import os, sys, glob, shutil, tempfile
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

RES = {"desktop": ("1280x720", ["--touch"]), "phone": ("1560x720", ["--touch"])}
WHEEL = {"focus": "open@4,sel@0.3:3,ok@0.6", "point": "open@4,sel@0.3:2,ok@0.6"}
PICK = {"focus": "tapsnap@0.8:1,tapsnap@1.8:0,tappre@2.8",
        "point": "tapdeploy@0.8:260:-90,tapdeploy@1.8:-230:110,tappre@2.8"}
# 关键帧（圆盘打开后的渲染帧号，60 帧 / 秒）
KEYS = [("1wheel", 24), ("2pick", 72), ("3pre", 120), ("4switch", 180), ("5done", 214), ("6order", 280)]


def run(d, mode, res, old):
    size, extra = RES[res]
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    app = tempfile.mkdtemp(prefix="touchcmd_app_")
    os.makedirs(os.path.join(app, "ArknightsSurvivors"))
    open(os.path.join(app, "ArknightsSurvivors", "settings.cfg"), "w").write(
        '[video]\nfullscreen=false\nres_index=0\nquality="high"\n\n[audio]\nmaster=0.0\nmusic=0.0\nsfx=0.0\nvoice=0.0\n\n'
        '[game]\nreduce_motion=false\n\n[progress]\ndifficulty=0\n')
    os.environ["APPDATA"] = app
    os.environ["ARK_REAL_USERDIR"] = "1"
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60",
            "--resolution", size, "--",
            "--balance", "--realtime", "--nodeath", "--bot=afk", "--seed=1", "--op=mizuki", "--squad=hoshiguma,exusiai",
            "--spawnat=3:knight@300:-70;mimic@-330:60" if mode == "focus" else "--spawnat=-1:",
            "--wheelplan=" + WHEEL[mode], "--pickplan=" + PICK[mode],
            "--recframes=4,%d" % (KEYS[-1][1] + 4), "--shotdir=" + d.replace(os.sep, "/")] + extra
    if old:
        args.append("--bal=command/touch_confirm=0")
    o, e, to = gr.run_godot(args, 400)
    shutil.rmtree(app, ignore_errors=True)
    errs = gr.script_errors(o, e)
    frames = sorted(glob.glob(os.path.join(d, "rec_*.png")))
    print(mode, res, "帧", len(frames), "超时" if to else "", errs[:3])
    return frames, errs


if __name__ == "__main__":
    rest = sys.argv[1:]
    out = next((a[4:] for a in rest if a.startswith("out=")), os.path.join(gr.common_root(), "build", "touch_command"))
    os.makedirs(out, exist_ok=True)
    gr.ensure_imported(os.path.join(ROOT, "game"))
    old = "old" in rest
    for mode in next((a[5:] for a in rest if a.startswith("mode=")), "focus,point").split(","):
        for r in next((a[4:] for a in rest if a.startswith("res=")), "phone").split(","):
            d = os.path.join(out, "_raw_%s_%s%s" % (mode, r, "_old" if old else ""))
            frames, errs = run(d, mode, r, old)
            for name, f in KEYS:
                if f < len(frames):
                    shutil.copy(frames[f], os.path.join(out, "%s_%s%s_%s.png" % (mode, r, "_old" if old else "", name)))
            if frames and not errs:
                shutil.rmtree(d, ignore_errors=True)
