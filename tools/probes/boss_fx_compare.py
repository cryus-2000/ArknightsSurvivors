# -*- coding: utf-8 -*-
"""Boss 特效精修前后对比视频（docs/142b §9，用户 10-25「boss 的特效修一下」）：同一个 --bossacts 演示（同 seed，玩法一致、只有画面不同）
改前录一遍、改后录一遍，每帧左旧右新并排（各裁中间 70% 宽的 16:9、缩到 640 宽），H.264 yuv420p 实时帧率、无音轨，给用户手机看。
截图流程同 tools/probes/boss_act_gifs.py（副屏 / 屏幕外、静音、一次只开 1 个 Godot）。

    python tools/probes/boss_fx_compare.py before          # 录「旧」→ build/boss_fx/before/<spec>/（有 build/_fx_before/game 就用那份改前检出）
    python tools/probes/boss_fx_compare.py after           # 改完后录「新」→ build/boss_fx/after/<spec>/
    python tools/probes/boss_fx_compare.py video           # 拼 build/boss_fx/<spec>_compare.mp4
    python tools/probes/boss_fx_compare.py perf            # 同局轮换新 / 旧帧时 P50 / P95 → build/boss_fx/perf.md（缺省只量伊祖米克）
    （后面可接 spec 只跑这几只，如 ... before ishar paranoia）
"""
import os, re, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "probes"))
import boss_act_gifs as bag

OUT = os.path.join(ROOT, "build", "boss_fx")
SPECS = ["knight_boss", "path", "iberia", "carmen", "bishop+archon", "bishop+immortal", "paranoia", "ishar", "izumik"]
HW = 640


BEFORE_GAME = os.path.join(ROOT, "build", "_fx_before", "game")   # 「旧」= 改前提交的独立检出（git worktree add --detach build/_fx_before <提交>，拷 .godot 导入缓存）


def record(which, specs, extra=None):
    for spec in specs:
        src, _ = bag.run(spec, BEFORE_GAME if which == "before" and os.path.isdir(BEFORE_GAME) else None, extra)
        dst = os.path.join(OUT, which, spec.replace("+", "_"))
        shutil.rmtree(dst, ignore_errors=True)
        shutil.copytree(src, dst)


def _shots(d):
    return sorted(f for f in os.listdir(d) if f.startswith("shot_acts_") and f.endswith(".png")) if os.path.isdir(d) else []


def _crop(path, crop=0.7):
    im = Image.open(path).convert("RGB")
    w0, h0 = im.size
    cw, ch = int(w0 * crop), int(w0 * crop * 9 / 16)
    x0, y0 = (w0 - cw) // 2, max(0, (h0 - ch) // 2)
    return im.crop((x0, y0, x0 + cw, y0 + ch)).resize((HW, int(HW * 9 / 16) // 2 * 2), Image.LANCZOS if crop >= 0.6 else Image.NEAREST)


def video(specs):
    import imageio_ffmpeg
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
    except OSError:
        font = None
    jobs = []
    for spec in specs:
        jobs.append((spec, 0.7, ""))
        if spec in ("ishar", "izumik"):
            jobs.append((spec, 0.45, "_closeup"))   # 特写并排（用户 10-25：伊莎玛拉看内波纹、伊祖米克看潮汐坠落）
    for spec, crop, suffix in jobs:
        tag = spec.replace("+", "_")
        da, db = os.path.join(OUT, "before", tag), os.path.join(OUT, "after", tag)
        fa, fb = _shots(da), _shots(db)
        n = min(len(fa), len(fb))
        if n == 0:
            print(spec, "缺截图（先跑 before / after）")
            continue
        ts = [float(x) for x in re.findall(r"BOSSACTS gate t=([0-9.]+)", open(os.path.join(db, "run.log"), encoding="utf-8", errors="replace").read())]
        fps = len(fb) / max(1.0, ts[-1] - 150.0) if ts else 6.5
        tmp = tempfile.mkdtemp(prefix="bossfx_")
        h = int(HW * 9 / 16) // 2 * 2
        for i in range(n):
            frame = Image.new("RGB", (HW * 2 + 8, h), (10, 12, 18))
            frame.paste(_crop(os.path.join(da, fa[i]), crop), (0, 0))
            frame.paste(_crop(os.path.join(db, fb[i]), crop), (HW + 8, 0))
            d = ImageDraw.Draw(frame)
            for x, s in ((8, "旧"), (HW + 16, "新")):
                d.rectangle((x - 4, 4, x + 30, 32), fill=(0, 0, 0))
                d.text((x, 6), s, fill=(255, 230, 150), font=font)
            frame.save(os.path.join(tmp, "f%04d.png" % i))
        dst = os.path.join(OUT, tag + suffix + "_compare.mp4")
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", "%.3f" % fps, "-i", os.path.join(tmp, "f%04d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "slow", "-crf", "24", "-movflags", "+faststart", "-an", dst], check=True)
        shutil.rmtree(tmp, ignore_errors=True)
        print(dst, "%.1f MB" % (os.path.getsize(dst) / 1048576.0), n, "帧")


def perf(specs):
    """同局轮换帧时（协调人 10-25）：--bossacts 每幕 10 秒（最终 Boss 30 秒、中期 20 秒）、--fixed-fps 60、--perfab=30 每 30 帧切新 / 旧画法、
    不截图；a = 新（Boss 颗粒开）、b = 旧（g.perf_alt：Boss 颗粒全关，含每幕颗粒 / 大群之歌新画法）。表写 build/boss_fx/perf.md"""
    import godot_runner as gr
    rows = ["| Boss | 新 P50 | 旧 P50 | 新 P95 | 旧 P95 | P95 差 |", "|---|---|---|---|---|---|"]
    for spec in specs:
        args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60", "--",
                "--autotest", "--seed=1", "--op=mizuki", "--bossacts=" + spec, "--perfab=30", "--noshots", "--bal=boss/acts_demo_len=10",
                "--shotdir=" + os.path.join(OUT, "perf").replace(os.sep, "/")]
        os.makedirs(os.path.join(OUT, "perf"), exist_ok=True)
        o, e, to = gr.run_godot(args, 400)
        got = {m.group(1): (float(m.group(2)), float(m.group(3))) for m in re.finditer(r"BOSSACTS PERF ([ab]) n=\d+ p50=([0-9.]+) p95=([0-9.]+)", o)}
        if "a" in got and "b" in got:
            rows.append("| %s | %.2f | %.2f | %.2f | %.2f | %+.2f |" % (spec, got["a"][0], got["b"][0], got["a"][1], got["b"][1], got["a"][1] - got["b"][1]))
        else:
            rows.append("| %s | 没测到（%s） |  |  |  |  |" % (spec, "超时" if to else str(gr.script_errors(o, e)[:2])))
        print(rows[-1])
    open(os.path.join(OUT, "perf.md"), "w", encoding="utf-8").write("\n".join(rows) + "\n")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("before", "after", "video", "perf"):
        sys.exit(__doc__)
    extra = [a for a in sys.argv[2:] if a.startswith("--")]   # 透传给游戏，如 --shotstep=1 --bal=boss/acts_demo_len=4（激光收尾逐帧看）
    specs = [a for a in sys.argv[2:] if not a.startswith("--")] or SPECS
    os.makedirs(OUT, exist_ok=True)
    if sys.argv[1] == "video":
        video(specs)
    elif sys.argv[1] == "perf":
        perf(specs if sys.argv[2:] and specs != SPECS else ["izumik"])   # 协调人 10-25：只量最重的一个场景（伊祖米克：900 像素大环 + 子代），预算是兜底
    else:
        record(sys.argv[1], specs, extra)


if __name__ == "__main__":
    main()
