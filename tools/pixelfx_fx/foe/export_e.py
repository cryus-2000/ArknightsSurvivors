# -*- coding: utf-8 -*-
"""组 E 一键导出（docs/236）：按 targets_e.json 跑 tools/pixelfx_export.py，再把它打印的登记行整块写进 art.gd「组 E」块，
最后跑 asset_index（本地用，index.json 不提交）和 audit_e 自检。

    python tools/pixelfx_fx/foe/export_e.py [--lib <pixelfx 检出>] [--only 名字,...]
"""
import argparse, json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fixed_e import FIXED

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ART = os.path.join(ROOT, "game", "scripts", "art.gd")
HEAD = "\t# ---- pixelfx 组 E"
TAIL = "\t# ---- 组 E 止"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=os.path.join(ROOT.split(os.sep + ".claude" + os.sep)[0], "build", "pixelfx"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    tg = json.load(open(os.path.join(ROOT, "tools", "pixelfx_fx", "targets_e.json"), encoding="utf-8"))
    names = [k for k in tg if not k.startswith("_")]
    only = [n for n in a.only.split(",") if n] or names
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pixelfx_export.py"), "--lib", a.lib, "--only", ",".join(only)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    new = {}
    for ln in r.stdout.splitlines():
        m = re.match(r'("([^"]+)": \[[^\]]*\]),', ln)
        if m:
            new[m.group(2)] = m.group(1)
    s = open(ART, encoding="utf-8", newline="").read()
    i = s.index("\n", s.index(HEAD)) + 1
    j = s.index(TAIL)
    old = {}
    for ln in s[i:j].splitlines():
        m = re.match(r'\t("([^"]+)": \[[^\]]*\]),', ln)
        if m:
            old[m.group(2)] = m.group(1)
    if not a.only:
        old = {}   # 全量重导：只留本次导出的登记，并删掉不再导出的旧 fx_e_px_* / proj_e_px_* 文件（比如关了光晕的 _glow）
        fx = os.path.join(ROOT, "game", "art", "fx")
        for f in os.listdir(fx):
            base = re.sub(r"(@2x)?\.png(\.import)?$", "", f)
            if re.match(r"(fx|proj)_e_px_", f) and base not in new and base not in FIXED:   # fixed_e.py 出的固定格式件不归这里管
                os.remove(os.path.join(fx, f))
    old.update(new)
    for nm, sp in FIXED.items():   # 固定格式件（fixed_e.py）：帧数 = 代码写死的数量，fps 照原条（播放速度由代码决定）
        old[nm] = '"%s": [%d, %.1f]' % (nm, sp["frames"], sp["fps"])
        names.append(nm)
    keep = [k for k in old if re.sub(r"(_v\d+)?(_glow)?$", "", k) in names]   # 只留 targets_e 里还有的
    blk = "\t# 组 E 敌方 / Boss（docs/236；tools/pixelfx_fx/foe/export_e.py 按 targets_e.json 导出后整块重写，本体 / _glow / _v1 / _v2 同帧数 fps）\n"
    blk += "".join("\t%s,\n" % old[k] for k in keep)
    open(ART, "w", encoding="utf-8", newline="").write(s[:i] + blk + s[j:])
    print("导出 %d 条，组 E 块登记 %d 行" % (len(new), len(keep)))
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "asset_index.py")], capture_output=True)
    sys.exit(subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "audit_e.py")]).returncode)


if __name__ == "__main__":
    main()
