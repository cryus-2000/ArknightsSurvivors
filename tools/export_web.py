"""一步导出网页版（docs/22）：干净副本 → 复制美术 → Godot 导出 Web → 分片 + gzip → 内联加载器。

  python tools/export_web.py            # 导出 HEAD 到 build/web/（对外网页版）
  python tools/export_web.py --ref xxx  # 导出指定提交
  python tools/export_web.py --ea --out build/release/final_<提交>/web_internal   # 对内网页版（演练开、全部解锁，同对内 Windows 包）
  python tools/export_web.py --toy      # B站 Toy 包：build/toy/web/ + build/toy/方舟幸存者_toy_<提交>.zip（根目录 index.html，≤ 50 MB，不上传）

--toy（docs/22「Toy 接入」）：同一份 index.html 模板（加载进度页、容器适配、云存档都一样），差异只有两处：
  1. container.js 之前写 window.__SY_TOY = 1 → 一律加载 Toy JS SDK（itch 包只在像是 B站的域名 / UA 下加载）；
  2. 分片文件名不用 .gz 后缀（Toy 只发布白名单后缀的文件，.pck / .wasm 是 Godot 包必有的后缀，.gz 不确定）：
     index.pck.00.gz → index.00.pck、index.wasm.00.gz → index.00.wasm，内容仍是 gzip，加载器按魔数识别，不改加载器。

构建信息：和 Windows 包一样往打包副本的 data/build.json 写 commit / built / audience（public 或 --ea 时 internal）/ encrypted=false，
--ea 另写 channel=EA。游戏里 Boss 演练入口与「全部解锁」都按 audience 判断（settings.gd，docs/33 §双版本）。
网页存档在浏览器 IndexedDB、按网站源（协议 + 域名 + 端口）隔离：对内网页版要放在和对外版不同的域名 / 端口下，否则两版共用存档。
导出后用 tools/verify_web_build.py 实测（release_all.py 会自动跑）。

分片：index.pck / index.wasm 按 --part-mib（默认 10 MiB，原始字节）切片，每片 gzip -9，
命名 index.pck.00.gz …，原文件删掉。tools/web/loader.js 拦截引擎对这两个文件的 fetch，并行下载分片、
解压拼回（见该文件注释）。托管平台单文件上限 25 MB（EdgeOne / Cloudflare Pages），导出后逐个检查。
不发布、不上传：部署命令见 docs/22。
"""
import argparse, datetime, gzip, io, json, lzma, os, shutil, subprocess, sys, tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release_slim

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
WORK = os.path.join(ROOT, "build", "_web")
WEB = os.path.join(ROOT, "tools", "web")
LIMIT = 25 * 1000 * 1000  # 平台按 25 MB 计，取十进制更保守
MARK = "<!--SHUIYUE_LOADER-->"
TYPES = {"index.pck": "application/octet-stream", "index.wasm": "application/wasm"}



def _boot_v(src):
    """启动加载页方向（balance.json ui/boot_v，0 = 现行声呐测绘；10-30 原型）"""
    try:
        with open(os.path.join(src, "game", "data", "balance.json"), encoding="utf-8") as fh:
            return int(json.load(fh).get("ui", {}).get("boot_v", 0))
    except (OSError, ValueError):
        return 0

def run(cmd, check=True):
    print(">", " ".join(cmd))
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    if check and p.returncode != 0:
        print("\n".join(p.stdout.splitlines()[-15:]))
        sys.exit("命令失败：%s" % cmd[0])
    return p.stdout


LZMA_FILTERS = [{"id": lzma.FILTER_LZMA1, "preset": 9 | lzma.PRESET_EXTREME, "lc": 3, "lp": 0, "pb": 0, "dict_size": 32 << 20}]


def split(out_dir, name, part_bytes, toy=False, enc="gzip"):
    """enc="lzma"（index.wasm，docs/187 §5）：分片用 .lzma alone 格式，加载器用 tools/web/lzma_dec.js 解；比 gzip -9 小约 3 MiB"""
    path = os.path.join(out_dir, name)
    with open(path, "rb") as fh:
        raw = fh.read()
    parts = []
    stem, ext = os.path.splitext(name)
    suf = ".lzma" if enc == "lzma" else ".gz"
    for i in range(0, len(raw), part_bytes):
        pn = ("%s.%02d%s" % (stem, len(parts), ext)) if toy else ("%s.%02d%s" % (name, len(parts), suf))
        chunk = raw[i:i + part_bytes]
        data = lzma.compress(chunk, format=lzma.FORMAT_ALONE, filters=LZMA_FILTERS) if enc == "lzma" else gzip.compress(chunk, compresslevel=9, mtime=0)
        if enc == "lzma":
            assert lzma.decompress(data, format=lzma.FORMAT_ALONE) == chunk, "%s：LZMA 回读不符" % pn
        with open(os.path.join(out_dir, pn), "wb") as fh:
            fh.write(data)
        parts.append([pn, len(data), len(chunk)])   # [文件名, 压缩字节, 原始字节]：加载器按原始长度直接写进整块
    os.remove(path)
    m = {"size": len(raw), "type": TYPES[name], "parts": parts}
    if enc == "lzma":
        m["enc"] = "lzma"
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "web"))
    ap.add_argument("--part-mib", type=float, default=10)
    ap.add_argument("--worktree-presets", action="store_true", help="用工作区的 export_presets.cfg（改预设时本地试导出用）")
    ap.add_argument("--audio-tier", default="C", choices=["off", "A", "B", "C", "D", "E"], help="网页包音频再压缩档位（tools/web_audio.py：A 近无损 / B 平衡 / C 缺省（10-28 用户定，B 可回退） / D、E 试听档（docs/187 §7）；off = 不压）")
    ap.add_argument("--wasm-gzip", action="store_true", help="index.wasm 分片退回 gzip（缺省 LZMA，docs/187 §5）")
    ap.add_argument("--no-lossless", action="store_true", help="关掉无损瘦身（字体 WOFF2 + WebP 无损最高档，docs/187），对照用")
    ap.add_argument("--ea", action="store_true", help="对内网页版：build.json audience = internal（演练开、全部解锁）")
    ap.add_argument("--toy", action="store_true", help="B站 Toy 包：一律加载 Toy SDK、分片不带 .gz 后缀、另打 zip（缺省输出 build/toy/web）")
    a = ap.parse_args()
    if a.toy and a.out == os.path.join(ROOT, "build", "web"):
        a.out = os.path.join(ROOT, "build", "toy", "web")

    commit = run(["git", "-C", ROOT, "rev-parse", "--short", a.ref]).strip()
    shutil.rmtree(WORK, ignore_errors=True)
    src = os.path.join(WORK, "src")
    os.makedirs(src)
    data = subprocess.run(["git", "archive", "--format=tar", a.ref, "game", "art/source/voice", "tools"], cwd=ROOT, stdout=subprocess.PIPE, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(data)).extractall(src, filter="data")
    if a.worktree_presets:
        shutil.copy2(os.path.join(ROOT, "game", "export_presets.cfg"), os.path.join(src, "game", "export_presets.cfg"))
    # 运行时贴图都在 game/art（docs/189），随 pck 走；网页包（Toy 50 MB）不带干员 @2x 回退条，游戏读 @1x（docs/128）
    _, freed = release_slim.prune_game_art(os.path.join(src, "game"), drop_fallback=True)
    print("[瘦身] 干员 @2x 回退条不进网页包：%.2f MB" % (freed / 1e6))
    print("源码：%s @ %s" % (a.ref, commit))
    # 构建信息（同 export_build.py）：局内记录的版本号、发布对象；演练入口与全部解锁按 audience 判断
    bj = os.path.join(src, "game", "data", "build.json")
    binfo = json.load(open(bj, encoding="utf-8")) if os.path.exists(bj) else {"version": "dev"}
    binfo.update({"commit": commit, "built": datetime.datetime.now().strftime("%Y%m%d"), "audience": "internal" if a.ea else "public", "encrypted": False, "platform": "web"})
    if a.ea:
        binfo["channel"] = "EA"
    else:
        binfo.pop("channel", None)
    with open(bj, "w", encoding="utf-8") as fh:
        json.dump(binfo, fh, ensure_ascii=False, indent=1)
    print("构建信息：audience=%s" % binfo["audience"])

    # 发布检查（玩法系统 tools/check_release.py，docs/33 清单）：对即将打包的这份源码跑，不过就中止
    chk = os.path.join(src, "tools", "check_release.py")
    p = subprocess.run([sys.executable, chk], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", env=dict(os.environ, PYTHONIOENCODING="utf-8"))
    print(p.stdout.strip())
    if p.returncode != 0:
        sys.exit("发布检查未通过，已中止导出")

    gpath = os.path.join(src, "game")
    # 字体按实际用字子集化（release_slim，docs/33 §包体瘦身）：只换打包副本里的字体，仓库原字体不动
    font_rows = release_slim.subset_fonts(gpath)
    release_slim.print_font_rows(font_rows)
    # 无损瘦身（docs/187）：子集字体转 WOFF2 容器（文件名不变，FreeType 按内容识别）；贴图 WebP 无损压到最高档（像素不变，只多花导入时间）
    if not a.no_lossless:
        woff2_fonts(gpath, [r[0] for r in font_rows])
        webp_max(gpath)
    # 网页包专用音频再压缩（tools/web_audio.py，docs/121 §4）：只改打包副本，桌面包与仓库不动；--audio-tier off 关闭
    import web_audio
    freed = web_audio.drop_unused_music(gpath)   # Suno 分层配乐接入后旧乐句文件不进网页包（tools/web_audio.py drop_unused_music）
    if freed:
        print("[瘦身] 旧程序合成配乐（Suno 分层已取代）不进网页包：%.2f MiB" % (freed / 1048576), flush=True)
    if a.audio_tier != "off":
        print("[瘦身] " + web_audio.report(web_audio.shrink(gpath, a.audio_tier)) + "（档位 %s）" % a.audio_tier, flush=True)
    tmp = os.path.join(WORK, "out")
    os.makedirs(tmp)
    run([GODOT, "--headless", "--path", gpath, "--import"], check=False)  # 无头导入退出时偶发崩溃，结果以导出为准
    out = run([GODOT, "--headless", "--path", gpath, "--export-release", "Web", os.path.join(tmp, "index.html")], check=False)
    if not os.path.exists(os.path.join(tmp, "index.pck")):
        print("\n".join(out.splitlines()[-15:]))
        sys.exit("导出失败：缺少 Web 导出模板（web_nothreads_*.zip）？见 docs/22")

    print("[瘦身] pck：%.2f MB" % (os.path.getsize(os.path.join(tmp, "index.pck")) / 1e6), flush=True)
    part = int(a.part_mib * 1048576)
    manifest = {"index.pck": split(tmp, "index.pck", part, a.toy)}
    # wasm：LZMA 分片（docs/187 §5，--wasm-gzip 退回 gzip）；20 MiB 一片，压缩后每片约 3 MiB
    manifest["index.wasm"] = split(tmp, "index.wasm", part if a.wasm_gzip else 20 * 1048576, a.toy, "gzip" if a.wasm_gzip else "lzma")
    sys.path.insert(0, WEB)
    import engine_patch
    engine_patch.patch_index_js(os.path.join(tmp, "index.js"))   # 网页样本释放接口（tools/web/engine_patch.py，docs/50 §40）
    html_p = os.path.join(tmp, "index.html")
    with open(html_p, encoding="utf-8") as fh:
        html = fh.read()
    if MARK not in html:
        sys.exit("index.html 里找不到 %s（Web 预设 html/head_include 被改了？）" % MARK)
    # WebGL 状态缓存（tools/web/gl_state.js，docs/50 §21）：放在最前，引擎建上下文之前就得装好
    with open(os.path.join(WEB, "gl_state.js"), encoding="utf-8") as fh:
        js = fh.read() + "\n"
    # 页面隐藏时挂起音频（tools/web/power.js，docs/50 §33）：也要在引擎建 AudioContext 之前
    with open(os.path.join(WEB, "power.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    # 帧时浮层（tools/web/fps_meter.js，docs/50 §21.7）：只在网址带 ?fps=1 时显示，给真机量帧率
    with open(os.path.join(WEB, "fps_meter.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    # LZMA 解码器（tools/web/lzma_dec.js，本作自写）：加载器解 wasm 分片用，要在 loader.js 之前
    with open(os.path.join(WEB, "lzma_dec.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    with open(os.path.join(WEB, "loader.js"), encoding="utf-8") as fh:
        js += fh.read().replace("/*SHUIYUE_MANIFEST*/null", json.dumps(manifest, separators=(",", ":"))).replace("/*SHUIYUE_BOOT_V*/0", str(_boot_v(src)))   # 启动页方向（balance ui/boot_v）
    # 网页容器适配（B站 Toy 横屏 / 安全区，tools/web/container.js）：接在加载器后面，同一个 <script>
    if a.toy:
        js += "\nwindow.__SY_TOY = 1;   // Toy 包：一律加载 Toy JS SDK（docs/22「Toy 接入」）\n"
    with open(os.path.join(WEB, "container.js"), encoding="utf-8") as fh:
        js += "\n" + fh.read()
    # B站 Toy 云存档的 JS 薄封装（tools/web/cloud.js，docs/89）：非 B站环境 probe 回 unsupported，Godot 侧不启用
    with open(os.path.join(WEB, "cloud.js"), encoding="utf-8") as fh:
        js += "\n" + fh.read()
    # 战绩分享卡（tools/web/share.js）：头像昵称 / 二维码 / 存相册；非 B站环境 probe 全 false，保存退回 <a download>
    with open(os.path.join(WEB, "share.js"), encoding="utf-8") as fh:
        js += "\n" + fh.read()
    with open(os.path.join(WEB, "loader.css"), encoding="utf-8") as fh:
        css = fh.read()
    html = html.replace(MARK, "<style>\n%s</style>\n<script>\n%s</script>" % (css, js))
    with open(html_p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(html)
    shutil.copy2(os.path.join(src, "game", "art", "ui", "title_deep", "logo_mark.png"), os.path.join(tmp, "loader_logo.png"))   # 启动加载页左上标志（loader.css）
    with open(os.path.join(tmp, "build.txt"), "w", encoding="utf-8") as fh:
        fh.write(commit + "\n")

    # 只清空内容不删目录：目录本身可能正被本地静态服务器占着（Windows 删不掉）
    os.makedirs(a.out, exist_ok=True)
    for f in os.listdir(a.out):
        fp = os.path.join(a.out, f)
        shutil.rmtree(fp) if os.path.isdir(fp) else os.remove(fp)
    shutil.copytree(tmp, a.out, dirs_exist_ok=True)
    big = 0
    for f in sorted(os.listdir(a.out)):
        s = os.path.getsize(os.path.join(a.out, f))
        big = max(big, s)
        print("  %-32s %10.2f MiB%s" % (f, s / 1048576, "  ← 超过 25 MB" if s > LIMIT else ""))
    tot = sum(os.path.getsize(os.path.join(a.out, f)) for f in os.listdir(a.out))
    print("完成：%s @ %s，共 %.1f MiB，最大单文件 %.2f MiB" % (a.out, commit, tot / 1048576, big / 1048576))
    if big > LIMIT:
        sys.exit("有文件超过 25 MB 上限")
    if a.toy:
        make_toy_zip(a.out, commit)


def woff2_fonts(gpath, names):
    """打包副本里的子集字体就地换成 WOFF2 内容（docs/187 §3）：字形 / 度量不变，导入后的 fontdata 约小 30%。
    文件名不改（场景 / 主题按路径引用），Godot 的 FreeType 带 brotli，按文件头 wOF2 识别"""
    from fontTools.ttLib import TTFont
    before = after = 0
    for fn in names:
        p = os.path.join(gpath, "fonts", fn)
        before += os.path.getsize(p)
        f = TTFont(p)
        f.flavor = "woff2"
        buf = io.BytesIO()
        f.save(buf)
        with open(p, "wb") as fh:
            fh.write(buf.getvalue())
        after += len(buf.getvalue())
    print("[瘦身] 子集字体转 WOFF2：%.2f MiB → %.2f MiB" % (before / 1048576, after / 1048576), flush=True)


WEBP_MAX = ("textures/webp_compression/compression_method=6\n"
            "textures/webp_compression/lossless_compression_factor=100.0\n")


def webp_max(gpath):
    """打包副本的 project.godot：WebP 无损贴图用最高压缩力度（缺省 2 / 25）。无损，解码像素不变，只是导入慢（docs/187 §3）"""
    p = os.path.join(gpath, "project.godot")
    with open(p, encoding="utf-8") as fh:
        txt = fh.read()
    if "[rendering]\n" not in txt:
        sys.exit("project.godot 里没有 [rendering] 段")
    txt = txt.replace("[rendering]\n", "[rendering]\n\n" + WEBP_MAX, 1)
    # 透明边渗色不在这里改：运行时贴图（game/art）的 .import 已逐张写好（没有 alpha 1–19 淡像素的关、带的开，docs/187 §6、docs/189）
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(txt)
    print("[瘦身] 贴图 WebP 无损压缩力度：方法 6 / 系数 100", flush=True)


TOY_LIMIT = 50 * 1000 * 1000   # Toy 新内测作者 50 MB（docs/99 §0），按十进制算更保守
TOY_GZ_EXT = (".pck", ".wasm")


def make_toy_zip(web, commit):
    """Toy 包：index.html 在 zip 根目录（没有外层文件夹）；gzip 内容的分片按存储放（再压没意义）。不上传，发布由 /toy 技能做。"""
    import zipfile
    out = os.path.join(os.path.dirname(web), "方舟幸存者_toy_%s.zip" % commit)
    files = sorted(f for f in os.listdir(web) if os.path.isfile(os.path.join(web, f)))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for f in files:
            stored = f.endswith(TOY_GZ_EXT) and f != "index.pck" and f != "index.wasm"
            z.write(os.path.join(web, f), f, compress_type=zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED)
    size = os.path.getsize(out)
    exts = sorted(set(os.path.splitext(f)[1] for f in files))
    print("Toy zip：%s  %.2f MB（%d 个文件，后缀 %s）%s" % (out, size / 1e6, len(files), " ".join(exts), "" if size <= TOY_LIMIT else "  ← 超过 50 MB"))
    if size > TOY_LIMIT:
        sys.exit("Toy 包超过 50 MB 上限")


if __name__ == "__main__":
    main()
