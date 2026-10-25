"""生成启动页的预读顺序 game/data/boot_order.json（screens/boot_screen.gd 用，docs/22「启动加载」）。

启动时最慢的一段是读入标题页：title.gd 经 preload / extends 一路带出 game.gd 与几乎全部脚本，桌面调试版 8–12 秒、网页十几秒，
以前全在 Godot 静态启动图下面、没有进度。启动页按这张表「叶子在前」逐个 load()，每个只编译它自己（依赖已在缓存），
所以进度是真实的，还能说清当前在读哪一类。GDScript 的 ResourceLoader.get_dependencies 不列 preload（实测为空），
导出包里又没有源码可扫，所以离线生成。表过期只会让进度粗一点：漏掉的脚本在最后读 main.tscn 时一并编译。

  python tools/gen_boot_order.py          # 重写 game/data/boot_order.json
  python tools/gen_boot_order.py --check  # 只比对，过期时退出码 1
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GAME, "data", "boot_order.json")
START = "res://main.tscn"
PRELOAD = re.compile(r'\bpreload\(\s*"(res://[^"]+)"\s*\)')
EXTENDS = re.compile(r'^extends\s+"(res://[^"]+)"', re.M)
EXT_RES = re.compile(r'\[ext_resource[^\]]*path="(res://[^"]+)"')

# 路径前缀 → 玩家看得懂的类别（启动页「正在读什么」）；先长后短匹配
LABELS = [
    ("res://scripts/characters/blocks/", "干员积木"),
    ("res://scripts/characters/", "干员"),
    ("res://scripts/enemies/", "海嗣"),
    ("res://scripts/allies/", "友方单位"),
    ("res://scripts/world/", "战场"),
    ("res://scripts/render/", "战场渲染"),
    ("res://scripts/run/", "作战流程"),
    ("res://scripts/core/", "核心规则"),
    ("res://scripts/screens/", "界面"),
    ("res://scripts/native/", "原生内核"),
    ("res://scripts/game.gd", "作战主循环"),
    ("res://scripts/title", "标题页"),
    ("res://scripts/gallery", "图鉴"),
    ("res://scripts/", "系统"),
    ("res://shaders/", "着色器"),
    ("res://fonts/", "字体"),
    ("res://data/", "作战数据"),
    ("res://", "美术素材"),
]


def label(p):
    for pre, lab in LABELS:
        if p.startswith(pre):
            return lab
    return "资源"


def deps(p):
    fp = os.path.join(GAME, p[len("res://"):])
    if not os.path.isfile(fp) or not fp.endswith((".gd", ".tscn", ".tres")):
        return []
    with open(fp, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    if fp.endswith(".gd"):
        return EXTENDS.findall(src) + PRELOAD.findall(src)
    return EXT_RES.findall(src)


def build():
    """叶子在前；互相 preload 的一圈脚本（强连通分量，game.gd 与它的各模块约 40 个）读其中任何一个都会整圈一起编译，
    所以按分量排：一个分量排在它依赖的所有分量之后（Tarjan 的输出顺序正是这样），圈外的依赖先一个个读完，
    整圈只占一项、标 heavy（启动页先把「正在读什么」画出来再读；网页没有线程，这一项会卡一下）。
    10-25 以前按普通深度优先排，环里先碰到 boss_patterns.gd，读它时把 game.gd 连同 80 多个还没读的脚本一口气编译，桌面一帧卡 2–4 秒。"""
    nodes = {}

    def walk(p):
        if p in nodes:
            return
        ds = [d for d in deps(p) if os.path.isfile(os.path.join(GAME, d[len("res://"):]))]
        nodes[p] = ds
        for d in ds:
            walk(d)

    sys.setrecursionlimit(10000)
    walk(START)
    index, low, stack, on, comps, c = {}, {}, [], set(), [], [0]

    def strong(v):
        index[v] = low[v] = c[0]
        c[0] += 1
        stack.append(v)
        on.add(v)
        for w in nodes[v]:
            if w not in index:
                strong(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            comps.append(comp)

    strong(START)
    items = []
    for comp in comps:
        if START in comp:
            continue   # main.tscn 由启动页最后读，读完就建标题页
        if len(comp) == 1:
            items.append([comp[0], label(comp[0])])
            continue
        hub = "res://scripts/game.gd" if "res://scripts/game.gd" in comp else sorted(comp)[0]
        items.append([hub, label(hub), "heavy"])   # 读它就整圈编译；其余成员已在缓存，不再单列
    return {"_doc": "启动页预读顺序（tools/gen_boot_order.py 生成，叶子在前、互相引用的一圈合成一项；勿手改）", "items": items}


def main():
    data = build()
    text = json.dumps(data, ensure_ascii=False, indent=0) + "\n"
    if "--check" in sys.argv:
        cur = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if cur != text:
            print("boot_order.json 过期：python tools/gen_boot_order.py")
            sys.exit(1)
        print("boot_order.json 最新（%d 项）" % len(data["items"]))
        return
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("写入 %s：%d 项" % (OUT, len(data["items"])))


if __name__ == "__main__":
    main()
