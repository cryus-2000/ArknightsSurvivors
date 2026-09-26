"""等价性 A/B（docs/36 §7.5）：预期逐局完全相同的改动（重构、换读法），两边在同一台云端机器上跑同一批局，这里逐局逐字段比较。
用法：python tools/cloud/eq_compare.py <前缀>
  读 origin 上所有 cloud-results/<前缀>-* 分支里的 build/cloud/**.json，tag 以 _base 结尾的算基准、其余算新版；
  按（开局, seed, 机器人, 难度）配对比较整局记录（data），打印每一局第一个不同的字段，最后给出 相同 / 不同 / 缺一边 的局数。
云端命令模板见 docs/36 §7.5（两边 tag 分别以 _base / _new 结尾）。"""
import os, sys, json, subprocess
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PFX = sys.argv[1] if len(sys.argv) > 1 else "gpeq"
def git(*a):
    return subprocess.run(["git"] + list(a), cwd=REPO, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
brs = [l.split("refs/heads/")[1] for l in git("ls-remote", "--heads", "origin", "cloud-results/%s-*" % PFX).splitlines() if l.strip()]
side = {"base": {}, "new": {}}
for br in sorted(brs):
    git("fetch", "-q", "origin", br)
    for f in git("ls-tree", "-r", "--name-only", "origin/" + br).split():
        if not (f.startswith("build/cloud/") and f.endswith(".json")):
            continue
        d = json.loads(git("show", "origin/%s:%s" % (br, f)) or "{}")
        if "records" not in d:
            continue
        s = "base" if d["args"]["tag"].endswith("_base") else "new"
        for r in d["records"]:
            side[s][(tuple(r["squad"]), r["seed"], r.get("bot"), r.get("diff"))] = r
def first_diff(a, b, path=""):
    if type(a) != type(b):
        return path or "/", a, b
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                return path + "/" + k, a.get(k, "<缺>"), b.get(k, "<缺>")
            x = first_diff(a[k], b[k], path + "/" + k)
            if x: return x
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return path + "(长度)", len(a), len(b)
        for i, (x, y) in enumerate(zip(a, b)):
            z = first_diff(x, y, "%s[%d]" % (path, i))
            if z: return z
        return None
    return None if a == b else (path, a, b)
keys = sorted(set(side["base"]) | set(side["new"]))
same = diff = miss = 0
for k in keys:
    a, b = side["base"].get(k), side["new"].get(k)
    if a is None or b is None:
        miss += 1; print("缺一边", k); continue
    if a.get("script_errors") or b.get("script_errors"):
        print("脚本错误", k, a.get("first_error"), b.get("first_error"))
    x = first_diff(a.get("data"), b.get("data"))
    if x:
        diff += 1; print("不同", k, "字段", x[0], "base=%s new=%s" % (str(x[1])[:80], str(x[2])[:80]))
    else:
        same += 1
print("分支", brs, "\n共 %d 局：相同 %d，不同 %d，缺一边 %d" % (len(keys), same, diff, miss))
