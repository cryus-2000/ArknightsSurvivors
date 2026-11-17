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
import argparse, datetime, glob, gzip, io, json, lzma, os, re, shutil, subprocess, sys, tarfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release_slim

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")
WORK = os.path.join(ROOT, "build", "_web")
WEB = os.path.join(ROOT, "tools", "web")
LIMIT = 25 * 1000 * 1000  # 平台按 25 MB 计，取十进制更保守
MARK = "<!--SHUIYUE_LOADER-->"
VOICE_LANG_DIRS = ("ja", "en", "ko")   # 外语语音目录 game/audio/voice/<lang>/（tools/voice_lang_1115.py），Toy 包剔除
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


def _compress(args):
    """一片的压缩（子进程里跑）。gzip -9 / LZMA 都是确定性的：同样的输入、同样的参数，输出逐字节相同，并行不改变产物"""
    chunk, enc = args
    if enc == "lzma":
        data = lzma.compress(chunk, format=lzma.FORMAT_ALONE, filters=LZMA_FILTERS)
        assert lzma.decompress(data, format=lzma.FORMAT_ALONE) == chunk, "LZMA 回读不符"
        return data
    return gzip.compress(chunk, compresslevel=9, mtime=0)


_POOL = None
_MEMO = {}   # (sha256(片), enc) → 压缩结果：itch 网页包与 Toy 包的 index.wasm 完全相同，第二次直接复用


def _pool():
    global _POOL
    if _POOL is None:
        from concurrent.futures import ProcessPoolExecutor
        _POOL = ProcessPoolExecutor(max_workers=max(1, min(8, (os.cpu_count() or 4) // 2)))
    return _POOL


def split(out_dir, name, part_bytes, toy=False, enc="gzip"):
    """enc="lzma"（index.wasm，docs/187 §5）：分片用 .lzma alone 格式，加载器用 tools/web/lzma_dec.js 解；比 gzip -9 小约 3 MiB。
    各片并行压缩（11-17 发版提速），文件名 / 内容与串行时逐字节相同"""
    import hashlib
    path = os.path.join(out_dir, name)
    with open(path, "rb") as fh:
        raw = fh.read()
    stem, ext = os.path.splitext(name)
    suf = ".lzma" if enc == "lzma" else ".gz"
    chunks = [raw[i:i + part_bytes] for i in range(0, len(raw), part_bytes)]
    keys = [(hashlib.sha256(c).hexdigest(), enc) for c in chunks]
    todo = [(k, c) for k, c in zip(keys, chunks) if k not in _MEMO]
    for (k, _), data in zip(todo, _pool().map(_compress, [(c, enc) for _, c in todo])):
        _MEMO[k] = data
    parts = []
    for i, (chunk, k) in enumerate(zip(chunks, keys)):
        pn = ("%s.%02d%s" % (stem, i, ext)) if toy else ("%s.%02d%s" % (name, i, suf))
        data = _MEMO[k]
        with open(os.path.join(out_dir, pn), "wb") as fh:
            fh.write(data)
        parts.append([pn, len(data), len(chunk)])   # [文件名, 压缩字节, 原始字节]：加载器按原始长度直接写进整块
    os.remove(path)
    m = {"size": len(raw), "type": TYPES[name], "parts": parts}
    if enc == "lzma":
        m["enc"] = "lzma"
    return m


TOY_DROP_MSG = "[瘦身] Toy 版不带英文 / 日文 / 韩文：翻译表与日韩字体 %.2f MiB 不进包（itch 网页包会带）"
TOY_VOICE_MSG = "[瘦身] Toy 版不带日 / 英 / 韩语音：%.2f MiB 不进包（itch 包会带）"


def _dir_bytes(d):
    return sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(d) for f in fs) if os.path.isdir(d) else 0


def toy_strip(src, binfo):
    """Toy 版与 itch 网页版的源码差异（docs/276 §12）：build.json 锁中文、翻译表与日韩字体、外语语音不进包。
    binfo 就地改；写 build.json 由调用方做。旧流程（--toy）在导入前做，--toy-out 共用导出时在 itch 包导出之后做"""
    binfo["lang_lock"] = "zh"
    l10n_dir = os.path.join(src, "game", "l10n")
    l10n_b = _dir_bytes(l10n_dir)
    shutil.rmtree(l10n_dir, ignore_errors=True)
    # 导入后 pck 里的翻译表与源 CSV 大小相近（compress=0）；网页包另有 gzip，实际下载少得更少
    print(TOY_DROP_MSG % (l10n_b / 1048576), flush=True)
    # 外语语音（11-15，audio/voice/<ja|en|ko>/，tools/voice_lang_1115.py）只进 itch 包；Toy 版语音固定中文（Cfg.voice_lang）
    vl_b = 0
    for vl in VOICE_LANG_DIRS:
        vd = os.path.join(src, "game", "audio", "voice", vl)
        vl_b += _dir_bytes(vd)
        shutil.rmtree(vd, ignore_errors=True)
    print(TOY_VOICE_MSG % (vl_b / 1048576), flush=True)


def toy_assert_src(src):
    bj = os.path.join(src, "game", "data", "build.json")
    chk_b = json.load(open(bj, encoding="utf-8"))
    assert chk_b.get("lang_lock") == "zh" and not os.path.exists(os.path.join(src, "game", "l10n")), "Toy 包必须锁中文且不带 game/l10n"
    assert not any(os.path.exists(os.path.join(src, "game", "audio", "voice", vl)) for vl in VOICE_LANG_DIRS), "Toy 包不带外语语音"


def toy_drop_sd(gpath):
    """同 web_half.make(sd_half_only=True) 的最后一步：斯卡蒂终结技图集原图（及 .import）不进 Toy 包，只留 ult_sd_half"""
    import web_half
    sd = os.path.join(gpath, "art", "fx", "pxp", "ult_sd")
    if os.path.isdir(sd) and os.path.isdir(sd + "_half"):
        for f in os.listdir(sd):
            if f.endswith(".png"):
                web_half._rm(os.path.join(sd, f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="HEAD")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "web"))
    ap.add_argument("--part-mib", type=float, default=10)
    ap.add_argument("--worktree-presets", action="store_true", help="用工作区的 export_presets.cfg（改预设时本地试导出用）")
    ap.add_argument("--audio-tier", default="C", choices=["off", "A", "B", "C", "D", "E"], help="网页包音频再压缩档位（tools/web_audio.py：A 近无损 / B 平衡 / C 缺省（10-28 用户定，B 可回退） / D、E 试听档（docs/187 §7）；off = 不压）")
    ap.add_argument("--final-tier", default="D", choices=["C", "D", "E"], help="最终 Boss 8 首配乐的单独档位（tools/web_audio.py FINAL_TIERS；11-06 用户批 D，docs/285 §3）；只在 --audio-tier C 时生效")
    ap.add_argument("--wasm-gzip", action="store_true", help="index.wasm 分片退回 gzip（缺省 LZMA，docs/187 §5）")
    ap.add_argument("--no-web-lossy", action="store_true", help="关掉网页专用的近无损压缩（事件插画有损 WebP 0.85、音效 32 kHz 上限，docs/187 §8），对照用")
    ap.add_argument("--no-lossless", action="store_true", help="关掉无损瘦身（字体 WOFF2 + WebP 无损最高档，docs/187），对照用")
    ap.add_argument("--ea", action="store_true", help="对内网页版：build.json audience = internal（演练开、全部解锁）")
    ap.add_argument("--god", action="store_true", help="无敌测试包：build.json test_god=true（队长生命归零回满，Cfg.test_god）；Toy zip 文件名加 _god。只给真机测内存用，不要提交审核 / 对外发布")
    ap.add_argument("--toy", action="store_true", help="B站 Toy 包：一律加载 Toy SDK、分片不带 .gz 后缀、另打 zip（缺省输出 build/toy/web）")
    ap.add_argument("--toy-out", help="同一次导入再出一份 Toy 包到这个目录（itch 网页版导出后改源码再导出一次，翻译表 / 外语语音 / 斯卡蒂原图在第二次导出前删掉；zip 在它的上一级目录），产物与单独跑 --toy 相同（11-17 发版提速）")
    ap.add_argument("--timing", action="store_true", help="每步打印耗时")
    a = ap.parse_args()
    if a.toy and a.toy_out:
        sys.exit("--toy 与 --toy-out 不能同时用")
    if a.toy_out and a.god:
        sys.exit("--toy-out 不支持 --god（无敌包单独跑 --toy --god）")
    if a.toy and a.out == os.path.join(ROOT, "build", "web"):
        a.out = os.path.join(ROOT, "build", "toy", "web")

    commit = run(["git", "-C", ROOT, "rev-parse", "--short", a.ref]).strip()
    t_last = [time.time()]

    def lap(name):
        now = time.time()
        if a.timing:
            print("[耗时] %s %.0f 秒" % (name, now - t_last[0]), flush=True)
        t_last[0] = now
    shutil.rmtree(WORK, ignore_errors=True)
    src = os.path.join(WORK, "src")
    os.makedirs(src)
    data = subprocess.run(["git", "archive", "--format=tar", a.ref, "game", "art/source/voice", "tools"], cwd=ROOT, stdout=subprocess.PIPE, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(data)).extractall(src, filter="data")
    import asset_index
    asset_index.write(os.path.join(src, "game", "art"))   # 运行时贴图索引不进 git（docs/364 §5）：解出来先按副本里的贴图重建（瘦身 / 半分辨率 / Toy 都读它）
    import godot_runner
    godot_runner.disable_mcp_in_copy(os.path.join(src, "game"))   # 并行导出时别抢 MCP 端口（addons/ 不进包）
    import import_cache
    import_cache.prewarm_tree(src, "源码")   # 新解出的文件首读要过实时防护扫描：并行先读一遍（import_cache.prewarm_tree）
    if a.worktree_presets:
        shutil.copy2(os.path.join(ROOT, "game", "export_presets.cfg"), os.path.join(src, "game", "export_presets.cfg"))
    # 运行时贴图都在 game/art（docs/189），随 pck 走；网页包（Toy 50 MB）不带干员 @2x 回退条，游戏读 @1x（docs/128）
    _, freed = release_slim.prune_game_art(os.path.join(src, "game"), drop_fallback=True)
    print("[瘦身] 干员 @2x 回退条 + 转平面旧做法对照帧条不进网页包：%.2f MB" % (freed / 1e6))
    print("源码：%s @ %s" % (a.ref, commit))
    # 构建信息（同 export_build.py）：局内记录的版本号、发布对象；演练入口与全部解锁按 audience 判断
    bj = os.path.join(src, "game", "data", "build.json")
    binfo = json.load(open(bj, encoding="utf-8")) if os.path.exists(bj) else {"version": "dev"}
    binfo.update({"commit": commit, "built": datetime.datetime.now().strftime("%Y%m%d"), "audience": "internal" if a.ea else "public", "encrypted": False, "platform": "web"})
    if a.god:
        binfo["test_god"] = True
        # 自动模式（网址 auto=1，run/auto_play.gd）要机器人：无敌包保留 bot.gd（正式包仍按预设剔除）
        ep = os.path.join(src, "game", "export_presets.cfg")
        txt = open(ep, encoding="utf-8").read()
        txt2 = txt
        for keep in ("scripts/core/bot.gd*", "scripts/run/auto_play.gd*", "scripts/core/god_suite.gd*"):
            txt2 = txt2.replace(", " + keep, "").replace(keep + ", ", "")
        if txt2 == txt:
            sys.exit("无敌包：export_presets.cfg 里没找到 scripts/core/bot.gd* 排除项（改名了要同步）")
        open(ep, "w", encoding="utf-8").write(txt2)
        print("[无敌包] 保留 bot.gd / auto_play.gd / god_suite.gd（自动模式与连测）")
    else:
        binfo.pop("test_god", None)
    if a.ea:
        binfo["channel"] = "EA"
    else:
        binfo.pop("channel", None)
    # 多语言只上 itch（Windows / html5），B站 Toy 版固定中文（11-11 用户经协调人，docs/276 §12）：
    # build.json 写 lang_lock = zh（settings.gd lang_locked 读），翻译表整个不进 Toy 包
    if a.toy:
        toy_strip(src, binfo)
    else:
        binfo.pop("lang_lock", None)
    with open(bj, "w", encoding="utf-8") as fh:
        json.dump(binfo, fh, ensure_ascii=False, indent=1)
    if a.toy:   # 导出断言：Toy 包切不到英文
        toy_assert_src(src)
    print("构建信息：audience=%s%s" % (binfo["audience"], "，语言锁中文" if a.toy else ""))

    # 发布检查（玩法系统 tools/check_release.py，docs/33 清单）：对即将打包的这份源码跑，不过就中止
    chk = os.path.join(src, "tools", "check_release.py")
    p = subprocess.run([sys.executable, chk], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", env=dict(os.environ, PYTHONIOENCODING="utf-8"))
    print(p.stdout.strip())
    if p.returncode != 0:
        sys.exit("发布检查未通过，已中止导出")

    gpath = os.path.join(src, "game")
    lap("解源码 + 发布检查")
    # 半分辨率贴图（tools/web_half.py，docs/319 §16）：整 2 倍放大的 @2x 换 1 倍；有细节的特效另出 @h、斯卡蒂终结技图集出半分辨率给手机。
    # 只动 art/fx、art/enemies、art/index.json、data/pxp_*.json，和下面的字体 / 音频步骤不碰同一批文件：放到子进程里同时做（11-17 发版提速，约省 50 秒）
    half_job = _pool().submit(_web_half_job, gpath, a.toy)   # Toy 包：斯卡蒂终结技只留半分辨率版（约 −2.1 MB）
    # 字体按实际用字子集化（release_slim，docs/33 §包体瘦身）：只换打包副本里的字体，仓库原字体不动
    font_rows = release_slim.subset_fonts(gpath)
    release_slim.print_font_rows(font_rows)
    # 无损瘦身（docs/187）：子集字体转 WOFF2 容器（文件名不变，FreeType 按内容识别）；贴图 WebP 无损压到最高档（像素不变，只多花导入时间）
    if not a.no_lossless:
        woff2_fonts(gpath, [r[0] for r in font_rows])
        webp_max(gpath)
        script_text_export(gpath)
    if not a.no_web_lossy:
        web_lossy_assets(gpath)
    lap("字体 / 脚本 / 近无损")
    # 网页包专用音频再压缩（tools/web_audio.py，docs/121 §4）：只改打包副本，桌面包与仓库不动；--audio-tier off 关闭
    os.environ.setdefault("ARK_AUDIO_ENC_CACHE", os.path.join(ROOT, "build", "_import_cache", "audio_enc"))   # 重编码结果复用（web_audio.encode）；要在 import web_audio 之前设
    import web_audio
    freed = web_audio.drop_unused_music(gpath)   # Suno 分层配乐接入后旧乐句文件不进网页包（tools/web_audio.py drop_unused_music）
    if freed:
        print("[瘦身] 旧程序合成配乐（Suno 分层已取代）不进网页包：%.2f MiB" % (freed / 1048576), flush=True)
    if a.audio_tier != "off":
        print("[瘦身] " + web_audio.report(web_audio.shrink(gpath, a.audio_tier, a.final_tier)) + "（档位 %s，最终 Boss %s）" % (a.audio_tier, a.final_tier), flush=True)
        web_audio.prune_encode_cache()
    lap("音频再压缩")
    tmp = os.path.join(WORK, "out")
    os.makedirs(tmp)
    # 长配乐出包（tools/web_music.py，docs/319 §12）：不进 index.pck，单独 AAC 由浏览器解码（不在 WASM 堆里整段解码）
    import web_music
    print("[瘦身] " + web_music.report(web_music.externalize(gpath, tmp)), flush=True)
    lap("配乐出包")
    print("[瘦身] " + half_job.result(), flush=True)
    lap("等半分辨率贴图")
    pack_px_metadata(gpath)
    cache_keys, _ = import_cache.restore(gpath, "web", GODOT)   # 导入缓存复用（tools/import_cache.py，docs/33 §发版提速）
    import_cache.prewarm_tree(gpath, "导入前")   # 瘦身步骤新写的文件
    extra = sorted(os.listdir(tmp))   # 导出前已在 out/ 里的文件（出包配乐 .m4a）：Toy 那次导出也要
    lap("导入缓存放回 + 预读")
    run([GODOT, "--headless", "--path", gpath, "--import"], check=False)  # 无头导入退出时偶发崩溃，结果以导出为准
    lap("Godot 导入")
    godot_export(gpath, tmp)
    lap("Godot 导出")
    import_cache.save(gpath, "web", cache_keys)
    finish(a, tmp, a.out, a.toy, commit, src)
    lap("分片压缩 + 加载器")
    if a.toy_out:
        # 同一次导入出 Toy 包（11-17 发版提速）：源码按 --toy 的差异改（build.json 锁中文、删翻译表 / 日韩字体 / 外语语音 / 斯卡蒂原图），
        # 不再重导入，直接再导出一次；Godot 导出前的扫描会把删掉的文件从资源表里去掉
        print("\n== Toy 包（共用导入）==", flush=True)
        bj = os.path.join(src, "game", "data", "build.json")
        binfo = json.load(open(bj, encoding="utf-8"))
        toy_strip(src, binfo)
        with open(bj, "w", encoding="utf-8") as fh:
            json.dump(binfo, fh, ensure_ascii=False, indent=1)
        toy_assert_src(src)
        toy_drop_sd(gpath)
        print("构建信息：audience=%s，语言锁中文" % binfo["audience"])
        tmp2 = os.path.join(WORK, "out_toy")
        os.makedirs(tmp2)
        for f in extra:
            shutil.copy2(os.path.join(a.out, f), os.path.join(tmp2, f))   # itch 那份已拷到 a.out，内容没动过
        godot_export(gpath, tmp2)
        lap("Godot 导出（Toy）")
        finish(a, tmp2, a.toy_out, True, commit, src)
        lap("分片压缩 + 加载器（Toy）")
    if _POOL is not None:
        _POOL.shutdown()


def _web_half_job(gpath, toy):
    """子进程里跑 web_half.make（见 main 里 half_job）；返回报告行"""
    import web_half
    return web_half.report(web_half.make(gpath, sd_half_only=toy))


def godot_export(gpath, tmp):
    out = run([GODOT, "--headless", "--path", gpath, "--export-release", "Web", os.path.join(tmp, "index.html")], check=False)
    if not os.path.exists(os.path.join(tmp, "index.pck")):
        print("\n".join(out.splitlines()[-15:]))
        sys.exit("导出失败：缺少 Web 导出模板（web_nothreads_*.zip）？见 docs/22")


def finish(a, tmp, out_dir, toy, commit, src):
    """导出之后：Toy 断言 → 分片压缩 → 拼加载器 → 拷到 out_dir → 大小检查 → Toy zip（itch 与 Toy 两份共用）"""
    print("[瘦身] pck：%.2f MB" % (os.path.getsize(os.path.join(tmp, "index.pck")) / 1e6), flush=True)
    if toy:   # 导出断言（docs/276 §12）：Toy 包里没有英文资源（翻译表路径一个都不能出现）
        with open(os.path.join(tmp, "index.pck"), "rb") as fh:
            pk = fh.read()
        # 查具体资源文件名（loc.gd 源码里有 "res://l10n/%s.en.translation" 格式串，不能只查 l10n/）
        mods = sorted({f.split(".")[0] for f in os.listdir(os.path.join(ROOT, "game", "l10n")) if f.endswith(".csv")} |
                      {"ops", "enemies", "ui", "relics", "events", "meta", "run", "extra"}) if os.path.isdir(os.path.join(ROOT, "game", "l10n")) else \
               ["ops", "enemies", "ui", "relics", "events", "meta", "run", "extra"]
        # 11-16：按 pck 目录里的文件路径查（格式同 tools/web_pck_report.py），不再按字节搜整包——
        # 脚本源码进包，settings_panel.gd / sfx.gd 里的 "l10n/ui_ko.otf"、"audio/voice/%s/" 字面量会被误判成资源（e6ab2c50f 起 Toy 导出因此中止）
        paths = pck_paths(pk)
        bad = [m for m in mods
               if any(("l10n/%s.%s.translation" % (m, lg)) in q for q in paths for lg in ("en", "ja", "ko")) or any(("l10n/%s.csv" % m) in q for q in paths)]
        bad += [f for f in ("ui_ja.otf", "ui_ko.otf") if any(("l10n/" + f) in q or ("/" + f + "-") in q for q in paths)]   # 日文 / 韩文回退字体（docs/276 §13 / §14）：源文件、.import 或导入产物
        bad += ["audio/voice/%s/" % vl for vl in VOICE_LANG_DIRS if any(("audio/voice/%s/" % vl) in q for q in paths)]   # 外语语音（11-15）
        assert not bad, "Toy 包里出现了英文翻译资源：%s" % bad
        print("[检查] Toy 包不含英文翻译资源", flush=True)
    part = int(a.part_mib * 1048576)
    manifest = {"index.pck": split(tmp, "index.pck", part, toy)}
    # wasm：LZMA 分片（docs/187 §5，--wasm-gzip 退回 gzip）；20 MiB 一片，压缩后每片约 3 MiB
    manifest["index.wasm"] = split(tmp, "index.wasm", part if a.wasm_gzip else 20 * 1048576, toy, "gzip" if a.wasm_gzip else "lzma")
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
    if toy:
        js += "\nwindow.__SY_TOY = 1;\n"
    # 页面隐藏时挂起音频（tools/web/power.js，docs/50 §33）：也要在引擎建 AudioContext 之前
    with open(os.path.join(WEB, "power.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    # 出包配乐的浏览器解码播放（tools/web/web_music.js，docs/319 §12）
    with open(os.path.join(WEB, "web_music.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    # 帧时浮层（tools/web/fps_meter.js，docs/50 §21.7）：只在网址带 ?fps=1 时显示，给真机量帧率
    with open(os.path.join(WEB, "fps_meter.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    # 性能自检浮层的 WASM 内存读数（tools/web/perf_probe.js，core/perf_hud.gd）：引擎实例化之前装好
    with open(os.path.join(WEB, "perf_probe.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    # LZMA 解码器（tools/web/lzma_dec.js，本作自写）：加载器解 wasm 分片用，要在 loader.js 之前
    with open(os.path.join(WEB, "lzma_dec.js"), encoding="utf-8") as fh:
        js += fh.read() + "\n"
    with open(os.path.join(WEB, "loader.js"), encoding="utf-8") as fh:
        js += fh.read().replace("/*SHUIYUE_MANIFEST*/null", json.dumps(manifest, separators=(",", ":"))).replace("/*SHUIYUE_BOOT_V*/0", str(_boot_v(src)))   # 启动页方向（balance ui/boot_v）
    # 网页容器适配（B站 Toy 横屏 / 安全区，tools/web/container.js）：接在加载器后面，同一个 <script>
    with open(os.path.join(WEB, "container.js"), encoding="utf-8") as fh:
        js += "\n" + fh.read()
    # B站 Toy 云存档的 JS 薄封装（tools/web/cloud.js，docs/89）：非 B站环境 probe 回 unsupported，Godot 侧不启用
    with open(os.path.join(WEB, "cloud.js"), encoding="utf-8") as fh:
        js += "\n" + fh.read()
    # 战绩分享卡（tools/web/share.js）：头像昵称 / 二维码 / 存相册；非 B站环境 probe 全 false，保存退回 <a download>
    with open(os.path.join(WEB, "share.js"), encoding="utf-8") as fh:
        js += "\n" + fh.read()
    # Toy「支持作者」奖励（tools/web/support.js，docs/313）：关注 / 三连状态只读查询；非 B站环境 check 回 unsupported
    with open(os.path.join(WEB, "support.js"), encoding="utf-8") as fh:
        js += "\n" + fh.read()
    with open(os.path.join(WEB, "loader.css"), encoding="utf-8") as fh:
        css = fh.read()
    # 首帧壳（tools/web/boot_shell.html，11-16 B站 App 黑屏）：纯 HTML / CSS 插在 <body> 最前，不等脚本 / rAF 就有画面、进度和「重新加载」
    # 多语言（tools/web_loader_l10n.py，11-16）：壳里四种语言的固定文字 + 按渠道填反馈提示（Toy 私信 UP 主 / itch 评论区）
    import web_loader_l10n
    shell = web_loader_l10n.shell_html(ROOT, toy)
    if html.count("<body>") != 1:
        sys.exit("index.html 里 <body> 不是恰好一处，首帧壳插不进去")
    html = html.replace("<body>", "<body>\n" + shell, 1)
    # 加载期错误捕获（tools/web/boot_err.js，11-16）：单独一个 <script>、放在最前——后面那一大块有语法错 / 运行错时也能把原因写到首帧壳上
    with open(os.path.join(WEB, "boot_err.js"), encoding="utf-8") as fh:
        boot_err = fh.read().replace("/*SY_BUILD*/''", json.dumps(commit))   # 诊断卡上的包版本（同 build.txt）
    # 加载页语言（tools/web/boot_l10n.js）：最先跑，选好语言再画壳；Toy 包锁中文、不带外语字典
    boot_l10n = web_loader_l10n.boot_js(ROOT, toy)
    html = html.replace(MARK, "<script>\n%s</script>\n<script>\n%s</script>\n<style>\n%s</style>\n<script>\n%s</script>" % (boot_l10n, boot_err, css, js))
    with open(html_p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(html)
    shutil.copy2(os.path.join(src, "game", "art", "ui", "title_deep", "logo_mark.png"), os.path.join(tmp, "loader_logo.png"))   # 启动加载页左上标志（loader.css）
    for a2, b2 in (("bg.png", "rl_bg.png"), ("jelly_0.png", "rl_j0.png"), ("jelly_1.png", "rl_j1.png"), ("jelly_2.png", "rl_j2.png")):   # 局间重载的「潮汐航标」载入页（loader.js rlPage，docs/319 §21）
        shutil.copy2(os.path.join(src, "game", "art", "ui", "title_deep", a2), os.path.join(tmp, b2))
    shutil.copy2(os.path.join(src, "game", "art", "ui", "rhodes_logo_src.png"), os.path.join(tmp, "loader_rhodes.png"))   # 方向 4 PRTS 认证终端的罗德岛标志（loader.js p4Init）
    with open(os.path.join(tmp, "build.txt"), "w", encoding="utf-8") as fh:
        fh.write(commit + "\n")

    # 只清空内容不删目录：目录本身可能正被本地静态服务器占着（Windows 删不掉）
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        fp = os.path.join(out_dir, f)
        shutil.rmtree(fp) if os.path.isdir(fp) else os.remove(fp)
    shutil.copytree(tmp, out_dir, dirs_exist_ok=True)
    big = 0
    for f in sorted(os.listdir(out_dir)):
        s = os.path.getsize(os.path.join(out_dir, f))
        big = max(big, s)
        print("  %-32s %10.2f MiB%s" % (f, s / 1048576, "  ← 超过 25 MB" if s > LIMIT else ""))
    tot = sum(os.path.getsize(os.path.join(out_dir, f)) for f in os.listdir(out_dir))
    print("完成：%s @ %s，共 %.1f MiB，最大单文件 %.2f MiB" % (out_dir, commit, tot / 1048576, big / 1048576))
    if big > LIMIT:
        sys.exit("有文件超过 25 MB 上限")
    if toy:
        make_toy_zip(out_dir, commit + ("_god" if a.god else ""))


def pck_paths(pk):
    """Godot pck 目录里的全部文件路径（GDPC：头里 file_base / dir_offset，目录项 = 路径长度 + 路径 + 偏移 / 大小 / md5 / 标志）"""
    import struct
    assert pk[:4] == b"GDPC", "不是 Godot pck"
    diro = struct.unpack("<Q", pk[32:40])[0]
    n = struct.unpack("<I", pk[diro:diro + 4])[0]
    p, out = diro + 4, []
    for _ in range(n):
        ln = struct.unpack("<I", pk[p:p + 4])[0]; p += 4
        out.append(pk[p:p + ln].rstrip(b"\0").decode("utf-8", "replace")); p += ln
        p += 8 + 8 + 16 + 4
    assert n > 100 and any(q.endswith("project.binary") for q in out), "pck 目录解析异常"
    return out


def woff2_fonts(gpath, names):
    """打包副本里的子集字体就地换成 WOFF2 内容（docs/187 §3）：字形 / 度量不变，导入后的 fontdata 约小 30%。
    文件名不改（场景 / 主题按路径引用），Godot 的 FreeType 带 brotli，按文件头 wOF2 识别"""
    from fontTools.ttLib import TTFont
    before = after = 0
    for fn in names:
        p = os.path.join(gpath, "fonts", fn)
        before += os.path.getsize(p)
        f = TTFont(p, recalcTimestamp=False)   # 同 release_slim.subset_bytes：字节可复现，导入缓存才命中
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


def strip_line_comments(src):
    """去掉 GDScript 的整行注释（首个非空白字符是 #，且不在三引号字符串里），换成空行——行号不变，报错行号对得上。
    行尾注释、字符串内容一律不动"""
    out, q = [], None
    for ln in src.split("\n"):
        if q is None and ln.lstrip().startswith("#"):
            out.append("")
            continue
        out.append(ln.rstrip() if q is None else ln)
        i = 0
        while i < len(ln):
            if q is None and ln[i] == "#":
                break   # 行尾注释（之后的三引号不算）
            if q is None and ln[i] in "\"'" and ln[i:i + 3] not in ('"""', "'''"):
                c = ln[i]; i += 1   # 单行字符串：跳到配对引号
                while i < len(ln) and ln[i] != c:
                    i += 2 if ln[i] == "\\" else 1
                i += 1
                continue
            t = ln[i:i + 3]
            if t in ('"""', "'''") and (q is None or q == t):
                q = t if q is None else None
                i += 3
                continue
            if q is not None and ln[i] == "\\":
                i += 2
                continue
            i += 1
    return "\n".join(out)


def pack_px_metadata(gpath):
    """Web MEMFS keeps the entire PCK; inflate each operator's metadata only on first use."""
    for path in sorted(glob.glob(os.path.join(gpath, "data", "pxp_*.json"))):
        with open(path, "rb") as source:
            packed = gzip.compress(source.read(), compresslevel=9, mtime=0)
        with open(path + ".gz", "wb") as target:
            target.write(packed)
        os.remove(path)


def script_text_export(gpath):
    """网页包脚本按源码导出（Web 预设 script_export_mode 2 → 0），并去掉整行注释（docs/309）。
    11-07 实测 Toy 包：压缩二进制令牌逐个脚本各压一遍，合计 4.87 MiB，整包 gzip 压不动；不压缩令牌 17.6 MiB、整包 gzip 后 5.03 MiB 更大；
    源码去整行注释后整包 gzip 约 2 MiB。令牌模式加载时同样要解析 + 编译，只省了分词，运行行为与加载开销基本一样"""
    p = os.path.join(gpath, "export_presets.cfg")
    with open(p, encoding="utf-8") as fh:
        txt = fh.read()
    # 各段以「[preset.N]」/「[preset.N.options]」开头；script_export_mode 在 [preset.N] 段里，同段有 name="Web"
    parts = re.split(r"(?m)^(?=\[preset\.)", txt)
    k = next((n for n, sec in enumerate(parts) if re.match(r"\[preset\.\d+\]\n", sec) and '\nname="Web"\n' in sec), -1)
    if k < 0:
        sys.exit("export_presets.cfg 里找不到 Web 预设")
    if "script_export_mode=2\n" not in parts[k]:
        sys.exit("Web 预设里没有 script_export_mode=2（预设改过？）")
    parts[k] = parts[k].replace("script_export_mode=2\n", "script_export_mode=0\n", 1)
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("".join(parts))
    before = after = 0
    for f in glob.glob(os.path.join(gpath, "**", "*.gd"), recursive=True):
        with open(f, encoding="utf-8") as fh:
            src = fh.read()
        dst = strip_line_comments(src)
        before += len(src.encode("utf-8")); after += len(dst.encode("utf-8"))
        with open(f, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(dst)
    print("[瘦身] 网页包脚本按源码导出、去整行注释：%.2f → %.2f MiB（未压缩）" % (before / 1048576, after / 1048576), flush=True)


CG_LOSSY_Q = 0.85   # 事件插画网页版（art/event_cg/web）有损 WebP 质量：源图本来就是有损 WebP，按无损导入反而翻倍（docs/187 §8）
SFX_MAX_HZ = 32000   # 音效采样率上限：只对 16 kHz 以上能量 < 3% 的文件设，QOA 体积按采样数线性下降（docs/187 §8）
SFX_HF_MAX = 0.03
# 按类别的音效采样率上限（11-06 用户「先去做语音和音效降采样」，Toy 50 MB 线）：细碎音效 22.05 kHz，
# 终结技与低频重击要保厚度单列 24 kHz。现状 2.84 MiB（QOA）→ 约 2.44（−0.40）；全部是单声道，不用转
SFX_CAP_HZ = 22050
SFX_HEAVY_HZ = 24000
SFX_HEAVY = ("ult_", "boom", "hurt_heavy", "break_", "ishar_land_break")


def sfx_cap(name):
    return SFX_HEAVY_HZ if name.startswith(SFX_HEAVY) else SFX_CAP_HZ


SFX_LOW_HZ = 22050   # 11 kHz 以上能量 < 0.3% 的音效再降到 22.05 kHz（11-02，docs/187 §10）
SFX_LOW_HF_MAX = 0.003


def _set_import(path, kv):
    """改 .import 的 [params] 键值（有就替换、没有就追加）"""
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    for k, v in kv.items():
        for i, ln in enumerate(lines):
            if ln.startswith(k + "="):
                lines[i] = "%s=%s" % (k, v)
                break
        else:
            lines.insert(lines.index("[params]") + 1, "%s=%s" % (k, v))
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))


def web_lossy_assets(gpath):
    """网页包专用的近无损压缩（10-31 第八批超预算，docs/187 §8）。只改打包副本的 .import，桌面包与仓库不动：
    - 事件插画 art/event_cg/web/*.webp：源图本身是有损 WebP（合计 1.24 MiB），缺省按无损重编后 2.48 MiB；改有损导入 0.85（相对源图 PSNR 中位 40.4 dB、最低 37.8）。
    - 音效 audio/sfx/*.wav：几乎没有 11 kHz 以上内容的降到 22.05 kHz；其余按类别设上限（11-06：细碎 22.05 kHz，终结技 / 重击 24 kHz，sfx_cap），QOA 按采样数缩小"""
    import numpy as np
    import soundfile as sf
    n_cg = 0
    for f in sorted(glob.glob(os.path.join(gpath, "art", "event_cg", "web", "*.webp.import"))):
        _set_import(f, {"compress/mode": "1", "compress/lossy_quality": str(CG_LOSSY_Q)})
        n_cg += 1
    n_sfx = 0
    for f in sorted(glob.glob(os.path.join(gpath, "audio", "sfx", "*.wav"))):
        if not os.path.exists(f + ".import"):
            continue
        x, sr = sf.read(f, always_2d=True)
        if sr <= SFX_LOW_HZ:
            continue
        X = np.abs(np.fft.rfft(x.mean(1))) ** 2
        fr = np.fft.rfftfreq(len(x), 1.0 / sr)
        tot = max(X.sum(), 1e-12)
        if X[fr > SFX_LOW_HZ / 2].sum() < SFX_LOW_HF_MAX * tot:
            _set_import(f + ".import", {"force/max_rate": "true", "force/max_rate_hz": str(SFX_LOW_HZ)})
            n_sfx += 1
        else:
            cap = sfx_cap(os.path.basename(f)[:-4])
            if sr > cap:
                _set_import(f + ".import", {"force/max_rate": "true", "force/max_rate_hz": str(cap)})
                n_sfx += 1
    print("[瘦身] 网页近无损：事件插画 %d 张改有损 WebP %.2f；音效 %d 个设采样率上限（%d / 重击与终结技 %d Hz）" % (n_cg, CG_LOSSY_Q, n_sfx, SFX_CAP_HZ, SFX_HEAVY_HZ), flush=True)


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
