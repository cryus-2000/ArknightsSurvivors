# -*- coding: utf-8 -*-
"""运行时贴图的目录约定（docs/189 §2–3、§6.1）：前缀登记表、名字 → game/art 下的目录、索引键。

asset_lint.py（命名检查）、asset_index.py（生成 game/art/index.json）和以后的接入工具共用这一份，别各写一套。
- out_dir(name)：一张运行时贴图该放的目录（相对 game/art），接入工具复制新图时用；
- index_key(rel)：game/art 下一个文件在索引里的名字（= 游戏里 A.tex() 用的名字）；不进索引的返回 None。
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_ART = os.path.join(ROOT, "game", "art")

PREFIXES = {
    "op_": "operators", "e_": "enemies", "fx_": "fx", "proj_": "fx/proj", "relic_": "ui/relics", "skill_": "ui/skills",
    "growth_": "ui/growth", "prop_": "world/props", "terrain_": "world/terrain", "mire_": "world/mire", "pickup_": "world/pickups",
    "gem_": "world/pickups", "drone_": "world/props", "merchant": "world/npc", "ally_": "operators/_reserve", "doctor": "operators/doctor",
    "ui_": "ui", "boss_": "enemies/_portraits",
}
LEGACY = {
    "player_": "水月旧帧条名（docs/98 §1：水月 player_*）", "mizuki_": "水月原生像素帧条（mizuki.json 按名读）",
    "boss": "初版占位", "chest": "初版占位", "coral": "初版占位", "crawler": "初版占位", "dart": "初版占位", "drifter": "初版占位",
    "jelly": "初版占位", "logo": "初版占位", "oil": "初版占位", "rock": "初版占位", "seaweed": "初版占位", "shell": "初版占位",
    "shell_prop": "初版占位", "slash": "初版占位", "tentacle": "初版占位", "tiles": "初版占位",
}
SUMMONS = {"mon3tr": "kaltsit"}   # 召唤物 -> 主人

# 进索引的目录（相对 game/art）。ui/ 下只收根目录的 ui_* 和三类图标；各界面专用图（ui/medals 等）按 res:// 路径直接读，不进索引
INDEX_DIRS = ("operators", "enemies", "fx", "world", "ui/relics", "ui/skills", "ui/growth")
# 带名字前缀的子目录：游戏里按 "<前缀>/<名>" 取（optical.gd、enemies.json 的 portrait），索引键保留这个写法
KEY_PREFIX_DIRS = {"enemies/_portraits": "portraits/", "fx/_optical": "optical_fx/"}


def _ids(sub):
    d = os.path.join(ROOT, "game", "data", sub)
    return {f[:-5] for f in os.listdir(d) if f.endswith(".json")} if os.path.isdir(d) else set()


def _enemy_ids():
    p = os.path.join(ROOT, "game", "data", "enemies.json")
    return set(json.load(open(p, encoding="utf-8"))["enemies"]) if os.path.exists(p) else set()


def _owner(rest, ids):
    """rest = 去掉前缀后的名字；按已登记 id 最长前缀匹配，查不到取第一段"""
    for i in sorted(ids, key=len, reverse=True):
        if rest == i or rest.startswith(i + "_") or rest.startswith(i + "@"):
            return i
    return rest.split("_")[0].split("@")[0]


def out_dir(name):
    """运行时贴图名（不带 .png，可带 @1x / @2x）→ 目标目录（相对 game/art）；不在登记表里的返回 None（要先登记前缀）"""
    if name.startswith("portraits/"):
        return "enemies/_portraits"
    if name.startswith("optical_fx/"):
        return "fx/_optical"
    if name.startswith(("player_", "mizuki_")):
        return "operators/mizuki"
    pre = next((p for p in sorted(PREFIXES, key=len, reverse=True) if name.startswith(p)), None)
    if pre is None:
        return "world/_legacy" if any(name == k or name.startswith(k + "@") for k in LEGACY) else None
    d = PREFIXES[pre]
    if pre == "op_":
        oid = _owner(name[3:], _ids("characters") | set(SUMMONS))
        return "operators/" + SUMMONS.get(oid, oid)
    if pre == "e_":
        return "enemies/" + _owner(name[2:], _enemy_ids())
    return d


def index_key(rel):
    """game/art 下的相对路径（/ 分隔，带 .png）→ 索引键；不进索引的返回 None"""
    if not rel.endswith(".png"):
        return None
    if not any(rel.startswith(d + "/") for d in INDEX_DIRS) and not (rel.startswith("ui/ui_") and rel.count("/") == 1):
        return None
    stem = os.path.basename(rel)[:-4]
    for d, kp in KEY_PREFIX_DIRS.items():
        if rel.startswith(d + "/"):
            return kp + stem
    return stem


# ---- 运行时贴图在哪（工具用，与 art.gd 一致：只看 game/art 索引；art/incoming 只是收货区）
INCOMING = os.path.join(ROOT, "art", "incoming")
INCOMING_SUBDIRS = ("portraits", "optical_fx")   # 迁移前 art/incoming 下游戏按 "<子目录>/<名>" 读的子目录（map_path 认旧路径用）
_IDX = {}


def load_index(game_art=GAME_ART):
    """{名字: 绝对路径}，读 game/art/index.json（没有就空）"""
    key = os.path.abspath(game_art)
    if key not in _IDX:
        p = os.path.join(game_art, "index.json")
        d = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
        _IDX[key] = {k: os.path.join(game_art, v[len("res://art/"):].replace("/", os.sep)) for k, v in d.items()}
    return _IDX[key]


def runtime_png(name, game_art=GAME_ART, incoming=None):
    """贴图名（可带 @1x / @2x、portraits/ / optical_fx/ 前缀）→ 游戏会读的 PNG 绝对路径（索引里的）。
    索引里没有时：给了 incoming 就返回 <incoming>/<名>.png（测试 / 平铺目录用），否则返回按前缀该放的位置（不存在）"""
    p = load_index(game_art).get(name)
    if p:
        return p
    if incoming:
        return os.path.join(incoming, name.replace("/", os.sep) + ".png")
    d = out_dir(name)
    return os.path.join(game_art, d, name.split("/")[-1] + ".png") if d else os.path.join(game_art, name.replace("/", os.sep) + ".png")


def runtime_files(game_art=GAME_ART):
    """全部运行时贴图 {名字: 绝对路径}（game/art 索引）"""
    return dict(load_index(game_art))


def out_png(name, game_art=GAME_ART):
    """生成 / 接入工具写运行时贴图用：名字已在索引里就写回原处，否则按 out_dir 放进 game/art/<类别>/（目录不存在就建）。
    新名字写完要跑 python tools/asset_index.py 更新索引（check.py 的 asset_index 项会拦）"""
    p = load_index(game_art).get(name)
    if p:
        return p
    d = out_dir(name)
    if d is None:
        raise ValueError("%s：前缀没登记（asset_paths.PREFIXES，docs/189 §3.1）" % name)
    os.makedirs(os.path.join(game_art, d), exist_ok=True)
    return os.path.join(game_art, d, name.split("/")[-1] + ".png")


# ---- 旧路径 → 新路径（docs/189 §6.5）：从 codex/art 或任何旧分支收货时用
MAP_FILE = os.path.join(ROOT, "tools", "asset_path_map.json")   # 迁移时 git mv 的完整对照（仓库相对路径，/ 分隔）


def map_path(old):
    """旧路径（仓库相对，例 art/incoming/op_skadi_idle@2x.png）→ 新路径；映射表里没有的 art/incoming 运行时 PNG 按前缀给目录，
    其余（交接文档、批次子目录等）原样返回"""
    p = old.replace("\\", "/").lstrip("./")
    amap = json.load(open(MAP_FILE, encoding="utf-8")) if os.path.exists(MAP_FILE) else {}
    if p in amap:
        return amap[p]
    pre = "art/incoming/"
    if p.startswith(pre) and p.endswith(".png"):
        rest = p[len(pre):]
        if rest.count("/") == 0 or (rest.count("/") == 1 and rest.split("/")[0] in INCOMING_SUBDIRS):
            d = out_dir(rest[:-4])
            if d:
                return "game/art/%s/%s" % (d, os.path.basename(p))
    return p


if __name__ == "__main__":
    import sys
    # python tools/asset_paths.py <旧路径 ...>   （不给参数就从标准输入每行读一个）：每行输出「旧路径 → 新路径」，没变的标 =
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    olds = sys.argv[1:] or [l.strip() for l in sys.stdin if l.strip()]
    for o in olds:
        n = map_path(o)
        print("%s → %s" % (o, n) if n != o.replace("\\", "/").lstrip("./") else "%s =" % o)
