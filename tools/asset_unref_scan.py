# -*- coding: utf-8 -*-
"""扫 game/art 与 game/audio 里运行时没有引用的文件（11-06 素材整理）。

引用来源：game/ 下 .gd 字符串字面量、data/*.json 的键与值、.tscn / .tres / project.godot 全文（release_slim.runtime_text）。
判定（任一成立即算引用，宁可漏报不误删）：
  1. 名字（去掉 @1x / @2x、去掉扩展名；带 portraits/ optical_fx/ 前缀的另算）作为子串出现在运行时文本里；
  2. 相对 game/ 的 res:// 路径或 game/art 内相对路径出现在文本里；
  3. 在某个 _ 处切成前后两段，两段各自是完整字符串字面量（"growth_" + id 之类的拼法）；
  4. 格式串（"op_%s_%s" % [...]）匹配；
  5. 同目录里 .tscn / .tres / .import 之外的别名：art.gd 的 ALIAS 字典已在文本里，随 1 覆盖。
用法：python tools/asset_unref_scan.py [--out 清单.tsv]    列出无引用文件、大小与按目录汇总
"""
import argparse, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release_slim as rs

ROOT = rs.ROOT
GAME = rs.GAME
EXT_ART = (".png", ".webp", ".jpg", ".jpeg", ".svg", ".gif", ".ogv", ".tres", ".res")
EXT_AUDIO = (".ogg", ".wav", ".mp3")


def build_blob():
    lits, _ = rs.runtime_text(GAME)
    import glob, json   # game/audio 与 game/art 里的 json（voice_pools.json、suno_layers.json 等）也是引用来源
    for jp in glob.glob(os.path.join(GAME, "audio", "**", "*.json"), recursive=True):
        rs._json_strings(json.load(open(jp, encoding="utf-8")), lits, [])
    blob = "\n".join(lits)
    litset = set(lits)
    fmts = []
    for s in litset:
        if ("%s" in s or "%d" in s) and len(s) < 80 and len(s.replace("%s", "").replace("%d", "")) >= 3 and re.fullmatch(r"[A-Za-z0-9_%@/.]+", s):
            fmts.append(re.compile("".join("[A-Za-z0-9_]+" if t in ("%s", "%d") else re.escape(t) for t in re.split(r"(%s|%d)", s))))
    return blob, litset, fmts


def norm(stem):
    return re.sub(r"@[12]x$", "", stem)


def is_ref(rel, base, blob, litset, fmts):
    """rel = 相对 game/ 的路径（/ 分隔）；base = 去扩展名、去 @Nx 的文件名"""
    if rel in blob or ("res://" + rel) in blob:
        return True
    keys = {base}
    d = rel.split("/")
    if len(d) > 3 and d[1] == "art":
        keys.add("/".join(d[2:-1] + [base]))              # fx/proj/xxx 之类
        for sub, pre in (("enemies/_portraits", "portraits/"), ("fx/_optical", "optical_fx/")):
            if "/".join(d[2:-1]) == sub:
                keys.add(pre + base)
    for k in keys:
        if k in blob:
            return True
    parts = base.split("_")
    for k in range(len(parts) - 1, 0, -1):
        pre, suf = "_".join(parts[:k]), "_".join(parts[k:])
        if (pre + "_" in litset and suf in litset) or (pre in litset and "_" + suf in litset):
            return True
    return any(rx.fullmatch(base) for rx in fmts)


def scan():
    blob, litset, fmts = build_blob()
    out = []
    for sub, exts in (("art", EXT_ART), ("audio", EXT_AUDIO)):
        for dp, dns, fs in os.walk(os.path.join(GAME, sub)):
            for f in sorted(fs):
                if not f.lower().endswith(exts):
                    continue
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, GAME).replace(os.sep, "/")
                base = norm(os.path.splitext(f)[0])
                if not is_ref(rel, base, blob, litset, fmts):
                    sz = os.path.getsize(p)
                    imp = p + ".import"
                    if os.path.exists(imp):
                        sz += os.path.getsize(imp)
                    out.append((rel, sz))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    a = ap.parse_args()
    res = scan()
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as fh:
            for rel, sz in res:
                fh.write("%s\t%d\n" % (rel, sz))
    by = {}
    for rel, sz in res:
        k = "/".join(rel.split("/")[:4])
        c = by.setdefault(k, [0, 0]); c[0] += 1; c[1] += sz
    for k, (n, sz) in sorted(by.items(), key=lambda x: -x[1][1])[:60]:
        print("%8.2f MB %5d  %s" % (sz / 1e6, n, k))
    print("合计 %d 个，%.2f MB" % (len(res), sum(s for _, s in res) / 1e6))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
