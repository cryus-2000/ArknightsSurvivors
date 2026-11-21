# -*- coding: utf-8 -*-
"""Python 工具读主题数据的入口（docs/367 §2）：和游戏里的 scripts/core/theme_pack.gd 同一份清单 game/themes/<id>/theme.json。

    import theme_paths as TP
    TP.data_file("enemies.json")      # → <仓库>/game/themes/deep_sea/data/enemies.json（清单 data 段有这个键）；没有就 <仓库>/game/data/<名>
    TP.data_dirs()                     # [game/data, game/themes/<每个主题>/data]：要扫全部数据 JSON 的工具（解析检查、文字扫描、字体子集）用
    TP.maps_dir()                      # 缺省主题的地图目录

只读文件，不依赖 Godot。root 参数给「指定仓库根」的工具（graph_lint.configure、check.py 在临时工作树里跑）用。
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = "deep_sea"


def manifest(theme=DEFAULT, root=None):
    p = os.path.join(root or ROOT, "game", "themes", theme, "theme.json")
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _fs(res, root=None):
    return os.path.join(root or ROOT, "game", *res[len("res://"):].split("/"))


def data_file(name, theme=DEFAULT, root=None):
    key = name[:-5] if name.endswith(".json") else name
    r = manifest(theme, root).get("data", {}).get(key)
    return _fs(r, root) if r else os.path.join(root or ROOT, "game", "data", name)


def maps_dir(theme=DEFAULT, root=None):
    r = manifest(theme, root).get("maps", {}).get("dir")
    return _fs(r, root) if r else os.path.join(root or ROOT, "game", "data", "maps")


def themes(root=None):
    d = os.path.join(root or ROOT, "game", "themes")
    return sorted(t for t in os.listdir(d) if os.path.isfile(os.path.join(d, t, "theme.json"))) if os.path.isdir(d) else []


def data_dirs(root=None):
    out = [os.path.join(root or ROOT, "game", "data")]
    for t in themes(root):
        p = os.path.join(root or ROOT, "game", "themes", t, "data")
        if os.path.isdir(p):
            out.append(p)
    return out


def load_json(name, theme=DEFAULT, root=None):
    """同 scripts/core/theme_pack.gd load_merged（docs/368 §4）：共享 game/data/<名> 叠上清单指向的主题部分；
    两边都是字典的键合并（主题优先）、pages_insert 按 at 插回 pages、其余主题覆盖，_doc 不合并。没拆的文件就是清单指向的那一份"""
    import copy
    shared = os.path.join(root or ROOT, "game", "data", name)
    tp = data_file(name, theme, root)
    if os.path.normcase(os.path.abspath(tp)) == os.path.normcase(os.path.abspath(shared)) or not os.path.exists(shared):
        with open(tp, encoding="utf-8") as f:
            return json.load(f)
    with open(shared, encoding="utf-8") as f:
        out = json.load(f)
    with open(tp, encoding="utf-8") as f:
        th = json.load(f)
    for k, v in th.items():
        if k == "_doc":
            continue
        if k == "pages_insert":
            for it in sorted(v, key=lambda x: x["at"]):
                out.setdefault("pages", []).insert(int(it["at"]), copy.deepcopy(it["page"]))
        elif isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k].update(copy.deepcopy(v))
        else:
            out[k] = copy.deepcopy(v)
    return out


def split_files(theme=DEFAULT, root=None):
    """拆成「共享 + 主题」两份的数据（共享 game/data/<名> 与清单指向的主题文件都在）：[(名, 共享路径, 主题路径)]"""
    out = []
    for key, res in manifest(theme, root).get("data", {}).items():
        shared = os.path.join(root or ROOT, "game", "data", key + ".json")
        tp = _fs(res, root)
        if os.path.exists(shared) and os.path.normcase(os.path.abspath(tp)) != os.path.normcase(os.path.abspath(shared)):
            out.append((key + ".json", shared, tp))
    return out
