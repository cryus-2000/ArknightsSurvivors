"""ark_native 一条命令构建（docs/101 §4.7，Windows 桌面原型）：
  1. 工具链与 godot-cpp 按 native/VERSION 固定（E:/toolchains 下，或 --toolchains 指定目录；缺了就报错，不自动下载）
  2. 用本机 Godot 4.7.2 导出 extension_api.json / gdextension_interface.h / .json（godot-cpp 用 gdextension_dir 对齐引擎）
  3. scons 编 template_debug / template_release（llvm-mingw），产物进 game/bin/，再写 game/bin/ark_native.gdextension
  4. 跑一次 godot --import，让引擎登记这个扩展（.godot/extension_list.cfg）
game/bin/ 不入库、不进导出包（export_presets 的 exclude_filter 已排除 bin/*）；没有 dll 的机器自动走 GDScript 核心。
用法：python native/build_native.py [--toolchains E:/toolchains] [--target debug|release|both] [--jobs N]
"""
import argparse
from contextlib import chdir
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NATIVE = ROOT / "native"
GAME = ROOT / "game"
sys.path.insert(0, str(ROOT / "tools"))
import godot_runner as GR  # noqa: E402


def read_version():
    v = {}
    for line in (NATIVE / "VERSION").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, val = line.split("=", 1)
            v[k.strip()] = val.strip()
    return v


GDEXT = """[configuration]
entry_symbol = "ark_native_init"
compatibility_minimum = "4.7"
reloadable = false

[libraries]
windows.debug.x86_64 = "res://bin/ark_native.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "res://bin/ark_native.windows.template_release.x86_64.dll"
"""


def run_engine(args, timeout):
    out, err, timed_out = GR.run_godot([GR.find_godot(), "--headless", "--audio-driver", "Dummy"] + args, timeout)
    if timed_out or "ERROR:" in out or "ERROR:" in err:
        raise SystemExit("Godot 构建步骤失败%s\n%s\n%s" % ("（超时）" if timed_out else "", out, err))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--toolchains", default="E:/toolchains")
    ap.add_argument("--target", choices=["debug", "release", "both"], default="both")
    ap.add_argument("--jobs", type=int, default=max(2, min(8, (os.cpu_count() or 4) - 2)))
    a = ap.parse_args()
    v = read_version()
    tc = Path(a.toolchains)
    mingw = tc / v["llvm_mingw"]
    gcpp = tc / ("godot-cpp-" + v["godot_cpp"][:8])
    scons_dir = tc / "scons"
    for p, what in ((mingw / "bin" / "x86_64-w64-mingw32-clang++.exe", "llvm-mingw"), (gcpp / "SConstruct", "godot-cpp"), (scons_dir / "SCons", "scons")):
        if not p.exists():
            raise SystemExit("缺 %s：%s（按 native/VERSION 准备，见 docs/101 §4.7）" % (what, p))
    head = subprocess.run(["git", "-C", str(gcpp), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if head != v["godot_cpp"]:
        raise SystemExit("godot-cpp 提交不对：%s ≠ %s" % (head, v["godot_cpp"]))
    api = tc / ("godot-api-" + v["godot"])
    api.mkdir(parents=True, exist_ok=True)
    if not (api / "extension_api.json").exists() or not (api / "gdextension_interface.json").exists():
        with chdir(api):
            run_engine(["--dump-extension-api", "--dump-gdextension-interface", "--dump-gdextension-interface-json"], 300)
    env = dict(os.environ)
    env["GODOT_CPP_DIR"] = str(gcpp)
    env["PYTHONPATH"] = str(scons_dir) + os.pathsep + env.get("PYTHONPATH", "")
    env["PATH"] = str(mingw / "bin") + os.pathsep + env.get("PATH", "")
    targets = ["template_debug", "template_release"] if a.target == "both" else ["template_" + a.target]
    for t in targets:
        cmd = [sys.executable, "-c", "import SCons.Script; SCons.Script.main()", "-C", str(NATIVE), "-j%d" % a.jobs,
               "platform=windows", "arch=x86_64", "target=" + t, "use_mingw=yes", "use_llvm=yes", "mingw_prefix=" + str(mingw).replace("\\", "/"),
               "gdextension_dir=" + str(api).replace("\\", "/"), "precision=single", "use_static_cpp=yes"]
        print("scons", t, flush=True)
        subprocess.run(cmd, env=env, check=True)
    (GAME / "bin").mkdir(exist_ok=True)
    (GAME / "bin" / "ark_native.gdextension").write_text(GDEXT, encoding="utf-8")
    print("import（登记扩展）", flush=True)
    run_engine(["--path", str(GAME), "--import"], 900)
    print("OK", [p.name for p in (GAME / "bin").iterdir()])


if __name__ == "__main__":
    main()
