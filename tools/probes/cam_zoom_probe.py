# -*- coding: utf-8 -*-
"""战斗镜头拉远候选（docs/112）：同 seed 同局按不同镜头档截图 / 录像 / 量帧时间。不改游戏代码。
用法：
  python tools/probes/cam_zoom_probe.py shot <标签> <zoom> [res] [额外游戏参数…]   静态图 60/240/480 秒 + 240 秒起录 3 秒（mp4 整屏 + 主控周围 1:1 裁窗放大 3 倍）
  python tools/probes/cam_zoom_probe.py perf <标签> <z1,z2,…> [res] [maxt]          同局每 60 帧轮换镜头档，按档按分钟记帧时间
res 缺省 1920x1080；输出 build/camzoom/<标签>/。走 tools/godot_runner（并发上限、窗口放副屏 / 屏幕外、只按自己的 PID 结束）
缺省局：水月队长 + 斯卡蒂 / 塞雷娅，Ⅳ，熟练机器人，seed=1，--nodeath，高画质，--fixed-fps 60 真实步长
"""
import os, sys, json, glob, shutil, subprocess, tempfile
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

RES_INDEX = {"1280x720": 0, "1920x1080": 1, "2560x1440": 2, "3840x2160": 3}


def run(out, cz_args, res, extra, timeout):
    os.makedirs(out, exist_ok=True)
    app = tempfile.mkdtemp(prefix="camzoom_app_")
    os.makedirs(os.path.join(app, "ArknightsSurvivors"))
    ri = RES_INDEX.get(res, 1)
    open(os.path.join(app, "ArknightsSurvivors", "settings.cfg"), "w").write(
        '[video]\nfullscreen=false\nres_index=%d\nquality="high"\n\n[audio]\nmaster=0.0\nmusic=0.0\nsfx=0.0\nvoice=0.0\n\n[progress]\ndifficulty=0\n' % ri)
    os.environ["APPDATA"] = app
    os.environ["ARK_REAL_USERDIR"] = "1"
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60",
            "--resolution", res, "-s", os.path.join(ROOT, "tools", "probes", "cam_zoom_probe.gd"), "--",
            "--balance", "--realtime", "--nodeath", "--seed=1", "--op=mizuki", "--squad=skadi,saria", "--bot=master", "--diff=4",
            "--cz_out=" + out.replace(os.sep, "/")] + cz_args + extra
    o, e, to = gr.run_godot(args, timeout)
    shutil.rmtree(app, ignore_errors=True)
    open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
    cz = None
    for l in o.splitlines():
        if l.startswith("CZSHOT"):
            print(l)
        if l.startswith("CZ "):
            cz = json.loads(l[3:])
    print("errors:", gr.script_errors(o, e)[:5], "timeout" if to else "")
    return cz


def encode(out, res):
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    rec = os.path.join(out, "rec")
    if not glob.glob(os.path.join(rec, "f*.png")):
        return
    src = os.path.join(rec, "f%04d.png")
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "60", "-i", src, "-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p",
                    os.path.join(out, "move_full.mp4")], check=True)
    w, h = (int(v) for v in res.split("x"))
    cw, ch = 400, 240   # 主控在画面正中：取中心 400×240 屏幕像素，最近邻放大 3 倍看像素抖动
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "60", "-i", src, "-vf",
                    "crop=%d:%d:%d:%d,scale=%d:%d:flags=neighbor" % (cw, ch, (w - cw) // 2, (h - ch) // 2 - 20, cw * 3, ch * 3),
                    "-c:v", "libx264", "-crf", "12", "-pix_fmt", "yuv420p", os.path.join(out, "move_crop3x.mp4")], check=True)
    shutil.copy(os.path.join(rec, "f0090.png"), os.path.join(out, "move_f0090.png"))
    shutil.rmtree(rec, ignore_errors=True)


def main():
    mode, tag = sys.argv[1], sys.argv[2]
    out = os.path.join(ROOT, "build", "camzoom", tag)
    if mode == "shot":
        z = sys.argv[3]
        res = sys.argv[4] if len(sys.argv) > 4 else "1920x1080"
        extra = sys.argv[5:]
        cz = run(out, ["--cz=" + z, "--cz_shots=60,240,480", "--cz_rec=240@3", "--cz_maxt=481"], res, extra, 2400)
        encode(out, res)
    elif mode == "pic":   # 单点出图：pic <标签> <zoom> <秒> [res]；原尺寸静态图（用户并排看镜头倍率）
        z, t = sys.argv[3], sys.argv[4]
        res = sys.argv[5] if len(sys.argv) > 5 else "1280x720"
        cz = run(out, ["--cz=" + z, "--cz_shots=" + t, "--cz_maxt=" + str(int(t) + 2)], res, [], 1800)
    elif mode == "multi":   # 同帧多档：multi <标签> <pct,pct,…> <秒> [res]；冻结模拟后逐档改设置里的缩放存图，同一局同一帧
        pcts, t = sys.argv[3], sys.argv[4]
        res = sys.argv[5] if len(sys.argv) > 5 else "1280x720"
        cz = run(out, ["--cz_multi=" + pcts, "--cz_multi_t=" + t, "--cz_maxt=" + str(int(t) + 30)], res, [], 1800)
    elif mode == "look":   # 亮度候选：镜头 100%，240–660 秒每 30 秒一张；额外参数给 --bal=render/…
        res = "1920x1080"
        ts = ",".join(str(t) for t in range(240, 661, 30))
        cz = run(out, ["--cz=1", "--cz_shots=" + ts, "--cz_maxt=661"], res, sys.argv[3:], 3600)
    else:
        zs = sys.argv[3]
        res = sys.argv[4] if len(sys.argv) > 4 else "1920x1080"
        maxt = sys.argv[5] if len(sys.argv) > 5 else "600"
        cz = run(out, ["--cz_ab=" + zs, "--cz_ab_n=60", "--cz_maxt=" + maxt], res, [], 3600)
    if cz is not None:
        json.dump(cz, open(os.path.join(out, "cz.json"), "w"), ensure_ascii=False)
        print("CZ", {k: cz[k] for k in cz if k in ("vs", "win", "rec", "multi")})


if __name__ == "__main__":
    main()
