"""Linux 大小写检查（云端批跑前跑一遍，Windows 上也能跑）：Windows 文件名不分大小写，Linux 分。
代码 / 数据里写的路径大小写不对，本地照常加载，到了 Linux 就「找不到文件」（贴图变空、脚本加载失败）。

查三类：
  1. res:// 路径（.gd / .tscn / .tres / .json / project.godot 里的字面量）：文件存在但大小写对不上
  2. 美术名：A.tex("name") / tex_name 等写死的名字 → art/incoming/<name>.png 或 game/art/<name>.png 大小写对不上
  3. 仓库里只差大小写的两个文件（Linux 上是两个文件、Windows 上会互相覆盖）
动态拼出来的名字（"player_" + kind）查不到，要靠云端跑一局看日志里的 "Failed loading" / "Cannot open file"。
用法：python tools/cloud/case_check.py        退出码 0 = 没问题
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAME = os.path.join(ROOT, "game")
SKIP_DIRS = {".git", ".godot", "__pycache__", "node_modules", "build", ".claude", ".worktrees"}
TEXT_EXT = (".gd", ".tscn", ".tres", ".json", ".godot", ".cfg", ".gdshader")


def walk_files(base):
    for dp, dns, fns in os.walk(base):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for f in fns:
            yield os.path.join(dp, f)


def exact_exists(path):
    """逐级按真实大小写比对（Windows 上 os.path.exists 不分大小写，这里模拟 Linux）"""
    path = os.path.normpath(path)
    drive, rest = os.path.splitdrive(path)
    cur = drive + os.sep if drive else os.sep
    for part in [p for p in rest.split(os.sep) if p]:
        try:
            names = os.listdir(cur)
        except OSError:
            return False
        if part not in names:
            return False
        cur = os.path.join(cur, part)
    return True


def main():
    problems = []
    # 3. 只差大小写的文件
    seen = {}
    for p in walk_files(ROOT):
        rel = os.path.relpath(p, ROOT)
        k = rel.lower()
        if k in seen and seen[k] != rel:
            problems.append("仓库里只差大小写：%s  vs  %s" % (seen[k], rel))
        seen[k] = rel
    art_dirs = [os.path.join(ROOT, "art", "incoming"), os.path.join(GAME, "art")]
    res_re = re.compile(r'res://([^"\'\s)]+)')
    tex_re = re.compile(r'\b(?:A\.tex|tex\.get|g\.tex\.get|_spr|draw_spr|spr|fx_sprite|spawn_fx_sprite)\(\s*"([A-Za-z0-9_@\-]+)"')
    for p in walk_files(GAME):
        if not p.endswith(TEXT_EXT):
            continue
        try:
            src = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        rel = os.path.relpath(p, ROOT)
        # 1. res:// 路径
        for m in res_re.finditer(src):
            rp = m.group(1).rstrip(".,;:")
            if "%" in rp or "{" in rp or rp.endswith("/"):
                continue   # 格式化 / 目录前缀，查不了
            full = os.path.join(GAME, rp.replace("/", os.sep))
            if os.path.exists(full) and not exact_exists(full):
                problems.append("%s：res://%s 大小写和真实文件不一致" % (rel, rp))
        # 2. 写死的美术名
        for m in tex_re.finditer(src):
            name = m.group(1)
            for d in art_dirs:
                full = os.path.join(d, name + ".png")
                if os.path.exists(full) and not exact_exists(full):
                    problems.append("%s：美术名 \"%s\" 大小写和 %s 里的文件不一致" % (rel, name, os.path.relpath(d, ROOT)))
    if problems:
        print("发现 %d 处 Linux 上会出问题的大小写：" % len(problems))
        for x in sorted(set(problems)):
            print("  " + x)
        sys.exit(1)
    print("大小写检查通过（res:// 路径、写死的美术名、仓库文件名）")


if __name__ == "__main__":
    main()
