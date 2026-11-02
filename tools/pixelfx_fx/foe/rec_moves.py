# -*- coding: utf-8 -*-
"""逐招前后对照录制（docs/236）：--bossmoves=<Boss> --bossonly=<招>,… --shotstep=1（固定 30 帧、每帧截图、同 seed），
改前用 build/_fx_before/game（git worktree add --detach build/_fx_before <提交>，拷导入缓存），改后用本工作树 game。
截图进 build/foe_fx/<before|after>/<tag>/，之后 compare_video.py 拼片。走 godot_runner（副屏 / 屏幕外、静音、全机并发上限）。

    python tools/pixelfx_fx/foe/rec_moves.py carmen:炮身砸击,炮身砸击 immortal:迸发,迸发
"""
import os, shutil, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr

OUT = os.path.join(ROOT, "build", "foe_fx")
GAMES = {"before": os.path.join(ROOT, "build", "_fx_before", "game"), "after": os.path.join(ROOT, "game")}


def main():
    for item in sys.argv[1:]:
        spec, moves = item.split(":")
        tag = spec.replace("+", "_")
        for which, gd in GAMES.items():
            out = os.path.join(OUT, which, tag)
            shutil.rmtree(out, ignore_errors=True)
            os.makedirs(out, exist_ok=True)
            args = [gr.find_godot(), "--path", gd, "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
                    "--autotest", "--seed=1", "--op=mizuki", "--bossmoves=" + spec, "--bossonly=" + moves, "--shotstep=1",
                    "--shotdir=" + out.replace(os.sep, "/")]
            o, e, to = gr.run_godot(args, 600)
            open(os.path.join(out, "run.log"), "w", encoding="utf-8").write(o + "\n----\n" + e)
            n = len([f for f in os.listdir(out) if f.startswith("shot_bmframe_")])
            print(which, spec, "帧", n, "超时" if to else "", gr.script_errors(o, e)[:3],
                  [ln for ln in o.splitlines() if ln.startswith("BOSSMOVES")][:6], flush=True)


if __name__ == "__main__":
    main()
