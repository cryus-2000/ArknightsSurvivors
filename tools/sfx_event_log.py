#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""跑一局记下每个音效播放请求（sfx.gd --sfxlog），给本机离线混音对照新旧音效用（docs/255 §7，流明攻击音效）。

不出声音：Godot 照常静音（--audio-driver Dummy）；--sfxlog 每次 Sfx.play 请求打一行 SFXLOG <引擎帧> <音名> <dB> <音高> <音高随机>，
同时开 fx/recipe_log 打 FXRLOG（含游戏时间），用来把引擎帧换成游戏时间。Godot 只经 godot_runner.run_godot 启动。

用法：python tools/sfx_event_log.py --out <目录> [--seed 11 --maxt 492 --extra "--op=texas --squad=lumen"]
输出：<目录>/sfx_events_<种子>.log（只留 SFXLOG / FXRLOG / TRACE 行）
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--maxt", type=int, default=492)
    ap.add_argument("--extra", default="--op=texas --squad=lumen --bal=growth/late_shape=1 --bal=fx/px_plane=1")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30", "--",
            "--balance", "--nodeath", "--trace=1", "--seed=%d" % a.seed, "--maxt=%d" % a.maxt, "--sfxlog", "--bal=fx/recipe_log=1"] + a.extra.split()
    out, err, to = GR.run_godot(args, 5400)
    keep = [l for l in (out or "").splitlines() if l.startswith(("SFXLOG", "SFXOP", "FXRLOG", "TRACE"))]
    p = os.path.join(a.out, "sfx_events_%d.log" % a.seed)
    open(p, "w", encoding="utf-8").write("\n".join(keep) + "\n")
    print(p, len(keep), "行", "SCRIPT ERROR:", len(GR.script_errors(out, err)), "超时" if to else "")


if __name__ == "__main__":
    main()
