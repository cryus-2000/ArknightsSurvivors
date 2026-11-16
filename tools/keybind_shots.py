"""键位设置截图（docs/350）：窗口模式屏外跑 tests/keybind_test.tscn --kbshot，各语言截键鼠页 / 手柄页 / 冲突框 / 改键后的操作说明页。

  python tools/keybind_shots.py zh en ja ko     # 输出 build/kb/shots/*.png
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as G

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build", "kb", "shots").replace(os.sep, "/")
for lang in sys.argv[1:] or ["zh", "en"]:
    o, e, to = G.run_godot([G.find_godot(), "--path", os.path.join(ROOT, "game"), "res://tests/keybind_test.tscn",
                            "--", "--regression", "--seed=1", "--kbshot=" + OUT, "--lang=" + lang], 240)
    print(lang, "超时" if to else "", [l for l in o.splitlines() if "KEYBIND" in l])
