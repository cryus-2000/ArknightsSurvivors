# -*- coding: utf-8 -*-
"""明日方舟 PC 客户端特效包只读解析（内部参照，原作素材不进 git / 包；docs/242 §13）。

- LZ4AK 块压缩：照 Ark-Unpacker v5.2.0 src/lz4ak/Block.py 的算法移植（BSD-3，Harry Huang），挂到 UnityPy 的 LZHAM 槽位；
- CAB 名 → 包路径索引：只解析包头目录、不解压数据块，缓存在 build/ark_ref/_cab_idx.json（客户端更新后加 --reindex 重建）；
- prefab 层级 dump（Transform TRS、ParticleSystem / 各类 Renderer 的 typetree、材质贴图 / 颜色 / 混合参数）、网格导出 OBJ、贴图导出 PNG。
原型：逻各斯会话 Claude outputs/logos_ref/scripts（dump.py / mesh2.py / ark_ref.py / cabidx.py）。
"""
import json, os, re, struct, sys

import lz4.block
import UnityPy
from UnityPy.enums.BundleFile import CompressionFlags
from UnityPy.helpers import CompressionHelper

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import godot_runner as GR
ROOT = GR.common_root()   # 主仓库根目录：build/ark_ref、CAB 索引、Claude outputs 各工作树共用
DATA = os.environ.get("ARK_DATA", "D:/Hypergryph Launcher/games/Arknights/Arknights_Data")
ROOTS = [DATA + "/StreamingAssets/AB/Windows", DATA + "/PersistentData/Bundles"]   # 新的优先
# 本作干员 id → 原作特效包名（battle/prefabs/effects/<包名>.ab）
OPS = {
    "angelina": "aglina", "exusiai": "angle", "eyjafjalla": "amgoat", "gladiia": "glady", "hoshiguma": "hsguma", "irene": "irene",
    "kaltsit": "kalts", "lappland": "whitew", "logos": "logos", "lumen": "lumen", "mizuki": "mizuki", "saria": "demkni",
    "siege": "siege", "skadi": "skadi", "skalter": "skadi2", "specter_unchained": "ghost2", "suzuran": "lisa", "texas": "texas",
    "ulpianus": "ulpia", "wisadel": "wisdel",
}
CAB_IDX = os.path.join(ROOT, "build", "ark_ref", "_cab_idx.json")
QUAD = "v -0.5 -0.5 0\nv 0.5 -0.5 0\nv 0.5 0.5 0\nv -0.5 0.5 0\nvt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\nf 1/1 2/2 3/3\nf 1/1 3/3 4/4\n"


def _extra(data, ip, end):
    n = 0
    while ip < end:
        b = data[ip]
        n += b
        ip += 1
        if b != 0xFF:
            break
    return n, ip


def lz4ak(src, usize):
    d = bytearray(src)
    ip = op = 0
    end = len(d)
    while ip < end:
        lit = d[ip] & 0xF
        mat = (d[ip] >> 4) & 0xF
        d[ip] = (lit << 4) | mat
        ip += 1
        if lit == 0xF:
            n, ip = _extra(d, ip, end)
            lit += n
        ip += lit
        op += lit
        if op >= usize:
            break
        off = (d[ip] << 8) | d[ip + 1]
        d[ip] = off & 0xFF
        d[ip + 1] = (off >> 8) & 0xFF
        ip += 2
        if mat == 0xF:
            n, ip = _extra(d, ip, end)
            mat += n
        op += mat + 4
    return lz4.block.decompress(bytes(d), usize)


CompressionHelper.DECOMPRESSION_MAP[CompressionFlags.LZHAM] = lz4ak


# ---------- CAB 索引（依赖包）
def _cstr(f):
    b = bytearray()
    while True:
        c = f.read(1)
        if not c or c == b"\0":
            return bytes(b).decode("utf8", "replace")
        b += c


def _cabs(path):
    with open(path, "rb") as f:
        if _cstr(f) != "UnityFS":
            return []
        ver = struct.unpack(">I", f.read(4))[0]
        _cstr(f); _cstr(f)
        size, csz, usz, flags = struct.unpack(">QIII", f.read(20))
        if ver >= 7:
            f.seek((f.tell() + 15) // 16 * 16)
        if flags & 0x80:
            f.seek(-csz, 2)
        info = f.read(csz)
        ct = flags & 0x3F
        data = info if ct == 0 else lz4.block.decompress(info, usz) if ct in (2, 3) else lz4ak(info, usz) if ct == 4 else None
    if data is None:
        return []
    p = 16
    nb = struct.unpack(">i", data[p:p + 4])[0]
    p += 4 + nb * 10
    nn = struct.unpack(">i", data[p:p + 4])[0]
    p += 4
    out = []
    for _ in range(nn):
        p += 20
        e = data.index(b"\0", p)
        out.append(data[p:e].decode("utf8", "replace"))
        p = e + 1
    return out


def cab_index(rebuild=False):
    if os.path.exists(CAB_IDX) and not rebuild:
        return json.load(open(CAB_IDX, encoding="utf-8"))
    idx = {}
    for r in reversed(ROOTS):   # 新的（StreamingAssets）后写、覆盖旧的
        for dp, dn, fn in os.walk(r):
            for n in fn:
                if n.endswith(".ab"):
                    fp = os.path.join(dp, n).replace(os.sep, "/")
                    try:
                        for c in _cabs(fp):
                            idx[c.split(".")[0]] = fp
                    except Exception as ex:   # noqa: BLE001
                        print("CAB 索引跳过", fp, ex)
    os.makedirs(os.path.dirname(CAB_IDX), exist_ok=True)
    json.dump(idx, open(CAB_IDX, "w", encoding="utf-8"), indent=0)
    print("CAB 索引 %d 条 → %s" % (len(idx), CAB_IDX))
    return idx


def find_ab(rel):
    for r in ROOTS:
        p = r + "/" + rel
        if os.path.isfile(p):
            return p
    return None


def load_env(op_or_ab, rebuild_idx=False):
    """干员 id（或 .ab 相对路径 / 绝对路径）→ 带依赖包的 UnityPy 环境"""
    if op_or_ab in OPS:
        p = find_ab("battle/prefabs/effects/%s.ab" % OPS[op_or_ab])
    elif os.path.isfile(op_or_ab):
        p = op_or_ab
    else:
        p = find_ab(op_or_ab)
    if not p:
        raise SystemExit("找不到特效包：%s（客户端目录 %s，可用环境变量 ARK_DATA 改）" % (op_or_ab, DATA))
    env = UnityPy.load(open(p, "rb").read())   # 读进内存，客户端文件只读、不留句柄
    idx = cab_index(rebuild_idx)
    seen = set()
    for _ in range(3):   # 依赖的依赖
        need = set()
        for f in list(env.files.values()):
            for sf in (f.files.values() if hasattr(f, "files") else [f]):
                for e in getattr(sf, "externals", []):
                    m = re.search(r"(CAB-[0-9a-f]+)", e.path)
                    if m and m.group(1) in idx and m.group(1) not in seen:
                        seen.add(m.group(1))
                        need.add(idx[m.group(1)])
        for q in need:
            try:
                env.load_file(open(q, "rb").read(), name=os.path.basename(q))
            except Exception as ex:   # noqa: BLE001
                print("依赖包读不了", q, ex)
    return env, p


def list_prefabs(env):
    """包里的根 GameObject（Transform 没有父节点）名字"""
    out = []
    for o in env.objects:
        if o.type.name != "Transform":
            continue
        try:
            d = o.read_typetree()
        except Exception:   # noqa: BLE001
            continue
        if not d.get("m_Father", {}).get("m_PathID"):
            try:
                out.append(o.assets_file.objects[d["m_GameObject"]["m_PathID"]].read().m_Name)
            except Exception:   # noqa: BLE001
                pass
    return sorted(set(out))


# ---------- prefab dump
def _mat(mobj):
    try:
        m = mobj.read()
        tex = {}
        for k, v in m.m_SavedProperties.m_TexEnvs:
            try:
                tex[k] = (v.m_Texture.deref().read() if hasattr(v.m_Texture, "deref") else v.m_Texture.read()).m_Name
            except Exception:   # noqa: BLE001
                if v.m_Texture.m_PathID:
                    tex[k] = "?%s/%s" % (v.m_Texture.m_FileID, v.m_Texture.m_PathID)
        cols = {k: [round(v.r, 3), round(v.g, 3), round(v.b, 3), round(v.a, 3)] for k, v in m.m_SavedProperties.m_Colors}
        fl = {k: v for k, v in m.m_SavedProperties.m_Floats}
        try:
            sh = m.m_Shader.deref().read().m_ParsedForm.m_Name
        except Exception:   # noqa: BLE001
            try:
                sh = m.m_Shader.read().m_Name
            except Exception:   # noqa: BLE001
                sh = "?"
        return {"name": m.m_Name, "shader": sh, "tex": tex, "cols": cols,
                "floats": {k: v for k, v in fl.items() if k in ("_SrcBlend", "_DstBlend", "_Mode", "_Blend", "_BlendMode", "_ZWrite", "_Cull", "_Intensity", "_Power")}}
    except Exception as ex:   # noqa: BLE001
        return {"_err": str(ex)}


def _comp(c):
    co = c.component.deref() if hasattr(c.component, "deref") else None
    if co is None:
        try:
            co = c.component.get_obj()
        except Exception:   # noqa: BLE001
            co = None
    return co


def _roots(env, names):
    for o in list(env.objects):
        if o.type.name == "GameObject":
            g = o.read()
            if g.m_Name in names:
                yield o, g


def dump_prefabs(env, names):
    """prefab 名列表 → {名: 节点树}；节点 = name / active / pos / rot / scale / comps / kids"""
    def walk(go_obj):
        go = go_obj.read()
        node = {"name": go.m_Name, "active": go.m_IsActive, "comps": {}}
        kids_ref = []
        for c in go.m_Component:
            co = _comp(c)
            if co is None:
                continue
            tn = co.type.name
            try:
                d = co.read_typetree()
            except Exception as ex:   # noqa: BLE001
                d = {"_err": str(ex)}
            if tn == "Transform":
                node["pos"], node["rot"], node["scale"] = d.get("m_LocalPosition"), d.get("m_LocalRotation"), d.get("m_LocalScale")
                kids_ref = d.get("m_Children", [])
            elif tn in ("ParticleSystemRenderer", "TrailRenderer", "LineRenderer", "MeshRenderer"):
                mats = []
                for mp in co.read().m_Materials:
                    try:
                        mats.append(_mat(mp.deref()))
                    except Exception as ex:   # noqa: BLE001
                        mats.append({"_err": str(ex)})
                d2 = {k: v for k, v in d.items() if k in ("m_RenderMode", "m_LengthScale", "m_VelocityScale", "m_SortingOrder", "m_RenderAlignment", "m_Time", "m_Parameters", "m_MinVertexDistance", "m_SortingFudge")}
                d2["mats"] = mats
                node["comps"][tn] = d2
            else:
                node["comps"][tn] = d
        node["kids"] = []
        for ch in kids_ref:
            tr = go_obj.assets_file.objects.get(ch["m_PathID"])
            if tr is not None:
                node["kids"].append(walk(go_obj.assets_file.objects[tr.read_typetree()["m_GameObject"]["m_PathID"]]))
        return node
    out = {}
    for o, g in _roots(env, names):
        r = walk(o)
        r["active"] = True   # 根节点在包里常是关着的（运行时由技能脚本 SetActive），关着照样回放，否则整棵跳过出空画面（组长 C 11-04）
        out[g.m_Name] = r
    return out


def mesh_name(prefab, path):
    return "%s__%s.obj" % (prefab, path.replace("/", "_"))


def export_meshes(env, names, mesh_dir):
    """MeshFilter / 网格粒子（RenderMode 4）的网格存 OBJ；读不到的按内置四边形"""
    os.makedirs(mesh_dir, exist_ok=True)
    n = 0
    for o, g in _roots(env, names):
        def walk(go, path):
            nonlocal n
            tr = None
            for c in go.m_Component:
                co = _comp(c)
                if co is None:
                    continue
                tn = co.type.name
                fn = os.path.join(mesh_dir, mesh_name(g.m_Name, path))
                mp = None
                if tn == "MeshFilter":
                    mp = co.read().m_Mesh
                elif tn == "ParticleSystemRenderer" and co.read_typetree().get("m_RenderMode") == 4 and not os.path.exists(fn):
                    mp = co.read().m_Mesh
                elif tn == "Transform":
                    tr = co.read()
                if mp is not None:
                    try:
                        open(fn, "w").write(mp.deref().read().export())
                    except Exception:   # noqa: BLE001
                        open(fn, "w").write(QUAD)
                    n += 1
            for ch in (tr.m_Children if tr else []):
                cg = ch.deref().read().m_GameObject.deref().read()
                walk(cg, path + "/" + cg.m_Name)
        walk(g, g.m_Name)
    return n


ALPHA = [re.compile(r"(.+)\[alpha\](\$[0-9]+)?$"), re.compile(r"(.+)_alpha(\$[0-9]+)?$")]


def export_textures(env, wanted, tex_dir):
    """贴图名集合 → tex_dir/<名>.png（已有就跳过）；单独的 alpha 图（xxx[alpha] / xxx_alpha）并进 alpha 通道"""
    os.makedirs(tex_dir, exist_ok=True)
    todo = {w for w in wanted if w and not w.startswith("?") and not os.path.exists(os.path.join(tex_dir, w + ".png"))}
    if not todo:
        return 0
    imgs, alphas = {}, {}
    for o in env.objects:
        if o.type.name != "Texture2D":
            continue
        try:
            t = o.read()
        except Exception:   # noqa: BLE001
            continue
        nm = t.m_Name
        for rx in ALPHA:
            m = rx.match(nm)
            if m and m.group(1) in todo:
                alphas[m.group(1)] = t
                break
        else:
            if nm in todo and nm not in imgs:
                imgs[nm] = t
    n = 0
    for nm, t in imgs.items():
        try:
            im = t.image.convert("RGBA")
            if nm in alphas:
                a = alphas[nm].image.convert("L").resize(im.size)
                im.putalpha(a)
            im.save(os.path.join(tex_dir, nm + ".png"))
            n += 1
        except Exception as ex:   # noqa: BLE001
            print("贴图导不出", nm, ex)
    return n


def textures_in(node, out=None):
    out = set() if out is None else out
    for k, c in node["comps"].items():
        for m in c.get("mats", []) if isinstance(c, dict) else []:
            if isinstance(m, dict):
                out.update(v for v in m.get("tex", {}).values() if isinstance(v, str))
    for ch in node["kids"]:
        textures_in(ch, out)
    return out
