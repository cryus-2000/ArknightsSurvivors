# -*- coding: utf-8 -*-
"""网页包 pck 分类体积报告（docs/285，11-06）：读 build/release/final_<sha>/web 的 index.pck.NN.gz，拆出 pck 条目，按类别汇总（压缩体积 = zlib 6 级估算，和浏览器 gzip 同量级）。
用法：python tools/web_pck_report.py <web 目录> [<web 目录> …]     多个目录并排对比（例：旧版 / 新版）
类别靠导入文件名前缀 / 扩展名判断（.godot/imported/<名>.png-<md5>.ctex 去掉哈希后按名字前缀分），新前缀要在 cat() 里补。
"""
import gzip, struct, glob, os, re, sys, zlib, collections


def read_entries(webdir):
    data = b"".join(gzip.open(f).read() for f in sorted(glob.glob(os.path.join(webdir, "index.pck.*.gz"))))
    assert data[:4] == b"GDPC", "不是 Godot pck"
    ver = struct.unpack("<I", data[4:8])[0]
    fb, diro = struct.unpack("<QQ", data[24:40])
    n = struct.unpack("<I", data[diro:diro + 4])[0]
    p = diro + 4
    out = []
    for _ in range(n):
        L = struct.unpack("<I", data[p:p + 4])[0]; p += 4
        path = data[p:p + L].rstrip(bytes([0])).decode("utf-8", "replace"); p += L
        off, size = struct.unpack("<QQ", data[p:p + 16]); p += 32 + 4
        out.append((path, size, len(zlib.compress(data[off + fb:off + fb + size], 6))))
    return out


def stem(p):
    n=os.path.basename(p.replace('res://',''))
    n=re.sub(r'-[0-9a-f]{32}\.[a-z0-9]+$','',n)   # imported: name.ext-md5.ctex
    return n
def cat(p):
    b=stem(p); full=p
    if p.endswith('.oggvorbisstr') or p.endswith('.ogg'):
        if b.startswith(('suno_','title','deploy','shop','opening','boss_in','boss_down','archive','menu')): return 'audio 配乐'
        if 'voice' in p: return 'audio 语音'
        return 'audio 配乐/其它ogg'
    if p.endswith(('.sample','.qoa','.wav')) or '.sample' in p:
        if b.startswith('ult_') or 'ult_' in b: return 'audio 终结技音效'
        return 'audio 其它音效'
    if p.endswith('.fontdata') or p.endswith(('.ttf','.otf')): return '字体'
    if p.endswith(('.gdc','.gd')) or p.endswith('.remap'): return '脚本'
    if re.search(r'\.(ctex|webp|png)$',p) or '.png-' in p or '.webp-' in p:
        if b.startswith('pxp_') or 'pxp' in p or b.startswith('sd_'): return 'art pxp 转平面'
        if b.startswith('fx_ult_'): return 'art 终结技帧条 fx_ult_'
        if b.startswith(('fx_','proj_')): return 'art 特效弹体'
        if b.startswith('op_') or b.startswith('mizuki') or b.startswith('player'): return 'art 干员帧条'
        if b.startswith('e_') or b.startswith('boss') : return 'art 怪物 Boss'
        if b.startswith(('relic_','skill_','growth_')): return 'art 图标(藏品/技能/成长)'
        if 'event' in p or b.startswith('cg_'): return 'art 事件插画'
        if b.startswith('ui_') or 'ui/' in p or 'medal' in b: return 'art 界面'
        return 'art 其它'
    return '数据 场景 其它'

def main():
    res = {}
    for d in sys.argv[1:]:
        c = collections.defaultdict(lambda: [0, 0, 0])
        for p, raw, z in read_entries(d):
            k = cat(p); c[k][0] += 1; c[k][1] += raw; c[k][2] += z
        res[d] = c
    keys = sorted(set(k for c in res.values() for k in c), key=lambda k: -max(c[k][2] for c in res.values() if k in c))
    print("%-26s" % "类别", *["%20s" % os.path.basename(os.path.dirname(d.rstrip("/\\")))[-14:] for d in res])
    for k in keys:
        print("%-26s" % k, *["%5d %6.2fM" % (c[k][0], c[k][2] / 2**20) if k in c else "%12s" % "-" for c in res.values()])
    print("TOTAL(zlib)", *["%.2f" % (sum(v[2] for v in c.values()) / 2**20) for c in res.values()])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
