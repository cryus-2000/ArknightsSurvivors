"""英文版界面截图（docs/276 §10）：tests/l10n_shots.tscn 中英各跑一遍，PNG 写到 --out。
走 tools/godot_runner（全机并发上限、只按自己的 PID 结束）；按 docs/256 放 GCP 上跑：
  python tools/gcp_render.py --branch claude/english-framework --job custom --name l10n-shots --cmd 'python3 tools/l10n/l10n_shots.py --out $MEDIA'
本机别直接跑（本机最多 1 个 Godot，截图一律上 GCP）。
"""
import argparse, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as gr  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--langs", default="en,zh")
    ap.add_argument("--extra", default="", help="附加游戏参数，空格分隔（如 --touch）")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    bad = 0
    for lang in a.langs.split(","):
        args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--resolution", "1280x720",
                "res://tests/l10n_shots.tscn", "--", "--lang=" + lang, "--balance", "--seed=1", "--op=mizuki",
                "--squad=skadi,kaltsit", "--shot_dir=" + a.out.replace(os.sep, "/")] + a.extra.split()
        o, e, to = gr.run_godot(args, 1200)
        open(os.path.join(a.out, "run_%s.log" % lang), "w", encoding="utf-8").write(o + "\n----\n" + e)
        errs = gr.script_errors(o, e)
        done = [l for l in o.splitlines() if l.startswith("L10N SHOTS")]
        print(lang, done, "errors:", errs[:5], "timeout" if to else "")
        bad += (1 if errs or to or not done else 0)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
