# -*- coding: utf-8 -*-
"""导出可分发的 Windows 版本（docs/33）。

用法（仓库根目录）：
    python tools/export_build.py              # 导出当前已提交的 HEAD
    python tools/export_build.py --ref main   # 指定提交 / 分支
    python tools/export_build.py --no-zip     # 只生成目录，不打 zip

流程：
1. git archive 把 <ref> 解到 build/_export/src —— 只含已提交内容，其它会话的未提交改动不会混进包里；
2. Godot 导入资源（--import），再用 "Windows Desktop" 预设导出发布版（需要 4.7.2 导出模板，见 docs/33）；
3. 组装发布目录：游戏 exe 按 art.gd incoming_dir() 从「exe 所在目录/../art/incoming」读美术，所以结构是
       方舟幸存者/
         开始游戏.bat              双击启动
         说明.txt
         game/ArknightsSurvivors.exe + .pck
         art/incoming/*.png       （不含交接文档、预览图）
4. 打成 build/release/<名字>_<日期>_<提交>.zip。
"""
import json, argparse, datetime, os, shutil, subprocess, sys, tarfile, io, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
WORK = os.path.join(ROOT, "build", "_export")
OUT = os.path.join(ROOT, "build", "release")
NAME = "方舟幸存者"
PRESET = "Windows Desktop"
# art/incoming 里只给玩家带游戏用到的 PNG：交接文档、清单、预览图不带
SKIP_WORDS = ("preview", "overview", "_frames.png", "reference", "_ref.")

README = """方舟幸存者（明日方舟同人，非商业）
版本：{ver}（{date}）

【怎么玩】
双击「开始游戏.bat」，或进入 game 文件夹双击 ArknightsSurvivors.exe。
不要把 game 文件夹单独拿出来运行——美术资源在旁边的 art 文件夹里，两个文件夹要放在一起。

【操作】
WASD / 方向键 移动；Space 或 J 手动技能；Tab 属性；Esc 暂停。支持手柄。

【说明】
本作是《明日方舟》的非官方同人作品，与鹰角网络无关。部分特效改自开放许可的第三方像素素材，详见游戏内「致谢」页。
"""


def run(cmd, cwd=None):
    print(">", " ".join(cmd))
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    tail = "\n".join(p.stdout.splitlines()[-15:])
    if p.returncode != 0:
        print(tail)
        sys.exit("命令失败：%s" % cmd[0])
    return p.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--no-zip", action="store_true")
    a = ap.parse_args()

    commit = run(["git", "rev-parse", "--short", a.ref], cwd=ROOT).strip()
    date = datetime.datetime.now().strftime("%Y%m%d")
    shutil.rmtree(WORK, ignore_errors=True)
    src = os.path.join(WORK, "src")
    os.makedirs(src)
    # 1. 干净副本
    data = subprocess.run(["git", "archive", "--format=tar", a.ref], cwd=ROOT, stdout=subprocess.PIPE, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(data)).extractall(src, filter="data")
    print("源码：%s @ %s" % (a.ref, commit))
    # 构建信息：写进包里的 data/build.json，局内数据记录（run/telemetry.gd）按它标版本（docs/40）
    bj = os.path.join(src, "game", "data", "build.json")
    binfo = json.load(open(bj, encoding="utf-8")) if os.path.exists(bj) else {"version": "dev"}
    binfo["commit"] = commit
    binfo["built"] = date
    json.dump(binfo, open(bj, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # 2. 导入 + 导出
    pkg = os.path.join(WORK, NAME)
    game_dir = os.path.join(pkg, "game")
    os.makedirs(game_dir)
    gpath = os.path.join(src, "game")
    run([GODOT, "--headless", "--path", gpath, "--import"])
    out = run([GODOT, "--headless", "--path", gpath, "--export-release", PRESET, os.path.join(game_dir, "ArknightsSurvivors.exe")])
    if "No export template found" in out or not os.path.exists(os.path.join(game_dir, "ArknightsSurvivors.exe")):
        print("\n".join(out.splitlines()[-15:]))
        sys.exit("导出失败：缺少 Godot 4.7.2 导出模板？见 docs/33")

    # 3. 美术 + 启动器 + 说明
    art_src = os.path.join(src, "art", "incoming")
    art_dst = os.path.join(pkg, "art", "incoming")
    os.makedirs(art_dst)
    n = 0
    for f in sorted(os.listdir(art_src)):
        if f.lower().endswith(".png") and not any(w in f.lower() for w in SKIP_WORDS):
            shutil.copy2(os.path.join(art_src, f), art_dst)
            n += 1
    print("美术 PNG：%d 张" % n)
    with open(os.path.join(pkg, "开始游戏.bat"), "w", encoding="gbk") as fh:
        fh.write('@echo off\r\ncd /d "%~dp0game"\r\nstart "" "ArknightsSurvivors.exe"\r\n')
    with open(os.path.join(pkg, "说明.txt"), "w", encoding="utf-8-sig") as fh:
        fh.write(README.format(ver=commit, date=date).replace("\n", "\r\n"))

    # 4. zip
    if a.no_zip:
        print("完成：", pkg)
        return
    os.makedirs(OUT, exist_ok=True)
    zpath = os.path.join(OUT, "%s_%s_%s.zip" % (NAME, date, commit))
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for d, _, files in os.walk(pkg):
            for f in files:
                full = os.path.join(d, f)
                z.write(full, os.path.join(NAME, os.path.relpath(full, pkg)))
    print("完成：%s（%.1f MB）" % (zpath, os.path.getsize(zpath) / 1048576))


if __name__ == "__main__":
    main()
