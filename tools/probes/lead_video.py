# -*- coding: utf-8 -*-
"""突出队长四个变体的 2×2 并排视频（docs/139 §11；用户在手机上看）。

先用 look_nausea.py 录帧：
    python tools/probes/look_nausea.py rec --seg vid_late --squad wisadel,siege,mizuki,kaltsit --only lead_now,leadA,leadB,leadC
    python tools/probes/look_nausea.py rec --seg vid_boss --squad wisadel,siege,mizuki,kaltsit --only lead_now,leadA,leadB,leadC
再：python tools/probes/lead_video.py → build/look_nausea/lead_compare_2x2.mp4（1280×720、30 fps、H.264、faststart）
第二版：录 --only emph1,emph2 后 python tools/probes/lead_video.py --emph → build/look_nausea/lead_emph_late.mp4 / lead_emph_boss.mp4
"""
import glob, os, subprocess, sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import godot_runner as GR  # noqa: E402

OUT = os.path.join(GR.common_root(), "build", "look_nausea")
VARS = [("lead_now", "现状"), ("leadA", "A  命中角标 + 数字主次"), ("leadB", "B  A + 队长层级 + 方向弧"), ("leadC", "C  数字主次 + 层级 + 方向弧")]
SEGS = [("vid_late", "9:05 后期满屏 · 队长维什戴尔"), ("vid_boss", "10:12 最终 Boss 在场 · 队长维什戴尔")]
W, H, FPS = 1280, 720, 30


def font(sz):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", sz)
    except OSError:
        return ImageFont.load_default()


## 第二版（用户 10-25「队长明不明显没看太出来」）：render/lead_emph 中 / 强两档，三格放大到队长附近（1.5 倍），第四格强档整屏
EMPH = [("lead_now", "现状（放大）", True), ("emph1", "中档：队长提亮 + 大数字 + 角标（放大）", True),
        ("emph2", "强档：+ 琥珀专属色 + 方向弧（放大）", True), ("emph2", "强档 · 整屏", False)]
ZW, ZH = 427, 240   # 放大取景（以队长为中心，镜头跟队长，所以就是屏幕中心偏上一点）


def emph(path_name, segs):
    import imageio_ffmpeg
    path = os.path.join(OUT, path_name)
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
           "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p", "-movflags", "+faststart", path]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    f_lab, f_title = font(20), font(40)
    for seg, title in segs:
        card = Image.new("RGB", (W, H), (14, 16, 20))
        d = ImageDraw.Draw(card)
        d.text((W // 2, H // 2 - 40), title, fill=(240, 240, 240), font=f_title, anchor="mm")
        d.text((W // 2, H // 2 + 20), "左上 现状 · 右上 中档 · 左下 强档 · 右下 强档整屏", fill=(170, 175, 185), font=f_lab, anchor="mm")
        for _ in range(FPS):
            p.stdin.write(card.tobytes())
        lists = [sorted(glob.glob(os.path.join(OUT, seg, v, "rec_*.png"))) for v, _, _ in EMPH]
        n = min(len(x) for x in lists)
        for i in range(n):
            g = Image.new("RGB", (W, H))
            for k, (v, lab, zoom) in enumerate(EMPH):
                im = Image.open(lists[k][i]).convert("RGB")
                if zoom:
                    cx, cy = 640, 330
                    im = im.crop((cx - ZW // 2, cy - ZH // 2, cx + ZW // 2, cy + ZH // 2)).resize((W // 2, H // 2), Image.NEAREST)
                else:
                    im = im.resize((W // 2, H // 2), Image.LANCZOS)
                d = ImageDraw.Draw(im)
                tw = int(d.textlength(lab, font=f_lab)) + 16
                d.rectangle([0, 0, tw, 28], fill=(0, 0, 0))
                d.text((8, 2), lab, fill=(255, 220, 90), font=f_lab)
                g.paste(im, ((k % 2) * (W // 2), (k // 2) * (H // 2)))
            p.stdin.write(g.tobytes())
        print(seg, n, "帧")
    p.stdin.close()
    p.wait()
    print(path, "%.1f MB" % (os.path.getsize(path) / 1048576.0))


def main():
    if "--emph" in sys.argv:
        for seg, title in SEGS:   # 两段合一超过 20 MB（手机发送上限），按段各出一个文件
            emph("lead_emph_%s.mp4" % seg.replace("vid_", ""), [(seg, title)])
        return
    import imageio_ffmpeg
    path = os.path.join(OUT, "lead_compare_2x2.mp4")
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
           "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p", "-movflags", "+faststart", path]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    f_lab, f_title = font(22), font(40)
    for seg, title in SEGS:
        card = Image.new("RGB", (W, H), (14, 16, 20))
        d = ImageDraw.Draw(card)
        d.text((W // 2, H // 2 - 40), title, fill=(240, 240, 240), font=f_title, anchor="mm")
        d.text((W // 2, H // 2 + 20), "左上 现状 · 右上 A · 左下 B · 右下 C", fill=(170, 175, 185), font=f_lab, anchor="mm")
        for _ in range(FPS):
            p.stdin.write(card.tobytes())
        lists = [sorted(glob.glob(os.path.join(OUT, seg, v, "rec_*.png"))) for v, _ in VARS]
        n = min(len(x) for x in lists)
        for i in range(n):
            g = Image.new("RGB", (W, H))
            for k, (v, lab) in enumerate(VARS):
                im = Image.open(lists[k][i]).convert("RGB").resize((W // 2, H // 2), Image.LANCZOS)
                d = ImageDraw.Draw(im)
                d.rectangle([0, 0, 330, 30], fill=(0, 0, 0))
                d.text((8, 2), lab, fill=(255, 220, 90), font=f_lab)
                g.paste(im, ((k % 2) * (W // 2), (k // 2) * (H // 2)))
            p.stdin.write(g.tobytes())
        print(seg, n, "帧")
    p.stdin.close()
    p.wait()
    print(path, "%.1f MB" % (os.path.getsize(path) / 1048576.0))


if __name__ == "__main__":
    main()
