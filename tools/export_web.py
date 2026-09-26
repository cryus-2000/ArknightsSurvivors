"""一步导出网页版（docs/22）：干净副本 → 复制美术 → Godot 导出 Web → 分片 + gzip → 内联加载器。

  python tools/export_web.py            # 导出 HEAD 到 build/web/
  python tools/export_web.py --ref xxx  # 导出指定提交

分片：index.pck / index.wasm 按 --part-mib（默认 10 MiB，原始字节）切片，每片 gzip -9，
命名 index.pck.00.gz …，原文件删掉。tools/web/loader.js 拦截引擎对这两个文件的 fetch，并行下载分片、
解压拼回（见该文件注释）。托管平台单文件上限 25 MB（EdgeOne / Cloudflare Pages），导出后逐个检查。
不发布、不上传：部署命令见 docs/22。
"""
import argparse, gzip, io, json, os, shutil, subprocess, sys, tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
WORK = os.path.join(ROOT, "build", "_web")
WEB = os.path.join(ROOT, "tools", "web")
LIMIT = 25 * 1000 * 1000  # 平台按 25 MB 计，取十进制更保守
MARK = "<!--SHUIYUE_LOADER-->"
TYPES = {"index.pck": "application/octet-stream", "index.wasm": "application/wasm"}


def run(cmd, check=True):
    print(">", " ".join(cmd))
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    if check and p.returncode != 0:
        print("\n".join(p.stdout.splitlines()[-15:]))
        sys.exit("命令失败：%s" % cmd[0])
    return p.stdout


def split(out_dir, name, part_bytes):
    path = os.path.join(out_dir, name)
    with open(path, "rb") as fh:
        raw = fh.read()
    parts = []
    for i in range(0, len(raw), part_bytes):
        pn = "%s.%02d.gz" % (name, len(parts))
        data = gzip.compress(raw[i:i + part_bytes], compresslevel=9, mtime=0)
        with open(os.path.join(out_dir, pn), "wb") as fh:
            fh.write(data)
        parts.append([pn, len(data)])
    os.remove(path)
    return {"size": len(raw), "type": TYPES[name], "parts": parts}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "web"))
    ap.add_argument("--part-mib", type=float, default=10)
    ap.add_argument("--worktree-presets", action="store_true", help="用工作区的 export_presets.cfg（改预设时本地试导出用）")
    a = ap.parse_args()

    commit = run(["git", "-C", ROOT, "rev-parse", "--short", a.ref]).strip()
    shutil.rmtree(WORK, ignore_errors=True)
    src = os.path.join(WORK, "src")
    os.makedirs(src)
    data = subprocess.run(["git", "archive", "--format=tar", a.ref, "game", "art/incoming"], cwd=ROOT, stdout=subprocess.PIPE, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(data)).extractall(src, filter="data")
    if a.worktree_presets:
        shutil.copy2(os.path.join(ROOT, "game", "export_presets.cfg"), os.path.join(src, "game", "export_presets.cfg"))
    # 网页没有本地文件系统：美术要打进包里（审稿拼图由 Web 预设的 exclude_filter 排除）
    art_dst = os.path.join(src, "game", "art", "incoming")
    os.makedirs(art_dst, exist_ok=True)
    art_src = os.path.join(src, "art", "incoming")
    for f in os.listdir(art_src):
        if f.lower().endswith(".png"):
            shutil.copy2(os.path.join(art_src, f), art_dst)
    print("源码：%s @ %s" % (a.ref, commit))

    gpath = os.path.join(src, "game")
    tmp = os.path.join(WORK, "out")
    os.makedirs(tmp)
    run([GODOT, "--headless", "--path", gpath, "--import"], check=False)  # 无头导入退出时偶发崩溃，结果以导出为准
    out = run([GODOT, "--headless", "--path", gpath, "--export-release", "Web", os.path.join(tmp, "index.html")], check=False)
    if not os.path.exists(os.path.join(tmp, "index.pck")):
        print("\n".join(out.splitlines()[-15:]))
        sys.exit("导出失败：缺少 Web 导出模板（web_nothreads_*.zip）？见 docs/22")

    part = int(a.part_mib * 1048576)
    manifest = {n: split(tmp, n, part) for n in ("index.pck", "index.wasm")}
    html_p = os.path.join(tmp, "index.html")
    with open(html_p, encoding="utf-8") as fh:
        html = fh.read()
    if MARK not in html:
        sys.exit("index.html 里找不到 %s（Web 预设 html/head_include 被改了？）" % MARK)
    with open(os.path.join(WEB, "loader.js"), encoding="utf-8") as fh:
        js = fh.read().replace("/*SHUIYUE_MANIFEST*/null", json.dumps(manifest, separators=(",", ":")))
    with open(os.path.join(WEB, "loader.css"), encoding="utf-8") as fh:
        css = fh.read()
    html = html.replace(MARK, "<style>\n%s</style>\n<script>\n%s</script>" % (css, js))
    with open(html_p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(html)
    shutil.copy2(os.path.join(src, "art", "incoming", "doctor_run@2x.png"), os.path.join(tmp, "loader_doctor.png"))
    with open(os.path.join(tmp, "build.txt"), "w", encoding="utf-8") as fh:
        fh.write(commit + "\n")

    shutil.rmtree(a.out, ignore_errors=True)
    shutil.copytree(tmp, a.out)
    big = 0
    for f in sorted(os.listdir(a.out)):
        s = os.path.getsize(os.path.join(a.out, f))
        big = max(big, s)
        print("  %-32s %10.2f MiB%s" % (f, s / 1048576, "  ← 超过 25 MB" if s > LIMIT else ""))
    tot = sum(os.path.getsize(os.path.join(a.out, f)) for f in os.listdir(a.out))
    print("完成：%s @ %s，共 %.1f MiB，最大单文件 %.2f MiB" % (a.out, commit, tot / 1048576, big / 1048576))
    if big > LIMIT:
        sys.exit("有文件超过 25 MB 上限")


if __name__ == "__main__":
    main()
