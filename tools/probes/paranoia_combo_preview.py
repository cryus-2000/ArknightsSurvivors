"""偏执泡影连携攻势录像（docs/170）：每组连段 16 秒，起手后走正式 AI；输出到 build/boss_paranoia/<tag>/。

python tools/probes/paranoia_combo_preview.py --tag cards_v1 [--quality high|low] [--encode-only]
产物：<序号>_<连段>.gif（每组原速，10 fps、宽 560）、all_combos.mp4（连播）、capture.json（每段事件、弹数峰值、帧时）；PNG 帧用完即删。
--timing：只测帧时（窗口在屏幕外、不截图），结果写 timing_<quality>.json。
窗口由 godot_runner 挪到副屏 / 屏幕外、静音；不覆盖已有帧。
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import godot_runner as runner

FPS = 15
SEG = 16.0


def ffmpeg(*args):
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


GIF_FILTER = "fps=10,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"


def encode(folder, out, cards):
    """每组一个原速 GIF（10 fps、宽 560）+ 全部连播 mp4；用完删掉 PNG 帧（用户 10-27 只看 gif）"""
    paths = sorted(folder.glob("frame_*.png"))
    per = int(SEG * FPS)
    ffmpeg("-framerate", str(FPS), "-i", str(folder / "frame_%05d.png"), "-c:v", "libx264", "-crf", "20", "-preset", "fast",
           "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out / "all_combos.mp4"))
    for i, c in enumerate(cards):
        ffmpeg("-framerate", str(FPS), "-start_number", str(i * per), "-i", str(folder / "frame_%05d.png"), "-frames:v", str(per),
               "-filter_complex", GIF_FILTER, "-loop", "0", str(out / ("%d_%s.gif" % (i + 1, c))))
    n = len(paths)
    for p in paths:
        p.unlink()
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--quality", choices=["high", "low"], default="high")
    ap.add_argument("--encode-only", action="store_true")
    ap.add_argument("--timing", action="store_true")
    a = ap.parse_args()
    if a.timing:
        out = (ROOT / "build/boss_paranoia" / a.tag).resolve()
        out.mkdir(parents=True, exist_ok=True)
        cmd = [runner.find_godot(), "--path", str(ROOT / "game"), "--audio-driver", "Dummy", "--resolution", "1280x720",
               "res://tests/paranoia_combo_preview.tscn", "--", "--pc-check", "--skin-ab", "--quality=" + a.quality]
        o, e, to = runner.run_godot(cmd, 900)
        rows = [json.loads(l.removeprefix("FX_PREVIEW_METRICS ")) for l in o.splitlines() if l.startswith("FX_PREVIEW_METRICS ")]
        res = [{"combo": r["combo"], "bullet_peak": r["bullet_peak"], **r["timing"]} for r in rows]
        (out / ("timing_" + a.quality + ".json")).write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
        print(json.dumps(res, ensure_ascii=False))
        return
    out = (ROOT / "build/boss_paranoia" / a.tag).resolve()
    out.mkdir(parents=True, exist_ok=True)
    folder = out / ("frames_" + a.quality)
    if not a.encode_only:
        if folder.exists() and list(folder.glob("frame_*.png")):
            raise SystemExit("换一个 --tag，已有帧不覆盖: " + str(folder))
        folder.mkdir(exist_ok=True)
        cmd = [runner.find_godot(), "--path", str(ROOT / "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30",
               "res://tests/paranoia_combo_preview.tscn", "--", "--quality=" + a.quality, "--shotdir=" + folder.as_posix()]
        o, e, to = runner.run_godot(cmd, 900)
        (folder / "run.log").write_text(o + "\n" + e, encoding="utf-8")
        if to or runner.script_errors(o, e) or "FX_PREVIEW_DONE" not in o:
            raise SystemExit("录像失败: " + str(folder / "run.log") + "\n" + (o + e)[-3000:])
    log = (folder / "run.log").read_text(encoding="utf-8")
    metrics = [json.loads(l.removeprefix("FX_PREVIEW_METRICS ")) for l in log.splitlines() if l.startswith("FX_PREVIEW_METRICS ")]
    cards = [m["combo"] for m in metrics]
    n = encode(folder, out, cards)
    (out / "capture.json").write_text(json.dumps({"quality": a.quality, "frames": n, "fps": FPS, "seconds_per_combo": SEG, "combos": metrics},
                                                 ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({"out": str(out), "frames": n, "combos": cards}, ensure_ascii=False))


if __name__ == "__main__":
    main()
