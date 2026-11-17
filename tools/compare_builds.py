# -*- coding: utf-8 -*-
"""对比两次出包的产物是否等价（11-17 发版提速验收用）。

    python tools/compare_builds.py web  <旧 web 目录> <新 web 目录>      # itch 网页包 / Toy 网页目录：文件清单、大小、pck 目录逐项 md5
    python tools/compare_builds.py zip  <旧 zip> <新 zip>                # zip 成员清单 + 大小 + CRC
    python tools/compare_builds.py pck  <旧 .pck> <新 .pck>              # 未加密 pck 目录逐项比对

网页目录里的 index.pck / index.wasm 是分片 + gzip / LZMA，按 manifest（loader 里内联的那份不好抠，直接按文件名规则）解回整块再比。
pck 目录项带每个文件的 md5（Godot 写包时算的），逐项比对路径 / 大小 / md5；不同的按扩展名归类列出。
"""
import gzip, hashlib, io, lzma, os, re, struct, sys, zipfile
from collections import Counter


def pck_entries(pk):
    assert pk[:4] == b"GDPC", "不是 Godot pck"
    diro = struct.unpack("<Q", pk[32:40])[0]
    n = struct.unpack("<I", pk[diro:diro + 4])[0]
    p, out = diro + 4, {}
    for _ in range(n):
        ln = struct.unpack("<I", pk[p:p + 4])[0]; p += 4
        path = pk[p:p + ln].rstrip(b"\0").decode("utf-8", "replace"); p += ln
        off, size = struct.unpack("<QQ", pk[p:p + 16]); p += 16
        md5 = pk[p:p + 16].hex(); p += 16
        p += 4
        out[path] = (size, md5)
    return out


def join_parts(d, stem, ext):
    """index.pck.00.gz … / index.00.pck …（Toy）/ index.wasm.00.lzma … 解回整块"""
    names = sorted(f for f in os.listdir(d) if re.fullmatch(r"%s(\.%s\.\d\d\.(gz|lzma)|\.\d\d\.%s)" % (stem, ext, ext), f))
    buf = b""
    for f in names:
        raw = open(os.path.join(d, f), "rb").read()
        buf += gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else lzma.decompress(raw, format=lzma.FORMAT_ALONE)
    return buf, names


def cmp_pck(a, b, label="pck"):
    ea, eb = pck_entries(a), pck_entries(b)
    only_a, only_b = sorted(set(ea) - set(eb)), sorted(set(eb) - set(ea))
    diff = sorted(k for k in set(ea) & set(eb) if ea[k] != eb[k])
    print("%s：旧 %d 项 / 新 %d 项；只在旧 %d，只在新 %d，内容不同 %d；整包 %s" % (label, len(ea), len(eb), len(only_a), len(only_b), len(diff),
          "逐字节相同" if a == b else "字节不同（%d → %d 字节）" % (len(a), len(b))))
    for k in only_a[:20]:
        print("  只在旧：", k)
    for k in only_b[:20]:
        print("  只在新：", k)
    if diff:
        print("  内容不同（按扩展名）：", dict(Counter(os.path.splitext(k)[1] or k for k in diff)))
        for k in diff[:30]:
            print("   ", k, ea[k][0], "→", eb[k][0])
    return not only_a and not only_b and not diff


def cmp_web(da, db):
    fa, fb = sorted(os.listdir(da)), sorted(os.listdir(db))
    print("文件：旧 %d / 新 %d；清单%s" % (len(fa), len(fb), "相同" if fa == fb else "不同：只在旧 %s 只在新 %s" % (sorted(set(fa) - set(fb)), sorted(set(fb) - set(fa)))))
    same_bytes = []
    for f in sorted(set(fa) & set(fb)):
        x, y = open(os.path.join(da, f), "rb").read(), open(os.path.join(db, f), "rb").read()
        if x == y:
            same_bytes.append(f)
        else:
            print("  字节不同：%-34s %10d → %10d" % (f, len(x), len(y)))
    print("  逐字节相同 %d 个" % len(same_bytes))
    pa, _ = join_parts(da, "index", "pck")
    pb, _ = join_parts(db, "index", "pck")
    ok = cmp_pck(pa, pb, "index.pck")
    wa, _ = join_parts(da, "index", "wasm")
    wb, _ = join_parts(db, "index", "wasm")
    print("index.wasm：%s" % ("相同" if wa == wb else "不同"))
    return ok and wa == wb and fa == fb


def cmp_zip(za, zb):
    a, b = zipfile.ZipFile(za), zipfile.ZipFile(zb)
    ia = {i.filename: (i.file_size, i.CRC) for i in a.infolist()}
    ib = {i.filename: (i.file_size, i.CRC) for i in b.infolist()}
    print("zip：旧 %d 个成员 %.2f MB / 新 %d 个 %.2f MB" % (len(ia), os.path.getsize(za) / 1e6, len(ib), os.path.getsize(zb) / 1e6))
    for k in sorted(set(ia) | set(ib)):
        if ia.get(k) != ib.get(k):
            print("  不同：%s %s → %s" % (k, ia.get(k), ib.get(k)))
    return ia == ib


if __name__ == "__main__":
    for st in (sys.stdout, sys.stderr):
        try:
            st.reconfigure(encoding="utf-8")
        except Exception:
            pass
    mode, x, y = sys.argv[1:4]
    ok = {"web": cmp_web, "zip": cmp_zip, "pck": lambda p, q: cmp_pck(open(p, "rb").read(), open(q, "rb").read())}[mode](x, y)
    print("结论：%s" % ("等价" if ok else "有差异（见上）"))
