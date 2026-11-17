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
