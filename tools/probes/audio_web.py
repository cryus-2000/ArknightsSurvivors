"""网页样本内存量测（docs/50 §40）：测量副本的 index.js 里把引擎的 GodotAudio.samples / 音频上下文挂到 window（__GAS / __GACTX），
再按 perf_web 的办法起页面跑 --audiofree（sfx.gd）或别的带 --audiomem 的场景，收 PF AUDIOFREE / PF AUDIOMEM 行。

  python tools/probes/audio_web.py --ref HEAD --tag x [--mobile] -- <游戏参数…>
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import perf_web as pw


def patch(d: str) -> None:
    p = os.path.join(d, "index.js")
    s = open(p, encoding="utf-8").read()
    if "window.__GAS" in s:
        return
    a = "GodotAudio.samples.set(params.id,sample);"
    assert a in s, "引擎 JS 里找不到 GodotAudio.samples.set（Godot 版本变了？）"
    s = s.replace(a, a + "window.__GAS=GodotAudio.samples;window.__GACTX=GodotAudio.ctx;", 1)
    open(p, "w", encoding="utf-8").write(s)


def main():
    argv = sys.argv[1:]
    game_args = []
    if "--" in argv:
        i = argv.index("--")
        argv, game_args = argv[:i], argv[i + 1:]
    ref = "HEAD"
    tag = "audio"
    mobile = "--mobile" in argv
    for i, a in enumerate(argv):
        if a == "--ref":
            ref = argv[i + 1]
        if a == "--tag":
            tag = argv[i + 1]
    d = pw.export(ref)
    patch(d)
    log = pw.run(ref, tag, game_args, 1500, 0, mobile, False, 3)
    for l in open(log, encoding="utf-8").read().splitlines():
        if l.startswith(("PF AUDIO", "SCRIPT ERROR")):
            print(l)


if __name__ == "__main__":
    main()
