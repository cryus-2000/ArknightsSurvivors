# -*- coding: utf-8 -*-
"""一条命令出齐同一提交的发布物（docs/33 §双版本）：对外包 + 对内包 + 网页版，逐个验证，最后写汇总。

用法（仓库根目录）：
    python tools/release_all.py --ref <冻结提交>                 # 对外 + 对内 + 对外网页 + 对内网页
    python tools/release_all.py --ref <冻结提交> --no-web        # 只出两个 Windows 包
    python tools/release_all.py --ref <提交> --only internal     # 只出一份：public / internal / web / web_internal

顺序固定、串行：export_build.py 与 verify_encrypted_game.py 共用 build/_export/（验证要读刚导出的那份打包源码），
所以每出一个包立刻验证，再出下一个。任何一步失败就中止，不会留下「只有一个包」却报成功的结果。
不推送、不上传：产物都在本地 build/ 下，发布前由用户确认（docs/33 清单第 6 条）。

产物统一收进 build/release/final_<提交>/：
    方舟幸存者_Public_Encrypted_<日期>_<提交>.zip
    方舟幸存者_Internal_EA_Encrypted_<日期>_<提交>.zip
    internal/                                   对内包的解压目录（验证过的那份），主目录「启动对内测试版.bat」启动最新的一份
    web/                                        对外网页版（分片 + 加载器）
    web_internal/                               对内网页版（演练开、全部解锁；要放在和对外版不同的域名 / 端口，网页存档按网站源隔离）
    web_verification_<public|internal>_<提交>.json  网页包验证（tools/verify_web_build.py）
    release_<提交>.json                         汇总：zip 的路径 / 大小 / sha256、验证结果、网页最大单文件
    encrypted_*_<提交>.json / .log              验证报告与各次启动日志
"""
import argparse, glob, hashlib, json, os, shutil, subprocess, sys

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


def one_package(kind, label, extra, commit, final):
    step("导出%s包" % kind, [sys.executable, os.path.join(TOOLS, "export_build.py"), "--ref", commit] + extra)
    zpath = newest_zip(label, commit)
    step("验证%s包" % kind, [sys.executable, os.path.join(TOOLS, "verify_encrypted_game.py"), "--package", STAGED_PKG, "--zip", zpath])
    audience = "internal" if "--ea" in extra else "public"
    report = os.path.join(ROOT, "build", "encrypted_game_verification_%s_%s.json" % (audience, commit))
    result = json.load(open(report, encoding="utf-8"))
    if result.get("failures") or result.get("audience") != audience or result.get("commit") != commit:
        sys.exit("%s包验证结果不对：%s" % (kind, report))
    # 收进 final_<提交>/：zip、验证报告与日志；对内包再留一份验证过的解压目录（一键启动用）
    dst = os.path.join(final, os.path.basename(zpath))
    shutil.move(zpath, dst)
    for f in glob.glob(os.path.join(ROOT, "build", "encrypted_*%s*_%s.*" % (audience, commit))):
        shutil.copy2(f, final)
    if audience == "internal":
        unpacked = os.path.join(final, "internal")
        shutil.rmtree(unpacked, ignore_errors=True)
        shutil.copytree(STAGED_PKG, unpacked)
    return {"zip": dst, "mb": round(os.path.getsize(dst) / 1048576, 1), "sha256": sha256(dst), "verify": os.path.join(final, os.path.basename(report)),
            "user_dir": result.get("user_dir"), "unlock_all": result.get("unlock_all"), "packed_png": result.get("packed_png_count"), "audio": result.get("audio_count")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True, help="冻结提交（两个包与网页版都从它出）")
    ap.add_argument("--no-web", action="store_true")
    ap.add_argument("--only", choices=["public", "internal", "web", "web_internal"], help="只出这一份（其余不动）")
    a = ap.parse_args()
    commit = subprocess.run(["git", "rev-parse", "--short", a.ref], cwd=ROOT, stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    final = os.path.join(OUT, "final_%s" % commit)
    os.makedirs(final, exist_ok=True)
    want = {a.only} if a.only else ({"public", "internal"} | (set() if a.no_web else {"web", "web_internal"}))
    summary = {"commit": commit}
    if "public" in want:
        summary["public"] = one_package("对外", "_Public_Encrypted", [], commit, final)
    if "internal" in want:
        summary["internal"] = one_package("对内", "_Internal_EA_Encrypted", ["--ea"], commit, final)
    for key, kind, extra, aud in (("web", "对外网页版", [], "public"), ("web_internal", "对内网页版", ["--ea"], "internal")):
        if key not in want:
            continue
        web = os.path.join(final, key)
        out = step("导出" + kind, [sys.executable, os.path.join(TOOLS, "export_web.py"), "--ref", commit, "--out", web] + extra)
        last = [l for l in out.splitlines() if l.startswith("完成：")]
        step("验证" + kind, [sys.executable, os.path.join(TOOLS, "verify_web_build.py"), "--dir", web, "--audience", aud, "--commit", commit])
        report = os.path.join(final, "web_verification_%s_%s.json" % (aud, commit))
        result = json.load(open(report, encoding="utf-8"))
        if result.get("failures"):
            sys.exit("%s验证结果不对：%s" % (kind, report))
        summary[key] = {"dir": web, "result": last[-1] if last else "", "verify": report, "audience": aud,
                        "unlock_all": result.get("unlock_all"), "boss_trial": result.get("boss_trial"), "max_file_mib": result.get("max_file_mib")}
    path = os.path.join(final, "release_%s.json" % commit)
    if os.path.exists(path):   # 分次出（--only）时并进已有汇总
        old = json.load(open(path, encoding="utf-8"))
        old.update(summary)
        summary = old
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=1)
    print("\n完成（提交 %s）。产物目录：%s" % (commit, final))
    for k in ("public", "internal"):
        if k in summary:
            print("  %-8s %s（%.1f MB，存档目录 %s，全部解锁 %s）" % (k, summary[k]["zip"], summary[k]["mb"], summary[k]["user_dir"], summary[k].get("unlock_all")))
    for k in ("web", "web_internal"):
        if k in summary:
            print("  %-12s %s（全部解锁 %s，演练 %s）" % (k, summary[k]["result"], summary[k].get("unlock_all"), summary[k].get("boss_trial")))


if __name__ == "__main__":
    main()
