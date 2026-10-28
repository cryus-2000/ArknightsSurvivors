# -*- coding: utf-8 -*-
"""结算改版三个方向的录像（10-28 用户「结算页设计的不太好看，重新设计一下」）：tests/settle_style_rec 逐帧存图 → H.264 mp4（原色原速）。
每个方向一段：桌面 1280×720 胜利 + 失败，接手机横屏 1480×720（--touch）胜利 + 失败；各段左上角标注。录完即删帧目录。
另出 1/3 速版（--slow）。输出主仓库 build/settle_redesign/<方向>.mp4。

用法：python tools/probes/settle_style_rec.py [1 2 3] [--slow] [--shots]
  --shots：只存每段终态静帧到 build/settle_redesign/shots/（自查用）
"""
import os, sys, glob, shutil, subprocess
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GR.common_root(), "build", "settle_redesign")
NAMES = {"0": "现样", "1": "方向 A · 作战报告", "2": "方向 B · 潮汐航迹", "3": "方向 C · 编队合影"}
DEVS = [("desktop", "1280x720", []), ("phone", "1480x720", ["--touch"])]


def run(style, dev):
    name, res, extra = dev
    d = os.path.join(OUT, "raw_%s_%s" % (style, name))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    out, err, to = GR.run_godot([GR.find_godot(), "--path", GAME, "--resolution", res, "--fixed-fps", "30",
                                 "res://tests/settle_style_rec.tscn", "--", "--shotdir=" + d, "--settle_style=" + style] + extra, 300)
    n = len(glob.glob(os.path.join(d, "rec_*.png")))
    if n == 0 or to:
        print(style, name, "失败", (out + err)[-2000:])
    errs = [l for l in (out + err).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    if errs:
        print(style, name, "脚本报错：", "\n".join(errs[:10]))
    return d, n


def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", os.path.join(GAME, "fonts", "ui_fallback.otf")]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def compose(style, dirs, slow):
    import imageio_ffmpeg
    W, H = 1480, 720
    f = font(16)
    path = os.path.join(OUT, "settle_%s%s.mp4" % (style, "_slow" if slow else ""))
    fps = 10 if slow else 30
    proc = subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                             "-s", "%dx%d" % (W, H), "-r", str(fps), "-i", "-",
                             "-vf", "scale=out_color_matrix=bt709:out_range=tv", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
                             "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                             "-color_range", "tv", "-movflags", "+faststart", path], stdin=subprocess.PIPE)
    for dev, d in dirs:
        for p in sorted(glob.glob(os.path.join(d, "rec_*.png"))):
            im = Image.open(p).convert("RGB")
            canvas = Image.new("RGB", (W, H), (0, 0, 0))
            canvas.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
            dr = ImageDraw.Draw(canvas)
            label = "%s  ·  %s" % (NAMES[style], "桌面 16:9" if dev == "desktop" else "手机横屏（触屏）")
            dr.rectangle((0, 0, dr.textlength(label, font=f) + 16, 24), fill=(0, 0, 0))
            dr.text((8, 2), label, fill=(255, 220, 140), font=f)
            proc.stdin.write(canvas.tobytes())
    proc.stdin.close()
    proc.wait()
    print("写出", path, "%.1f MB" % (os.path.getsize(path) / 1048576))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    styles = args or ["1", "2", "3"]
    shots = "--shots" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    GR.ensure_imported(GAME)
    jobs = [(st, dv) for st in styles for dv in DEVS]
    with ThreadPoolExecutor(3) as ex:
        res = list(ex.map(lambda j: run(*j), jobs))
    for st in styles:
        dirs = [(dv[0], res[jobs.index((st, dv))][0]) for dv in DEVS]
        if shots:
            sd = os.path.join(OUT, "shots")
            os.makedirs(sd, exist_ok=True)
            for dev, d in dirs:
                for si, tag in [(0, "win"), (1, "dead")]:
                    fr = sorted(glob.glob(os.path.join(d, "rec_%d_*.png" % si)))
                    if not fr:
                        continue
                    for sub, i in [("", len(fr) - 1), ("_a", int(len(fr) * 0.25)), ("_b", int(len(fr) * 0.5))]:
                        shutil.copy(fr[i], os.path.join(sd, "s%s_%s_%s%s.png" % (st, dev, tag, sub)))
        else:
            compose(st, dirs, False)
            if "--slow" in sys.argv:
                compose(st, dirs, True)
        for _, d in dirs:
            shutil.rmtree(d, ignore_errors=True)   # 帧目录用完即删（10-27 口径）


if __name__ == "__main__":
    main()
