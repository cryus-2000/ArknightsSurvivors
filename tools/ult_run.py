"""终结技原型（docs/198）冒烟 / 计数：无头跑一局机器人，打印脚本错误、ULT 汇总行与结尾几行。
用法：python tools/ult_run.py <队长> <秒> [附加游戏参数…]
例：  python tools/ult_run.py texas 90 --bal=ult/e_mult=20 --squad=exusiai,lappland
附加参数原样传给游戏（--bal=键=值、--seed=、--squad= 等）；缺省 --seed=1 --bot=expert。退出码：有脚本错误 / 超时为 1。"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    op, secs = sys.argv[1], sys.argv[2]
    extra = sys.argv[3:]
    if not any(a.startswith("--seed=") for a in extra):
        extra.append("--seed=1")
    if not any(a.startswith("--bot=") for a in extra):
        extra.append("--bot=expert")
    args = [GR.find_godot(), "--headless", "--path", GAME, "--fixed-fps", "60", "--audio-driver", "Dummy", "--",
            "--balance", "--op=" + op, "--maxt=" + secs] + extra
    out, err, to = GR.run_godot(args, timeout=max(240, int(float(secs) * 3)))
    errs = GR.script_errors(out, err)
    for e in errs[:20]:
        print("ERR", e)
    for ln in out.splitlines():
        if ln.startswith("ULT") or "SCRIPT ERROR" in ln:
            print(ln[:1500])
        elif ln.startswith("BALANCE "):
            try:
                rec = json.loads(ln[8:])
                print("RESULT win=%s t=%s lv=%s kills=%s" % (rec.get("win"), rec.get("t"), rec.get("lv"), rec.get("kills")))
                print("ULTREC", json.dumps(rec.get("ult"), ensure_ascii=False))
            except ValueError:
                print(ln[:300])
    if to:
        print("TIMEOUT")
    tail = [ln for ln in (out + "\n" + err).splitlines() if ln.strip()][-6:]
    print("--- tail")
    for ln in tail:
        print(ln[:400])
    return 1 if errs or to else 0


if __name__ == "__main__":
    sys.exit(main())
