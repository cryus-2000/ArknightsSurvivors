# -*- coding: utf-8 -*-
"""导出可分发的 Windows 版本（docs/33）。

用法（仓库根目录）：
    python tools/export_build.py              # 对外加密版；导出当前已提交的 HEAD
    python tools/export_build.py --ref main   # 指定提交 / 分支
    python tools/export_build.py --no-zip     # 只生成目录，不打 zip
    python tools/export_build.py --ea         # 内部 EA 加密验证包
    python tools/export_build.py --unencrypted # 仅本地 Diagnostic 未加密包

流程：
1. git archive 把 <ref> 解到 build/_export/src —— 只含已提交内容，其它会话的未提交改动不会混进包里；
   整个过程持有 build/_export.lock（release_all 在导出 + 验证期间也持有它），并行出包 / 验证不会互相清掉对方的 build/_export；
2. Godot 导入资源（--import），再用 godot_runner.stale_imports 核对导入缓存（.import 登记的缓存文件都在），缺了就再导（最多再 2 遍）；
   然后用 "Windows Desktop" 预设导出发布版（需要 4.7.2 导出模板，见 docs/33）。导出报错时自动清掉导入缓存重导一次再导出，第二次仍失败才算失败
   （2026-10-10 db5f4112 出包：无头导入在退出时崩溃，fonts/ui.ttf 的 fontdata 没写出来，导出报 "Error loading custom project font"，重跑一次就过）；
3. 默认生成加密公开版：美术导入 PCK，脚本、数据、音频与资源目录一起加密；
       方舟幸存者/
         开始游戏.bat
         说明.txt
         release_manifest.json
         game/ArknightsSurvivors.exe + .pck
   --ea 为内部 EA 加密包；--unencrypted 仅供本地诊断，保留外置 PNG。
4. 打成 build/release/ 下带 Public_Encrypted、Internal_EA_Encrypted 或 Diagnostic 标记的 zip。
"""
import json, argparse, datetime, os, shutil, subprocess, sys, tarfile, io, zipfile
from pathlib import Path
import godot_runner
import encrypted_release

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
WORK = os.path.join(ROOT, "build", "_export")
OUT = os.path.join(ROOT, "build", "release")
NAME = "方舟幸存者"
PRESET = "Windows Desktop"
INTERNAL_USER_DIR = "ArknightsSurvivors_Internal"   # 对内包存档目录：%APPDATA%\ArknightsSurvivors_Internal
# art/incoming 里只给玩家带游戏用到的 PNG：交接文档、清单、预览图不带
SKIP_WORDS = ("preview", "overview", "_frames.png", "reference", "_ref.")
ART_SUBDIRS = ["portraits"]   # art/incoming 下随包带走的子目录（Boss 名片头像，art.gd 按 "portraits/boss_<id>" 取）

README = """方舟幸存者（明日方舟同人，非商业）
版本：{channel}{ver}（{date}）

【怎么玩】
双击「开始游戏.bat」，或进入 game 文件夹双击 ArknightsSurvivors.exe。
不要把 game 文件夹单独拿出来运行——美术资源在旁边的 art 文件夹里，两个文件夹要放在一起。

【操作】
WASD / 方向键 移动；空格 冲刺（冲刺中无敌）；Q / E 手动技能（目前只有乌尔比安三技能）；Tab 属性；Esc 暂停；M 开关音乐。设置里可把普通攻击改为手动：左键 / J 攻击，朝光标方向。支持手柄。
V 或右上角倍速按钮：1× / 1.5× / 2×。菜单、音乐不加速。

【检查与展示】
图鉴的敌人页面可以观看真实攻击演示，切换形态并重播。主页右下角可更换与博士并肩的封面干员，不影响开局选人。
{ea_note}

【说明】
本作是《明日方舟》的非官方同人作品，与鹰角网络无关。部分特效改自开放许可的第三方像素素材，详见游戏内「致谢」页。
"""


def run(cmd, cwd=None, check=True):
    print(">", " ".join(cmd))
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    tail = "\n".join(p.stdout.splitlines()[-15:])
    if check and p.returncode != 0:
        print(tail)
        sys.exit("命令失败：%s" % cmd[0])
    return p.stdout



def checked_build_path(path):
    """Reject redirected build folders and output links before deletion/writing."""
    root = Path(ROOT).resolve()
    build = root / "build"
    candidate = Path(path).absolute()
    try:
        relative = candidate.relative_to(Path(ROOT).absolute() / "build")
    except ValueError:
        raise ValueError("Output must stay under the repository build directory: %s" % path)
    expected = build / relative
    if build.resolve() != build or candidate.resolve() != expected:
        raise ValueError("Refusing redirected build/output path: %s" % path)
    if not relative.parts:
        raise ValueError("Refusing to use the build root itself as an output target")
    return str(expected)


EXPORT_LOCK = os.path.join(ROOT, "build", "_export.lock")   # 与 release_all 共用：build/_export 一次只给一个出包 / 验证用


def run_export_godot(cmd, timeout=900, check=True):
    """跑一次 Godot；返回 (输出, 失败原因或 None)。check=True 时脚本错误 / ERROR: / 超时都算失败"""
    print(">", " ".join(cmd), flush=True)
    out, err, timed_out = godot_runner.run_godot(cmd, timeout)
    output = out + "\n" + err
    if timed_out:
        return output, "Godot export timed out"
    if check and (godot_runner.script_errors(out, err) or "ERROR:" in output):
        return output, "Godot export reported errors"
    return output, None


def import_verified(gpath, fresh=False, retries=2):
    """导入资源并核对导入缓存：.import 登记的缓存文件缺一个就再导，最多再 retries 遍。fresh=True 先清掉 .godot 从头导。
    无头导入退出时偶发崩溃（不影响已写出的部分），所以单次导入的退出码不作数，以缓存核对为准。返回核对是否通过"""
    if fresh:
        shutil.rmtree(os.path.join(gpath, ".godot"), ignore_errors=True)
    for attempt in range(1 + retries):
        run_export_godot([GODOT, "--headless", "--path", gpath, "--import"], check=False)
        miss = godot_runner.stale_imports(gpath)
        imp = os.path.join(gpath, ".godot", "imported")
        total = len(os.listdir(imp)) if os.path.isdir(imp) else 0
        if not miss:
            print("导入缓存核对：完整（%d 个缓存文件，第 %d 遍导入）" % (total, attempt + 1), flush=True)
            return True
        print("导入缓存核对：缺 %d 个（例如 %s），%s" % (len(miss), miss[0], "再导一遍" if attempt < retries else "已到重试上限"), flush=True)
    return False


def export_with_retry(gpath, exe_path):
    """导出；失败时清掉导入缓存重导一次再导出，第二次仍失败才退出。返回导出输出"""
    for attempt in (1, 2):
        out, why = run_export_godot([GODOT, "--headless", "--path", gpath, "--export-release", PRESET, exe_path])
        if why is None:
            return out
        print("\n".join(out.splitlines()[-20:]), flush=True)
        if attempt == 2:
            sys.exit(why)
        print("导出第 1 次失败（%s），清掉导入缓存重导后再试一次" % why, flush=True)
        for stale in (exe_path, os.path.splitext(exe_path)[0] + ".pck"):
            if os.path.exists(stale):
                os.remove(stale)
        import_verified(gpath, fresh=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--no-zip", action="store_true")
    ap.add_argument("--ea", action="store_true", help="Label this build as Early Access")
    encryption = ap.add_mutually_exclusive_group()
    encryption.add_argument("--encrypted", action="store_true", help="Encrypt packed resources (default); never fall back")
    encryption.add_argument("--unencrypted", action="store_true", help="Local diagnostic only; never a public release")
    a = ap.parse_args()
    a.encrypted = not a.unencrypted
    audience = "diagnostic" if a.unencrypted else ("internal" if a.ea else "public")
    label = "_Diagnostic" if a.unencrypted else ("_Internal_EA_Encrypted" if a.ea else "_Public_Encrypted")
    # Check before touching staging/output directories. Missing secrets or templates fail closed.
    if a.encrypted:
        encrypted_template, encryption_key = encrypted_release.template_and_key()


    commit = run(["git", "rev-parse", "--short", a.ref], cwd=ROOT).strip()
    date = datetime.datetime.now().strftime("%Y%m%d")
    checked_build_path(OUT)
    if a.encrypted:
        secrets = (encrypted_template, encryption_key)
    else:
        secrets = (None, None)
    if os.environ.get("ARK_EXPORT_LOCK_HELD") == "1":   # release_all 已替我们持锁（它要连着验证一起锁）
        build(a, commit, date, audience, label, *secrets)
        return
    with godot_runner.file_lock(EXPORT_LOCK):
        build(a, commit, date, audience, label, *secrets)


def build(a, commit, date, audience, label, encrypted_template, encryption_key):
    shutil.rmtree(checked_build_path(WORK), ignore_errors=True)
    src = os.path.join(WORK, "src")
    os.makedirs(src)
    # 1. 干净副本
    data = subprocess.run(["git", "archive", "--format=tar", a.ref], cwd=ROOT, stdout=subprocess.PIPE, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(data)).extractall(src, filter="data")
    print("源码：%s @ %s" % (a.ref, commit))

    # 发布检查（玩法系统 tools/check_release.py，docs/33 清单）：对即将打包的这份源码跑，不过就中止
    chk = os.path.join(src, "tools", "check_release.py")
    p = subprocess.run([sys.executable, chk], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", env=dict(os.environ, PYTHONIOENCODING="utf-8"))
    print(p.stdout.strip())
    if p.returncode != 0:
        sys.exit("发布检查未通过，已中止导出")
    # 构建信息：写进包里的 data/build.json，局内数据记录（run/telemetry.gd）按它标版本（docs/40）
    bj = os.path.join(src, "game", "data", "build.json")
    binfo = json.load(open(bj, encoding="utf-8")) if os.path.exists(bj) else {"version": "dev"}
    binfo["commit"] = commit
    binfo["built"] = date
    binfo["audience"] = audience
    binfo["encrypted"] = a.encrypted
    if a.ea:
        binfo["channel"] = "EA"
    else:
        binfo.pop("channel", None)
    json.dump(binfo, open(bj, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # 对内包的存档目录与对外包分开（docs/33 §双版本：内测进度不得影响对外存档）：同一台机器两个包都装时，
    # 对内包的正常游玩不会解锁对外包的图鉴 / 难度。只改打包副本的 project.godot，仓库里不动
    if audience == "internal":
        pg = os.path.join(src, "game", "project.godot")
        text = open(pg, "rb").read().decode("utf-8")   # 按字节读写，保留原换行
        key = 'config/custom_user_dir_name="ArknightsSurvivors"'
        if text.count(key) != 1:
            sys.exit("project.godot 的 custom_user_dir_name 不是预期值，无法给对内包隔离存档目录")
        open(pg, "wb").write(text.replace(key, 'config/custom_user_dir_name="%s"' % INTERNAL_USER_DIR).encode("utf-8"))

    # 2. 导入 + 导出
    pkg = os.path.join(WORK, NAME)
    game_dir = os.path.join(pkg, "game")
    os.makedirs(game_dir)
    gpath = os.path.join(src, "game")
    if a.encrypted:
        preset_path = Path(gpath) / "export_presets.cfg"
        preset_path.write_text(encrypted_release.encrypted_preset(preset_path.read_text(encoding="utf-8"), encrypted_template), encoding="utf-8")
        packed_art = Path(gpath) / "art" / "incoming"
        packed_art.mkdir(parents=True, exist_ok=True)
        for pat in ["*.png"] + [d + "/*.png" for d in ART_SUBDIRS]:
            for png in sorted((Path(src) / "art" / "incoming").glob(pat)):
                if not any(w in png.name.lower() for w in SKIP_WORDS):
                    (packed_art / png.parent.name if png.parent.name in ART_SUBDIRS else packed_art).mkdir(parents=True, exist_ok=True)
                    shutil.copy2(png, (packed_art / png.parent.name if png.parent.name in ART_SUBDIRS else packed_art) / png.name)
        # Preserve editor/external-art workflow; public binaries only read their packed resources.
        art_loader = Path(gpath) / "scripts" / "art.gd"
        loader = art_loader.read_text(encoding="utf-8")
        guard = 'static func _incoming_path(name: String) -> String:\n'
        if guard not in loader:
            raise ValueError("Art loader contract changed; encrypted release cannot safely patch the staging copy")
        if 'OS.has_feature("packed_release")' not in loader:
            loader = loader.replace(guard, guard + '\tif OS.has_feature("packed_release"):\n\t\treturn ""\n', 1)
            art_loader.write_text(loader, encoding="utf-8")
    if not import_verified(gpath):   # 缺的缓存文件导出时会以 "Cannot open file res://.godot/imported/..." 失败，导出前再清缓存从头导一遍
        print("导入缓存仍不完整，清掉 .godot 从头导一遍", flush=True)
        import_verified(gpath, fresh=True)
    previous_key = os.environ.get("GODOT_SCRIPT_ENCRYPTION_KEY")
    try:
        if a.encrypted:
            os.environ["GODOT_SCRIPT_ENCRYPTION_KEY"] = encryption_key
        out = export_with_retry(gpath, os.path.join(game_dir, "ArknightsSurvivors.exe"))
    finally:
        if previous_key is None:
            os.environ.pop("GODOT_SCRIPT_ENCRYPTION_KEY", None)
        else:
            os.environ["GODOT_SCRIPT_ENCRYPTION_KEY"] = previous_key
    if "No export template found" in out or not all(os.path.isfile(os.path.join(game_dir, "ArknightsSurvivors" + ext)) for ext in (".exe", ".pck")):
        print("\n".join(out.splitlines()[-15:]))
        sys.exit("导出失败：缺少 Godot 4.7.2 导出模板？见 docs/33")

    # 3. 美术 + 启动器 + 说明
    art_src = os.path.join(src, "art", "incoming")
    art_dst = os.path.join(pkg, "art", "incoming")
    if not a.encrypted:
        os.makedirs(art_dst)
    n = 0
    for sub in [""] + ART_SUBDIRS:
        sdir = os.path.join(art_src, sub) if sub else art_src
        if not os.path.isdir(sdir):
            continue
        for f in sorted(os.listdir(sdir)):
            if f.lower().endswith(".png") and not any(w in f.lower() for w in SKIP_WORDS):
                if not a.encrypted:
                    os.makedirs(os.path.join(art_dst, sub) if sub else art_dst, exist_ok=True)
                    shutil.copy2(os.path.join(sdir, f), os.path.join(art_dst, sub) if sub else art_dst)
                n += 1
    print(("Packed/encrypted PNG: %d" if a.encrypted else "美术 PNG：%d 张") % n)
    with open(os.path.join(pkg, "开始游戏.bat"), "w", encoding="gbk") as fh:
        fh.write('@echo off\r\ncd /d "%~dp0game"\r\nstart "" "ArknightsSurvivors.exe"\r\n')
    with open(os.path.join(pkg, "说明.txt"), "w", encoding="utf-8-sig") as fh:
        readme = README
        readme += {"public": "\n用途：对外公开试玩，加密资源版。\n", "internal": "\n用途：内部 EA 验证，请勿作为公开正式包分发。存档与对外版分开（%APPDATA%\\" + INTERNAL_USER_DIR + "），内测进度不会带到对外版。\n", "diagnostic": "\n用途：仅本地诊断，未加密；不可作为公开发布包。\n"}[audience]
        if a.encrypted:
            readme = readme.replace("不要把 game 文件夹单独拿出来运行——美术资源在旁边的 art 文件夹里，两个文件夹要放在一起。", "美术、音频与脚本已打包加密。请保留 game 文件夹中的 exe 与 pck 文件。")
        fh.write(readme.format(ver=commit, date=date, channel="EA " if a.ea else "", ea_note="对内测试版启动即全部解锁：难度三档、图鉴、结局线全开，只在本次运行生效、不写入存档。\nEA 版主页「Boss 演练」可选对手、主控、成长及形态；观察模式不会倒下，演练不记录通关进度。\n对内测试版会在本机记录每局的对局摘要（胜负、用时、等级、死因等，不含任何个人信息，不上传）：\n设置 → 游戏 → 对局记录「打开记录文件夹」，把 runs.jsonl 发给我就能帮忙校准难度。" if a.ea else "").replace("\n", "\r\n"))

    if a.encrypted:
        pck_info = encrypted_release.check_encrypted_pck(Path(game_dir) / "ArknightsSurvivors.pck")
        encrypted_release.check_distribution(pkg)
        # Manifest never contains the key or private build paths.
        hashes = {p.name: __import__("hashlib").sha256(p.read_bytes()).hexdigest() for p in Path(game_dir).glob("*") if p.is_file()}
        manifest = dict(pck_info, commit=commit, audience=audience, encrypted=True, packed_png_count=n, files_sha256=hashes)
        (Path(pkg) / "release_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    # 4. zip
    if a.no_zip:
        print("完成：", pkg)
        return
    os.makedirs(checked_build_path(OUT), exist_ok=True)
    zpath = os.path.join(OUT, "%s_%s_%s.zip" % (NAME + label, date, commit))
    checked_build_path(zpath)
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for d, _, files in os.walk(pkg):
            for f in files:
                full = os.path.join(d, f)
                z.write(full, os.path.join(NAME, os.path.relpath(full, pkg)))
    print("完成：%s（%.1f MB）" % (zpath, os.path.getsize(zpath) / 1048576))


if __name__ == "__main__":
    main()
