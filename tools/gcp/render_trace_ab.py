"""GCP 出图任务 trace_ab 的执行体（tools/gcp_render.py 经 metadata 送到虚拟机 /work/render_trace_ab.py，不依赖被测提交里的工具）。
环境变量：TRACE_WINDOWED=1（画画面跑，画面代码也执行；缺省 --headless）、TRACE_CASES（队长:种子:秒数,…）、TRACE_A / TRACE_B（两组附加参数）、TRACE_EXTRA（两组共用）、GODOT、OUT、GODOT_MAX_PROCS。"""
import os, shlex, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

OUT = os.environ["OUT"]
GODOT = os.environ["GODOT"]
cases = [c.split(":") for c in os.environ["TRACE_CASES"].split(",") if c.strip()]
grp = {"A": shlex.split(os.environ.get("TRACE_A", "")), "B": shlex.split(os.environ.get("TRACE_B", ""))}
extra = shlex.split(os.environ.get("TRACE_EXTRA", ""))
os.makedirs(os.path.join(OUT, "trace"), exist_ok=True)
sys.path.insert(0, "tools")
try:
    from godot_runner import TEST_SETTINGS as SETTINGS   # 被测提交里的那份（与本机测试同一套设置）
except Exception:
    SETTINGS = "[game]\ndmg_numbers=true\n"


def run(job):
    (op, seed, secs), g = job
    ud = tempfile.mkdtemp(prefix="ark_")
    os.makedirs(os.path.join(ud, "ArknightsSurvivors"), exist_ok=True)
    open(os.path.join(ud, "ArknightsSurvivors", "settings.cfg"), "w", encoding="utf-8").write(SETTINGS)   # 同本机 godot_runner.TEST_SETTINGS
    env = dict(os.environ, XDG_DATA_HOME=ud, APPDATA=ud)
    args = [GODOT] + ([] if os.environ.get("TRACE_WINDOWED") == "1" else ["--headless"]) + ["--audio-driver", "Dummy", "--path", "game", "--", "--balance", "--seed=" + seed, "--op=" + op,
            "--maxt=" + secs, "--trace=1", "--bot=expert"] + extra + grp[g]
    p = subprocess.run(args, capture_output=True, text=True, errors="replace", env=env, timeout=600 + int(secs) * 3)
    lines = [l for l in p.stdout.splitlines() if l.startswith("TRACE ")]
    errs = [l for l in (p.stdout + p.stderr).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    open(os.path.join(OUT, "trace", "%s_s%s_%s.txt" % (op, seed, g)), "w", encoding="utf-8").write(
        "# " + " ".join(args[1:]) + "\n" + "\n".join(lines) + "\n" + "\n".join("# " + e for e in errs[:5]) + "\n")
    return lines, errs


jobs = [(c, g) for c in cases for g in ("A", "B")]
with ThreadPoolExecutor(max(1, int(os.environ.get("GODOT_MAX_PROCS", "4")))) as ex:
    res = list(ex.map(run, jobs))
rep = ["# 同种子 TRACE 对比", "", "A：`%s`　B：`%s`　共用：`%s`" % (" ".join(grp["A"]), " ".join(grp["B"]), " ".join(extra)), "",
       "| 局 | A 行数 | B 行数 | 结果 | 第一处差异 |", "|---|---|---|---|---|"]
ok = True
for i, c in enumerate(cases):
    (la, ea), (lb, eb) = res[2 * i], res[2 * i + 1]
    d = next((k for k, (x, y) in enumerate(zip(la, lb)) if x != y), None)
    same = d is None and len(la) == len(lb) and len(la) >= 3 and not ea and not eb
    ok &= same
    first = "" if d is None else "第 %d 行：A `%s` / B `%s`" % (d + 1, la[d][:120], lb[d][:120])
    if ea or eb:
        first = "脚本报错：" + "；".join((ea + eb)[:2])
    rep.append("| %s 种子 %s %s 秒 | %d | %d | %s | %s |" % (c[0], c[1], c[2], len(la), len(lb), "逐行一致" if same else "**有差异**", first))
open(os.path.join(OUT, "trace_ab.md"), "w", encoding="utf-8").write("\n".join(rep) + "\n")
print("\n".join(rep))
sys.exit(0 if ok else 1)
