# -*- coding: utf-8 -*-
"""一条命令出齐同一提交的发布物（docs/33 §双版本）：对外包 + 对内包 + 网页版，逐个验证，最后写汇总。

用法（仓库根目录）：
    python tools/release_all.py --ref <冻结提交>          # 对外 + 对内 + 网页
    python tools/release_all.py --ref <冻结提交> --no-web # 只出两个 Windows 包

顺序固定、串行：export_build.py 与 verify_encrypted_game.py 共用 build/_export/（验证要读刚导出的那份打包源码），
所以每出一个包立刻验证，再出下一个。任何一步失败就中止，不会留下「只有一个包」却报成功的结果。
不推送、不上传：产物都在本地 build/ 下，发布前由用户确认（docs/33 清单第 6 条）。

产物：
    build/release/方舟幸存者_Public_Encrypted_<日期>_<提交>.zip
    build/release/方舟幸存者_Internal_EA_Encrypted_<日期>_<提交>.zip
    build/web/                                  网页版（分片 + 加载器）
    build/release/release_<提交>.json           汇总：两个 zip 的路径 / 大小 / sha256、两份验证结果、网页最大单文件
"""
import argparse, glob, hashlib, json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
STAGED_PKG = os.path.join(ROOT, "build", "_export", "方舟幸存者")
OUT = os.path.join(ROOT, "build", "release")
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")


def step(title, cmd):
    print("\n== %s ==\n> %s" % (title, " ".join(cmd)), flush=True)
    p = subprocess.run(cmd, cwd=ROOT, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    print("\n".join(p.stdout.splitlines()[-12:]), flush=True)
    if p.returncode != 0:
        sys.exit("失败：%s（退出码 %d），已中止；前面已出的包不算发布物" % (title, p.returncode))
    return p.stdout


def newest_zip(label, commit):
    found = sorted(glob.glob(os.path.join(OUT, "*%s_*_%s.zip" % (label, commit))), key=os.path.getmtime)
    if not found:
        sys.exit("没找到 %s 的 zip（提交 %s）" % (label, commit))
    return found[-1]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def one_package(kind, label, extra, commit):
    step("导出%s包" % kind, [sys.executable, os.path.join(TOOLS, "export_build.py"), "--ref", commit] + extra)
    zpath = newest_zip(label, commit)
    step("验证%s包" % kind, [sys.executable, os.path.join(TOOLS, "verify_encrypted_game.py"), "--package", STAGED_PKG, "--zip", zpath])
    audience = "internal" if "--ea" in extra else "public"
    report = os.path.join(ROOT, "build", "encrypted_game_verification_%s_%s.json" % (audience, commit))
    result = json.load(open(report, encoding="utf-8"))
    if result.get("failures") or result.get("audience") != audience or result.get("commit") != commit:
        sys.exit("%s包验证结果不对：%s" % (kind, report))
    return {"zip": zpath, "mb": round(os.path.getsize(zpath) / 1048576, 1), "sha256": sha256(zpath), "verify": report,
            "user_dir": result.get("user_dir"), "packed_png": result.get("packed_png_count"), "audio": result.get("audio_count")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True, help="冻结提交（两个包与网页版都从它出）")
    ap.add_argument("--no-web", action="store_true")
    a = ap.parse_args()
    commit = subprocess.run(["git", "rev-parse", "--short", a.ref], cwd=ROOT, stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    summary = {"commit": commit}
    summary["public"] = one_package("对外", "_Public_Encrypted", [], commit)
    summary["internal"] = one_package("对内", "_Internal_EA_Encrypted", ["--ea"], commit)
    if not a.no_web:
        out = step("导出网页版", [sys.executable, os.path.join(TOOLS, "export_web.py"), "--ref", commit])
        last = [l for l in out.splitlines() if l.startswith("完成：")]
        summary["web"] = {"dir": os.path.join(ROOT, "build", "web"), "result": last[-1] if last else ""}
    path = os.path.join(OUT, "release_%s.json" % commit)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=1)
    print("\n全部完成（同一提交 %s）。汇总：%s" % (commit, path))
    for k in ("public", "internal"):
        print("  %-8s %s（%.1f MB，存档目录 %s）" % (k, summary[k]["zip"], summary[k]["mb"], summary[k]["user_dir"]))
    if "web" in summary:
        print("  web      %s" % summary["web"]["result"])


if __name__ == "__main__":
    main()
