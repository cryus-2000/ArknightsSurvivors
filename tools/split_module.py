"""把 game.gd 里的一组函数搬到独立模块（2026-09-26 架构整理用，可重复使用）。

用法：python tools/split_module.py <spec.json> [--dry]
spec: {
  "module": "res://scripts/run/spawner.gd",   # 新模块路径（res://）
  "field": "spawner",                          # game.gd 里持有模块的变量名
  "const": "Spawner",                          # game.gd 里 preload 的常量名
  "doc": "模块说明（写进文件头）",
  "funcs": ["_spawn", ...],                    # 要搬的函数
  "rename": {"_spawn": "update"},              # 可选：搬过去后改名（调用方同步改）
  "keep_vars": ["foo"]                         # 可选：即使只被搬走的函数使用也留在 game.gd 的变量
}
做法：
  1. 函数体里引用 game.gd 成员（变量 / 常量 / 函数 / 枚举 / Node2D 继承方法）的地方加 `g.`；self → g。
     preload 常量整行复制到模块头部（UI.text 之类照写）。
  2. 只被搬走的函数使用的 game.gd 变量一并搬进模块（初始化式也改写）。
  3. game.gd 里剩下的调用改成 `<field>.<名字>`；其他脚本里的 `.名字` 引用列出来并改成 `.<field>.<名字>`。
  4. game.gd 顶部加 preload 常量、变量声明处加 `var <field> = <Const>.new(self)`。
不认识的标识符（既不是局部变量也不是 game.gd 成员、也不在内置名单）会列出来，需要人看。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game", "scripts", "game.gd")
SCRIPTS = os.path.join(ROOT, "game")

KEYWORDS = set("""if elif else for while match break continue pass return class class_name extends is in as self signal func static const
enum var await yield super preload true false null not and or void PI TAU INF NAN breakpoint assert when tool onready export _""".split())
# GDScript 全局函数 / 常用内置（不加 g.）
BUILTIN = set("""abs absf absi acos asin atan atan2 bezier_interpolate bytes_to_var ceil ceilf ceili clamp clampf clampi cos cosh cubic_interpolate
db_to_linear deg_to_rad ease exp floor floorf floori fmod fposmod hash instance_from_id inverse_lerp is_equal_approx is_finite is_inf
is_instance_id_valid is_instance_valid is_nan is_same is_zero_approx lerp lerp_angle lerpf linear_to_db log max maxf maxi min minf mini
move_toward nearest_po2 pingpong posmod pow print print_rich printerr prints printt push_error push_warning rad_to_deg rand_from_seed randf
randf_range randfn randi randi_range randomize remap rid_allocate_id rid_from_int64 rotate_toward round roundf roundi seed sign signf signi
sin sinh smoothstep snapped snappedf snappedi sqrt step_decimals str str_to_var tan tanh type_convert type_string typeof var_to_bytes
var_to_str weakref wrap wrapf wrapi char convert len load range print_debug print_stack get_stack inst_to_dict dict_to_inst
int float bool String Array Dictionary Callable""".split())
# Node2D / CanvasItem / Node 继承来的成员：在模块里要写成 g.xxx
INHERITED = set("""draw_arc draw_char draw_circle draw_colored_polygon draw_dashed_line draw_lcd_texture_rect_region draw_line draw_mesh
draw_msdf_texture_rect_region draw_multiline draw_multiline_colors draw_multiline_string draw_multiline_string_outline draw_multimesh
draw_polygon draw_polyline draw_polyline_colors draw_primitive draw_rect draw_set_transform draw_set_transform_matrix draw_string
draw_string_outline draw_style_box draw_texture draw_texture_rect draw_texture_rect_region draw_end_animation draw_animation_slice
get_viewport get_viewport_rect get_tree get_global_mouse_position get_local_mouse_position get_canvas_transform get_global_transform
get_node get_node_or_null get_parent get_children add_child remove_child queue_free queue_redraw is_inside_tree create_tween
get_window set_process to_local to_global get_world_2d position rotation scale global_position modulate self_modulate visible z_index
material texture_filter get_viewport_transform get_process_delta_time is_queued_for_deletion""".split())

TOK = re.compile(r'''("""[\s\S]*?"""|'\'\'[\s\S]*?'\'\'|&?"(?:\\.|[^"\\\n])*"|&?'(?:\\.|[^'\\\n])*'|\^"(?:\\.|[^"\\\n])*"|#[^\n]*|[A-Za-z_][A-Za-z0-9_]*|\d[\d_]*(?:\.\d*)?(?:e[+-]?\d+)?|\s+|.)''')


def tokens(src):
    return TOK.findall(src)


def top_blocks(lines):
    """顶层语句块：[(kind, name, start, end)]，end 不含；函数块带上紧贴其上的 ##/# 注释行"""
    blocks = []
    i, n = 0, len(lines)
    depth = 0
    while i < n:
        l = lines[i]
        if l.strip() == "" or l.startswith("#") or l[0] in " \t":
            i += 1
            continue
        m = re.match(r'(?:static\s+)?func\s+([A-Za-z_]\w*)', l) or None
        kind, name = None, None
        if m:
            kind, name = "func", m.group(1)
        else:
            m2 = re.match(r'(?:@\w+(?:\([^)]*\))?\s+)*(var|const|enum|signal)\s+([A-Za-z_]\w*)', l)
            if m2:
                kind, name = m2.group(1), m2.group(2)
        start = i
        # 注释前缀（紧贴）
        cs = start
        while cs > 0 and lines[cs - 1].startswith("#") and not lines[cs - 1].startswith("# ====") and not lines[cs - 1].startswith("# ----"):
            cs -= 1
        # 块结束：函数到下一个顶层非空、非注释行；变量按括号配平
        j = i + 1
        if kind == "func":
            while j < n and (lines[j].strip() == "" or lines[j][0] in " \t" or (lines[j].startswith("#") and _next_code_indented(lines, j))):
                j += 1
            # 回退尾部空行 / 注释（它们属于下一个块）
            while j - 1 > i and (lines[j - 1].strip() == "" or lines[j - 1].startswith("#")):
                j -= 1
        else:
            bal = _balance("\n".join(lines[i:j]))
            while bal > 0 and j < n:
                j += 1
                bal = _balance("\n".join(lines[i:j]))
        blocks.append((kind, name, cs if kind == "func" else start, j))
        i = j
    return blocks


def _next_code_indented(lines, j):
    k = j
    while k < len(lines) and (lines[k].strip() == "" or lines[k].startswith("#")):
        k += 1
    return k < len(lines) and lines[k][0] in " \t"


def _balance(s):
    b = 0
    for t in tokens(s):
        if t in "([{":
            b += 1
        elif t in ")]}":
            b -= 1
    return b


def locals_of(src):
    """函数（含 lambda）里的局部名：参数、var、const、for 变量"""
    loc = set()
    for m in re.finditer(r'\bfunc\b\s*[A-Za-z_]*\s*\(([^)]*)\)', src):
        for p in m.group(1).split(","):
            mm = re.match(r'\s*([A-Za-z_]\w*)\s*(?::|=|$)', p)
            if mm:
                loc.add(mm.group(1))
    for m in re.finditer(r'\b(?:var|const)\s+([A-Za-z_]\w*)', src):
        loc.add(m.group(1))
    for m in re.finditer(r'\bfor\s+([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?in\b', src):
        loc.add(m.group(1))
    return loc


def rewrite(src, members, local, moved_names, rename, unknown, allow_self=True):
    """给 game.gd 成员加 g.；src 是整个函数（或变量初始化）源码"""
    out = []
    toks = tokens(src)
    prev_sig = ""   # 上一个非空白 token
    for k, t in enumerate(toks):
        if re.match(r'[A-Za-z_]', t) and not t.startswith(('"', "'")):
            nxt = ""
            for u in toks[k + 1:]:
                if not u.isspace():
                    nxt = u
                    break
            if prev_sig == "." or prev_sig == "$":
                out.append(t)
            elif t == "g" and "g" in local:
                out.append("g_item")   # 原代码的局部变量 g（如 for g in gems）会遮住模块的 g，改名
            elif t == "self" and allow_self:
                out.append("g")
            elif t in local or t in KEYWORDS:
                out.append(t)
            elif t in moved_names:
                out.append(rename.get(t, t))
            elif t in members or t in INHERITED:
                out.append("g." + t)
            elif t in BUILTIN or t[0].isupper():
                out.append(t)
            elif prev_sig == "func" or nxt == ":" and prev_sig in ("{", ","):
                out.append(t)   # lambda 名 / 字典字面量键（{key = v} 语法不在此列）
            else:
                unknown.add(t)
                out.append(t)
        else:
            out.append(t)
        if not t.isspace() and not t.startswith("#"):
            prev_sig = t
    return "".join(out)


def main():
    spec = json.load(open(sys.argv[1], encoding="utf-8"))
    dry = "--dry" in sys.argv
    raw = open(GAME, "rb").read().decode("utf-8")
    crlf = "\r\n" in raw
    lines = raw.replace("\r\n", "\n").split("\n")
    blocks = top_blocks(lines)
    members = {b[1] for b in blocks if b[0] in ("var", "const", "func", "enum", "signal")}
    preload_consts = {}
    for b in blocks:
        if b[0] == "const":
            txt = "\n".join(lines[b[2]:b[3]])
            if "preload(" in txt:
                preload_consts[b[1]] = txt
    members -= set(preload_consts)
    funcs = spec["funcs"]
    rename = spec.get("rename", {})
    clash = [v for v in rename.values() if v in BUILTIN or v in INHERITED or v in KEYWORDS]
    assert not clash, ("新名字和内置函数 / Node 方法 / 关键字重名", clash)
    byname = {b[1]: b for b in blocks if b[0] == "func"}
    missing = [f for f in funcs if f not in byname]
    assert not missing, ("找不到函数", missing)
    moved = set(funcs)
    moved_ranges = sorted((byname[f][2], byname[f][3]) for f in funcs)
    in_moved = [False] * len(lines)
    for a, b in moved_ranges:
        for i in range(a, b):
            in_moved[i] = True
    rest_src = "\n".join(l for i, l in enumerate(lines) if not in_moved[i])
    moved_src = "\n".join(lines[a:b] and "\n".join(lines[a:b]) for a, b in moved_ranges)

    # 其他脚本里对被搬函数 / 变量的 .引用
    others = {}
    for dp, _, fs in os.walk(os.path.join(SCRIPTS, "scripts")):
        for f in fs:
            if f.endswith(".gd"):
                p = os.path.join(dp, f)
                if os.path.samefile(p, GAME):
                    continue
                others[p] = open(p, "rb").read().decode("utf-8")
    for dp, _, fs in os.walk(os.path.join(SCRIPTS, "tests")):
        for f in fs:
            if f.endswith(".gd"):
                p = os.path.join(dp, f)
                others[p] = open(p, "rb").read().decode("utf-8")

    def used_outside(name):
        pat = re.compile(r'(?<![.\w$])' + re.escape(name) + r'\b')
        if pat.search(_strip(rest_src)):
            return True
        pat2 = re.compile(r'\.' + re.escape(name) + r'\b')
        return any(pat2.search(_strip(s)) for s in others.values())

    # 搬变量：只被搬走的函数使用
    # 变量与（非 preload）常量：只被搬走的代码使用的，一并搬走
    var_blocks = [b for b in blocks if b[0] == "var" or (b[0] == "const" and b[1] not in preload_consts)]
    move_vars = []
    for b in var_blocks:
        name = b[1]
        if name in spec.get("keep_vars", []):
            continue
        # 按字符串名字访问的（如 STAT_SYNC 的 set(name, v)、get("name")）也算被使用，不能搬
        if re.search(r'["\']' + re.escape(name) + r'["\']', rest_src) or any(re.search(r'["\']' + re.escape(name) + r'["\']', s) for s in others.values()):
            continue
        if re.search(r'(?<![.\w$])' + re.escape(name) + r'\b', _strip(moved_src)) and not _used_in_rest(name, lines, in_moved, b) and not any(
                re.search(r'\.' + re.escape(name) + r'\b', _strip(s)) for s in others.values()):
            move_vars.append(b)
    moved_var_names = {b[1] for b in move_vars}
    # 初始化式引用了 game 成员的变量不能搬（模块构造时 g 还没设）；反复剔除直到稳定
    while True:
        bad = set()
        for b in move_vars:
            if b[1] not in moved_var_names:
                continue
            src = "\n".join(lines[b[2]:b[3]])
            init = src.split("=", 1)[1] if "=" in src else ""
            tmp = set()
            if "g." in rewrite(init, members - moved_var_names, moved_var_names, moved, rename, tmp, allow_self=True) or "self" in init:
                bad.add(b[1])
        if not bad:
            break
        for v in bad:
            print("变量初始化引用了 game 成员，留在 game.gd：", v)
        moved_var_names -= bad

    unknown = set()
    mod_members = members - moved_var_names
    out_funcs = []
    for a, b in moved_ranges:
        src = "\n".join(lines[a:b])
        loc = locals_of(src) | moved_var_names
        out_funcs.append(rewrite(src, mod_members, loc, moved, rename, unknown))
        # 函数定义行改名
    out_funcs = [re.sub(r'^((?:static\s+)?func\s+)([A-Za-z_]\w*)', lambda m: m.group(1) + rename.get(m.group(2), m.group(2)), f, flags=re.M) for f in out_funcs]
    out_vars = []
    for b in move_vars:
        src = "\n".join(lines[b[2]:b[3]])
        # 注释（紧贴上方）
        cs = b[2]
        while cs > 0 and lines[cs - 1].startswith("##"):
            cs -= 1
        doc = "\n".join(lines[cs:b[2]])
        if b[1] not in moved_var_names:
            continue
        body = rewrite(src, mod_members, moved_var_names | {b[1]}, moved, rename, unknown)
        out_vars.append((doc + "\n" if doc else "") + body)
    move_vars = [b for b in move_vars if b[1] in moved_var_names]

    # 需要的 preload 常量
    need_pre = [c for c in preload_consts if re.search(r'(?<![.\w])' + c + r'\b', "\n".join(out_funcs + out_vars))]
    header = "extends RefCounted\n" + "\n".join("## " + l if l else "##" for l in spec["doc"].split("\n")) + "\n\n"
    header += "\n".join(preload_consts[c] for c in need_pre) + ("\n\n" if need_pre else "")
    header += 'const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错\nvar g: Game\n'
    body = header + ("\n".join(out_vars) + "\n" if out_vars else "") + "\n\nfunc _init(game: Game) -> void:\n\tg = game\n\n\n" + "\n\n\n".join(f.strip("\n") for f in out_funcs) + "\n"

    # game.gd：删掉搬走的函数与变量，调用改成 field.name
    field = spec["field"]
    drop = set(i for i, v in enumerate(in_moved) if v)
    for b in move_vars:
        cs = b[2]
        while cs > 0 and lines[cs - 1].startswith("##"):
            cs -= 1
        drop.update(range(cs, b[3]))
    kept = [l for i, l in enumerate(lines) if i not in drop]
    new_game = "\n".join(kept)
    new_game = re.sub(r'\n{4,}', "\n\n\n", new_game)
    fixed = []
    for name in sorted(moved, key=len, reverse=True):
        pat = re.compile(r'(?<![.\w$"])' + re.escape(name) + r'\b')
        new_game, n = _sub_code(pat, lambda m: field + "." + rename.get(name, name), new_game)
        if n:
            fixed.append((name, n))
    # 声明
    const_line = 'const %s = preload("%s")' % (spec["const"], spec["module"])
    anchor = new_game.index("\nconst Bot = preload")
    anchor = new_game.index("\n", anchor + 1)
    new_game = new_game[:anchor] + "\n" + const_line + new_game[anchor:]
    var_anchor = new_game.index("\nvar rng := RandomNumberGenerator.new()")
    new_game = new_game[:var_anchor] + "\nvar %s = %s.new(self)   # %s" % (field, spec["const"], spec["doc"].split("\n")[0].split("：")[0]) + new_game[var_anchor:]

    # 其他脚本
    other_hits = []
    for p, s in others.items():
        s2 = s
        for name in moved:
            pat = re.compile(r'\b(g|game|_g|G)\.' + re.escape(name) + r'\b')
            s2, n = _sub_code(pat, lambda m: m.group(1) + "." + field + "." + rename.get(name, name), s2)
            if n:
                other_hits.append((os.path.relpath(p, ROOT), name, n))
            # 其他写法的 .name 引用（非 g./game.）列出来人工看
            for m in re.finditer(r'(\w+)\.' + re.escape(name) + r'\b', _strip(s2)):
                if m.group(1) not in ("g", "game", "_g", "G", field):
                    print("注意：", os.path.relpath(p, ROOT), m.group(0))
        if s2 != s:
            others[p] = s2
            if not dry:
                open(p, "wb").write(s2.encode("utf-8"))

    print("搬走函数 %d 个、变量 %d 个：%s" % (len(moved), len(move_vars), ", ".join(b[1] for b in move_vars)))
    print("game.gd 内调用改写：", fixed)
    print("其他脚本调用改写：", other_hits)
    if unknown:
        print("不认识的标识符（需人工确认）：", sorted(unknown))
    mod_path = os.path.join(ROOT, "game", spec["module"][len("res://"):].replace("/", os.sep))
    if dry:
        print("--dry：未写文件；模块 %d 行" % body.count("\n"))
        return
    os.makedirs(os.path.dirname(mod_path), exist_ok=True)
    open(mod_path, "wb").write((body.replace("\n", "\r\n") if crlf else body).encode("utf-8"))
    open(GAME, "wb").write((new_game.replace("\n", "\r\n") if crlf else new_game).encode("utf-8"))
    print("写入", mod_path, "（%d 行）；game.gd 剩 %d 行" % (body.count("\n"), new_game.count("\n")))


def _strip(s):
    """去掉字符串与注释（只用于查找引用）"""
    return "".join(t if not (t.startswith(("#", '"', "'", '&"', "&'", '^"'))) else " " for t in tokens(s))


def _sub_code(pat, repl, s):
    """只在代码里替换（跳过字符串 / 注释）"""
    out, n = [], 0
    for t in tokens(s):
        if t.startswith(("#", '"', "'", '&"', "&'", '^"')):
            out.append(t)
            continue
        out.append(t)
    # 逐 token 替换不方便处理 a.b 形式，退回整体替换但保护字符串 / 注释
    parts = re.split(r'("""[\s\S]*?"""|&?"(?:\\.|[^"\\\n])*"|&?\'(?:\\.|[^\'\\\n])*\'|#[^\n]*)', s)
    for i in range(0, len(parts), 2):
        parts[i], k = pat.subn(repl, parts[i])
        n += k
    return "".join(parts), n


def _used_in_rest(name, lines, in_moved, own_block):
    pat = re.compile(r'(?<![.\w$])' + re.escape(name) + r'\b')
    for i, l in enumerate(lines):
        if in_moved[i] or own_block[2] <= i < own_block[3]:
            continue
        if pat.search(_strip(l)):
            return True
    return False


if __name__ == "__main__":
    main()
