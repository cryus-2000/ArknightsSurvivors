"""伊莎玛拉连段实机录像（docs/170）：六组连段各 16 秒，正式 AI，窗口放屏外 / 副屏、静音。

python tools/probes/ishar_combo_preview.py --tag v1 [--quality low]
输出 build/boss_ishar/<tag>/：每组 mp4 + 原速 GIF、整段 mp4、capture.json；编码后删除 PNG 帧。已有帧不覆盖。
"""
import argparse
import hashlib
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
SEGMENTS = 6
SOURCES = ["game/scripts/enemies/bosses/ishar.gd", "game/scripts/enemies/bosses/ishar_combos.gd", "game/tests/ishar_combo_preview.gd",
           "game/scripts/enemies/final_attacks.gd", "game/scripts/render/boss_attack_draw.gd", "game/scripts/render/final_attack_grains.gd",
           "game/scripts/render/world.gd", "game/scripts/render/telegraph_draw.gd", "game/data/enemies.json"]


def ffmpeg(*args):
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--quality", choices=["high", "low"], default="high")
    ap.add_argument("--encode-only", action="store_true")
    ap.add_argument("--slow", action="store_true", help="另出 1/3 速 GIF")
    ap.add_argument("--keep-frames", action="store_true", help="编码后保留 PNG 帧（缺省删除）")
    a = ap.parse_args()
    base = (ROOT / "build/boss_ishar" / a.tag).resolve()
    frames = base / ("frames_" + a.quality)
    if not a.encode_only:
        if frames.exists() and list(frames.glob("frame_*.png")):
            raise SystemExit("换一个 --tag，已有帧：" + str(frames))
        frames.mkdir(parents=True, exist_ok=True)
        hashes = {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in SOURCES if (ROOT / n).exists()}
        (base / "source_hashes.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
        cmd = [runner.find_godot(), "--path", str(ROOT / "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30",
               "res://tests/ishar_combo_preview.tscn", "--", "--seed=271027", "--quality=" + a.quality, "--shotdir=" + frames.as_posix()]
        out, err, timed_out = runner.run_godot(cmd, 900)
        (base / ("run_%s.log" % a.quality)).write_text(out + "\n" + err, encoding="utf-8")
        if timed_out or runner.script_errors(out, err) or "FX_PREVIEW_DONE" not in out:
            raise SystemExit("录制失败：" + (out + err)[-3000:])
    paths = sorted(frames.glob("frame_*.png"))
    per = len(paths) // SEGMENTS
    log = (base / ("run_%s.log" % a.quality)).read_text(encoding="utf-8")
    metrics = [json.loads(l.removeprefix("FX_PREVIEW_METRICS ")) for l in log.splitlines() if l.startswith("FX_PREVIEW_METRICS ")]
    suffix = "" if a.quality == "high" else "_low"
    ffmpeg("-framerate", str(FPS), "-i", str(frames / "frame_%05d.png"), "-c:v", "libx264", "-crf", "18", "-preset", "fast",
           "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(base / ("ishar_combos_all%s.mp4" % suffix)))
    for s in range(SEGMENTS):
        name = metrics[s]["move"] if s < len(metrics) else str(s)
        ffmpeg("-framerate", str(FPS), "-start_number", str(s * per), "-i", str(frames / "frame_%05d.png"), "-frames:v", str(per),
               "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
               str(base / ("%d_%s%s.mp4" % (s + 1, name, suffix))))
    # 给用户看的一律 GIF（协调人 10-27）：原速，8 fps、宽 480、96 色（6 段各约 10.5 MB）；--slow 另出 1/3 速；单个 ≤25 MB
    pal = "split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
    for s in range(SEGMENTS):
        name = metrics[s]["move"] if s < len(metrics) else str(s)
        for tag, pts in [("", "")] + ([("_slow3", "setpts=3*PTS,")] if a.slow else []):
            gif = base / ("%d_%s%s%s.gif" % (s + 1, name, suffix, tag))
            ffmpeg("-framerate", str(FPS), "-start_number", str(s * per), "-i", str(frames / "frame_%05d.png"), "-frames:v", str(per),
                   "-filter_complex", pts + "fps=8,scale=480:-2:flags=lanczos," + pal, "-loop", "0", str(gif))
            if gif.stat().st_size > 25 * 1024 * 1024:
                print("WARN gif > 25MB", gif)
    if not a.keep_frames:
        for f in paths:
            f.unlink()
        frames.rmdir()
    (base / ("capture%s.json" % suffix)).write_text(json.dumps({"frames": len(paths), "fps": FPS, "segments": SEGMENTS, "segment_seconds": SEG,
        "metrics": metrics,
        "simulation": "正式 AI + 弹幕 + 预警；每段只强制起手一组连段；第 7 秒击破一只连线海嗣；玩家无敌、沿椭圆连续移动 110px/s"},
        ensure_ascii=False, indent=2), encoding="utf-8")
    print("OK", base, len(paths))


if __name__ == "__main__":
    main()
