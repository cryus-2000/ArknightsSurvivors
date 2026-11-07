# -*- coding: utf-8 -*-
"""PV 实机素材（11-08）：每局的参数 + 在 GCP 虚拟机上跑一局、把各段 jpg 编成 mp4。

  python3 tools/promo/pv_runs.py <局名> <输出目录>      # 虚拟机上（tools/gcp/render_jobs/pv_rec.sh 调）
  python  tools/promo/pv_runs.py --list                  # 列出各局

本机发起：python tools/gcp_render.py --branch <提交> --job custom --split --name pv1108 \
            --cmd 'bash tools/gcp/render_jobs/pv_rec.sh E' --cmd 'bash tools/gcp/render_jobs/pv_rec.sh H' …
每局：1920×1080、--fixed-fps 60 + --realtime（--rtfrom 之前快进），--quality=high，机器人 master、难度 4、不死。
录帧见 tools/promo/pv_rec.gd；分镜号对应 Claude Docs「方舟幸存者宣传 PV 分镜」。
"""
import glob, json, os, shutil, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = ["--balance", "--realtime", "--nodeath", "--bot=master", "--diff=4", "--quality=high", "--pickframes=90"]
MID = ["--op=mizuki", "--squad=skadi,texas"]

RUNS = {
    # 冒烟：12 秒短局，所有监视功能各走一遍
    "Z": dict(args=MID + ["--seed=12", "--lamphold=1:3"], rtfrom=0, maxt=12,
              pv=["--pv_win=2-4", "--pv_ult=5", "--pv_autoult", "--pv_ring=3:40:300", "--pv_elite=3.5:skimmer:200:0", "--pv_choice", "--pv_bossult=0.99"]),
    # #3 水月独行 + #5 招募 + #9 升级三选一：开局 0–95 秒连续录（选卡面板机器人停 1.5 秒）
    "E": dict(args=["--op=mizuki", "--seed=11"], rtfrom=0, maxt=96, pv=["--pv_win=0.3-95"]),
    # #1–#2 钩子：灯火压最低、四周一圈海嗣、到点充满水月终结技（三条备选）
    "H": dict(args=MID + ["--seed=12", "--lamphold=40:3"], rtfrom=55, maxt=116,
              pv=["--pv_win=58-72,78-92,98-112", "--pv_ring=60:70:330", "--pv_ult=66,86,106"]),
    # #7 三人小队 3 分钟、#10–#11 圆盘集火精英、#17–#18 中期 Boss（伊比利亚）弹幕 + 残血终结技击杀
    "S": dict(args=MID + ["--seed=13", "--forceboss=1", "--wheelplan=open@193,sel@0.5:3,ok@1.2", "--pickplan=snap@0.4,ok@1.8"],
              rtfrom=172, maxt=300, pv=["--pv_win=175-300", "--pv_elite=189:skimmer:330:-60", "--pv_bossult=0.15", "--pv_beacon"]),
    # #12 灯标：同 S 的阵容，前 3 分钟只录灯标充能 → 点亮（预录 1 秒）
    "B": dict(args=MID + ["--seed=21"], rtfrom=20, maxt=200, pv=["--pv_beacon"]),
    # #13 8 分钟后满屏怪潮（精二满节点）
    "L": dict(args=MID + ["--seed=14", "--maxprog", "--bal=ult/test_swarm_at=478", "--bal=ult/test_swarm_every=9", "--bal=ult/test_swarm_n=90"],
              rtfrom=470, maxt=512, pv=["--pv_win=474-511"]),
    # #19 俯瞰灯火圈（镜头拉远 80%）+ 最终 Boss 登场（剪影一闪的素材）
    "F": dict(args=MID + ["--seed=18", "--maxprog", "--camzoom=80", "--forceending=standard"], rtfrom=582, maxt=622, pv=["--pv_win=585-621"]),
    # #14–#16 终结技连放：安洁莉娜黑洞 / 维什戴尔炮击 / 浊心斯卡蒂吐息，各三条
    "UA": dict(args=["--op=angelina", "--squad=skadi,texas", "--seed=15", "--maxprog", "--bal=ult/test_swarm_at=472", "--bal=ult/test_swarm_every=15", "--bal=ult/test_swarm_n=90"],
               rtfrom=468, maxt=522, pv=["--pv_win=470-521", "--pv_ult=476,491,506"]),
    "UW": dict(args=["--op=wisadel", "--squad=skadi,texas", "--seed=16", "--maxprog", "--bal=ult/test_swarm_at=472", "--bal=ult/test_swarm_every=15", "--bal=ult/test_swarm_n=90"],
               rtfrom=468, maxt=522, pv=["--pv_win=470-521", "--pv_ult=476,491,506"]),
    "UK": dict(args=["--op=skalter", "--squad=skadi,texas", "--seed=17", "--maxprog", "--bal=ult/test_swarm_at=472", "--bal=ult/test_swarm_every=15", "--bal=ult/test_swarm_n=90"],
               rtfrom=468, maxt=522, pv=["--pv_win=470-521", "--pv_ult=476,491,506"]),
    # #8 德克萨斯 S3 近景（实战局，队长德克萨斯精二）
    "T": dict(args=["--op=texas", "--squad=mizuki,skadi", "--seed=19", "--maxprog", "--bal=ult/test_swarm_at=242", "--bal=ult/test_swarm_every=12",
                    "--bal=ult/test_skill_at=244", "--bal=ult/test_skill_idx=2", "--bal=ult/test_skill_every=6"],
              rtfrom=238, maxt=272, pv=["--pv_win=240-271"]),
}
# 图鉴演示（无 HUD、空场）：德克萨斯 S3 + 四人终结技备选
DEMOS = [("texas", 2, 3, 300), ("mizuki", 2, 4, 300), ("angelina", 2, 4, 300), ("wisadel", 2, 4, 300), ("skalter", 2, 4, 300)]


def ffmpeg():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return shutil.which("ffmpeg") or "ffmpeg"


def encode(src_glob_dir, pattern, dst, fps=60):
    r = subprocess.run([ffmpeg(), "-v", "error", "-y", "-framerate", str(fps), "-i", os.path.join(src_glob_dir, pattern),
                        "-c:v", "libx264", "-crf", "15", "-preset", "medium", "-pix_fmt", "yuv420p", "-r", str(fps), dst])
    return r.returncode


def run_game(name, out):
    r = RUNS[name]
    godot = os.environ.get("GODOT", "godot")
    raw = os.path.join(out, "raw")
    os.makedirs(raw, exist_ok=True)
    args = [godot, "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--resolution", "1920x1080",
            "--position", "0,0", "-s", os.path.join(ROOT, "tools", "promo", "pv_rec.gd"), "--"] + BASE + r["args"]
    if r["rtfrom"] > 0:
        args.append("--rtfrom=%d" % r["rtfrom"])
    args += ["--pv_out=" + raw, "--pv_maxt=%s" % r["maxt"], "--pv_rtfrom=%s" % r["rtfrom"]] + r["pv"]
    t0 = time.time()
    with open(os.path.join(out, "godot.log"), "w", encoding="utf-8") as fh:
        fh.write(" ".join(args) + "\n\n")
        fh.flush()
        p = subprocess.run(args, stdout=fh, stderr=subprocess.STDOUT, timeout=4 * 3600)
    print("%s rc=%d %.0fs" % (name, p.returncode, time.time() - t0), flush=True)
    media = os.environ.get("MEDIA", os.path.join(out, "media"))
    os.makedirs(media, exist_ok=True)
    shutil.copy(os.path.join(raw, "pv.log"), os.path.join(media, "%s_pv.log" % name))
    for d in sorted(glob.glob(os.path.join(raw, "seg_*"))):
        seg = os.path.basename(d)
        n = len(glob.glob(os.path.join(d, "f*.jpg")))
        rc = encode(d, "f%05d.jpg", os.path.join(media, "%s_%s.mp4" % (name, seg))) if n else -1
        if os.path.exists(os.path.join(d, "sfx.json")):
            shutil.copy(os.path.join(d, "sfx.json"), os.path.join(media, "%s_%s.sfx.json" % (name, seg)))
        print("  %s %d 帧 rc=%d" % (seg, n, rc), flush=True)
        shutil.rmtree(d, ignore_errors=True)


def run_demos(out):
    godot = os.environ.get("GODOT", "godot")
    media = os.environ.get("MEDIA", os.path.join(out, "media"))
    os.makedirs(media, exist_ok=True)
    for op, stage, mode, n in DEMOS:
        d = os.path.join(out, "demo_%s_%d" % (op, mode))
        os.makedirs(d, exist_ok=True)
        args = [godot, "--audio-driver", "Dummy", "--resolution", "1920x1080", "--position", "0,0", "--fixed-fps", "60", "--path", os.path.join(ROOT, "game"),
                "res://tests/elite_demo_shot.tscn", "--", "--shot_op=" + op, "--shot_stage=%d" % stage, "--shot_mode=%d" % mode, "--shot_dir=" + d,
                "--shot_start=0.5", "--shot_every=1", "--shot_n=%d" % n, "--shot_w=1920", "--shot_h=1080", "--quality=high"]
        with open(d + ".log", "w", encoding="utf-8") as fh:
            p = subprocess.run(args, stdout=fh, stderr=subprocess.STDOUT, timeout=1800)
        fs = sorted(glob.glob(os.path.join(d, "f_*.png")))
        lst = os.path.join(d, "list.txt")
        with open(lst, "w") as fh:
            for f in fs:
                fh.write("file '%s'\nduration %.6f\n" % (f, 1 / 60))
        rc = subprocess.run([ffmpeg(), "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c:v", "libx264", "-crf", "15", "-preset", "medium",
                             "-pix_fmt", "yuv420p", "-r", "60", os.path.join(media, "D_%s_m%d.mp4" % (op, mode))]).returncode if fs else -1
        shutil.copy(d + ".log", os.path.join(media, "D_%s_m%d.log" % (op, mode)))
        print("demo %s m%d rc=%d %d 张 enc=%d" % (op, mode, p.returncode, len(fs), rc), flush=True)
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    if sys.argv[1] == "--list":
        for k, v in RUNS.items():
            print(k, v)
        sys.exit(0)
    name, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    if name == "D":
        run_demos(out)
    else:
        run_game(name, out)
