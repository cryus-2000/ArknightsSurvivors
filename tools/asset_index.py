# -*- coding: utf-8 -*-
"""生成 / 核对运行时贴图索引 game/art/index.json（docs/189 §6.1）：贴图名 → res:// 路径，@1x / @2x 各算一个名字。

art.gd 按名字取图时先查这份索引（_indexed），查不到再回退 art/incoming 根目录（过渡期，批 5 去掉）。
挪图 / 接入新图后跑一次：python tools/asset_index.py；check.py 的 asset_index 项核对索引与磁盘一致（不一致算失败，
因为索引缺名字游戏里就画不出来）。哪些目录进索引、索引键怎么取见 asset_paths.INDEX_DIRS / index_key。
用法：asset_index.py            重写索引
      asset_index.py --check    只核对，不一致退出码 1
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asset_paths import GAME_ART, index_key

INDEX = os.path.join(GAME_ART, "index.json")


def build(game_art=GAME_ART):
    """返回 (索引 dict, 重名列表)；game_art 可指向导出副本"""
    idx, dups = {}, []
    for dp, dns, fs in os.walk(game_art):
        dns.sort()
        for f in sorted(fs):
            rel = os.path.relpath(os.path.join(dp, f), game_art).replace(os.sep, "/")
            k = index_key(rel)
            if k is None:
                continue
            if k in idx:
                dups.append("%s：%s 与 %s" % (k, idx[k], rel))
                continue
            idx[k] = "res://art/" + rel
    return dict(sorted(idx.items())), dups


def dump(idx):
    return json.dumps(idx, ensure_ascii=False, indent=0, sort_keys=True) + "\n"


def check():
    """check.py 用：返回错误列表（空 = 一致）"""
    idx, dups = build()
    errs = ["重名（名字必须全局唯一，docs/189 §2）：" + d for d in dups]
    if not os.path.exists(INDEX):
        return errs + ["缺 game/art/index.json：跑 python tools/asset_index.py"]
    old = json.load(open(INDEX, encoding="utf-8"))
    miss = sorted(set(idx) - set(old))
    gone = sorted(set(old) - set(idx))
    moved = sorted(k for k in set(idx) & set(old) if idx[k] != old[k])
    for tag, ks in (("磁盘有、索引没有", miss), ("索引有、磁盘没有", gone), ("路径变了", moved)):
        if ks:
            errs.append("%s %d 个（例 %s）：跑 python tools/asset_index.py" % (tag, len(ks), ", ".join(ks[:3])))
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if a.check:
        errs = check()
        for e in errs:
            print("ERROR " + e)
        print("asset_index：%s" % ("一致" if not errs else "%d 处不一致" % len(errs)))
        return 1 if errs else 0
    idx, dups = build()
    for d in dups:
        print("ERROR 重名：" + d)
    with open(INDEX, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(dump(idx))
    print("game/art/index.json：%d 个名字" % len(idx))
    return 1 if dups else 0


if __name__ == "__main__":
    sys.exit(main())
