# -*- coding: utf-8 -*-
"""指挥圆盘终末地风格截图 / 动效录像（docs/144）。走 tools/godot_runner（并发上限、窗口放副屏 / 屏幕外、静音）。
用法：
  python tools/probes/wheel_style_shots.py shot [hover=2] [res=desktop,phone] [rm]   打开圆盘、悬停某项，截终态 + 展开中段一帧
  python tools/probes/wheel_style_shots.py rec  [res=desktop] [rm]                  打开 → 依次悬停 0–4 → 确认，逐帧存图并拼 30 帧 gif
输出到主仓库 build/wheel_style/；rm = 开「减少动态效果」
"""
import os, sys, glob, shutil, tempfile
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

RES = {"desktop": ("1280x720", []), "phone": ("1560x720", ["--touch"])}
REC_PLAN = "open@5,sel@0.45:0,sel@0.8:1,sel@1.15:2,sel@1.5:3,sel@1.85:4,ok@2.4"


def run(d, res, rm, plan, nframes):
    size, extra = RES[res]
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    app = tempfile.mkdtemp(prefix="wheelstyle_app_")
    os.makedirs(os.path.join(app, "ArknightsSurvivors"))
    open(os.path.join(app, "ArknightsSurvivors", "settings.cfg"), "w").write(
        '[video]\nfullscreen=false\nres_index=0\nquality="high"\n\n[audio]\nmaster=0.0\nmusic=0.0\nsfx=0.0\nvoice=0.0\n\n'
        '[game]\nreduce_motion=%s\n\n[progress]\ndifficulty=0\n' % ("true" if rm else "false"))
    os.environ["APPDATA"] = app
    os.environ["ARK_REAL_USERDIR"] = "1"
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60",
            "--resolution", size, "--",
            "--balance", "--realtime", "--nodeath", "--bot=afk", "--seed=1",
            "--wheelplan=" + plan, "--recframes=5,%d" % nframes, "--shotdir=" + d.replace(os.sep, "/")] + extra
    o, e, to = gr.run_godot(args, 400)
    shutil.rmtree(app, ignore_errors=True)
    errs = gr.script_errors(o, e)
    frames = sorted(glob.glob(os.path.join(d, "rec_*.png")))
    print(os.path.basename(d), "帧", len(frames), "超时" if to else "", errs[:3])
    return frames, errs


if __name__ == "__main__":
    mode = sys.argv[1]
    rest = sys.argv[2:]
    out = os.path.join(gr.common_root(), "build", "wheel_style")
    os.makedirs(out, exist_ok=True)
    gr.ensure_imported(os.path.join(ROOT, "game"))
    rm = "rm" in rest
    tag = "_rm" if rm else ""
    if mode == "shot":
        hover = int(next((a[6:] for a in rest if a.startswith("hover=")), "2"))
        for r in next((a[4:] for a in rest if a.startswith("res=")), "desktop,phone").split(","):
            d = os.path.join(out, "_shot_%s_%d%s" % (r, hover, tag))
            frames, errs = run(d, r, rm, "open@5,sel@0.25:%d" % hover, 40)
            if frames:
                dst = os.path.join(out, "wheel_%s_h%d%s.png" % (r, hover, tag))
                shutil.copy(frames[-1], dst)
                shutil.copy(frames[min(6, len(frames) - 1)], dst.replace(".png", "_open.png"))
            if frames and not errs:
                shutil.rmtree(d, ignore_errors=True)
    else:
        r = next((a[4:] for a in rest if a.startswith("res=")), "desktop")
        d = os.path.join(out, "rec_%s%s" % (r, tag))
        frames, errs = run(d, r, rm, REC_PLAN, 190)
        if frames:
            from PIL import Image
            ims = [Image.open(f).convert("RGB").resize((640, 360) if r == "desktop" else (780, 360), Image.LANCZOS) for f in frames[::2]]
            ims = [im.quantize(colors=128, method=Image.Quantize.MEDIANCUT) for im in ims]
            gif = os.path.join(out, "wheel_motion_%s%s.gif" % (r, tag))
            ims[0].save(gif, save_all=True, append_images=ims[1:], duration=33, loop=0)
            print("gif", gif)
