# -*- coding: utf-8 -*-
"""游戏改名草案（界面与美术 10-15，协调人派；预案见 docs/101_rename_plan.md）。缺省只打印计划，不改文件。

    python tools/rename_game.py 灯火深潜 "Lamplight Dive"                 # 只列计划（每条规则：文件、命中次数、改前 → 改后）
    python tools/rename_game.py 灯火深潜 "Lamplight Dive" --split 2       # 标题文字版拆分：前 2 字大号、其余小号（缺省 2）
    python tools/rename_game.py 灯火深潜 "Lamplight Dive" --apply         # 真的改（先确认计划；改完跑快检 --auto）
    python tools/rename_game.py ... --groups game,packaging               # 只做某几组（缺省全部）

只替换文案常量，**不动资源名与标识符**：存档目录 `ArknightsSurvivors`（project.godot custom_user_dir_name、settings.gd 迁移）、
exe / pck 文件名 `ArknightsSurvivors.exe`、itch 目标 slug、Toy slug、贴图名 `logo` 都保持原样（改了会丢存档 / 打包校验断 / 链接失效）。
每条规则写了「预期命中次数」，现场次数对不上就整组不改并报出来（代码漂移了，回 docs/101 核对后再更新本脚本）。

组：
  game       游戏内：窗口标题 / 网页 <title>（project.godot config/name）、Windows 产品名、标题页英文名与文字版标题、停用旧像素 Logo、致谢同人声明
  packaging  打包与发布：包文件夹 / zip 前缀（export_build / release_all / deploy_itch 三处必须一致）、包内说明.txt、runs_report 缺省名
  promo      宣传工具里的标题常量（promo_cover / promo_xhs）：改后要重出封面 / 小红书图
  copy       对外文案 Markdown（itch / Toy / 小红书 / 商店文案 docs/100）：全文替换中英文名
不在本脚本里、要人工做的（见 docs/101 §3）：新像素 Logo（Codex 单）、itch 页面标题、B站 Toy 标题（toy update）、Codex 有字封面重出。
"""
import argparse, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLD_CN = "方舟幸存者"
OLD_EN = "Arknights Survivors"


def spaced_upper(en):
    """标题页英文名的写法：全大写、词间两个空格（ARKNIGHTS  SURVIVORS）"""
    return "  ".join(w.upper() for w in en.split())


def rules(cn, en, split):
    a, b = cn[:split], cn[split:]
    old_sp, new_sp = spaced_upper(OLD_EN), spaced_upper(en)
    R = []   # (组, 文件, 旧, 新, 预期次数)
    # ---- game
    R += [
        ("game", "game/project.godot", 'config/name="%s"' % OLD_CN, 'config/name="%s"' % cn, 1),
        ("game", "game/export_presets.cfg", 'application/product_name="%s"' % OLD_EN, 'application/product_name="%s"' % en, 1),
        ("game", "game/scripts/title.gd", '"%s"' % old_sp, '"%s"' % new_sp, 1),
        ("game", "game/scripts/title.gd", 'UI.text(self, font, Vector2(tx, 182 + ly), "方舟", 96', 'UI.text(self, font, Vector2(tx, 182 + ly), "%s", 96' % a, 1),
        ("game", "game/scripts/title.gd", 'UI.text(self, font, Vector2(tx + 210, 180 + ly), "幸存者", 40',
         'UI.text(self, font, Vector2(tx + %d, 180 + ly), "%s", 40' % (105 * len(a), b), 1),
        # 旧像素 Logo 画的是旧名：停用，退回上面的文字版标题，等新 Logo（docs/101 §3.1）
        ("game", "game/scripts/title.gd", '	tex_logo = A.tex("logo")', '	tex_logo = null   # 改名（tools/rename_game.py）：旧像素 Logo 画的是旧名，停用到新 Logo 到货（docs/101 §3.1）', 1),
        ("game", "game/scripts/title.gd", '「%s」Logo' % OLD_CN, '「%s」Logo' % cn, 1),
        ("game", "game/scripts/game.gd", "## %s ——" % OLD_CN, "## %s ——" % cn, 1),
        ("game", "game/data/credits.json", "《%s》" % OLD_CN, "《%s》" % cn, 1),
    ]
    # ---- packaging（三处一致：export_build 打包文件夹 / zip 前缀 = release_all 暂存路径 = deploy_itch 查找前缀）
    R += [
        ("packaging", "tools/export_build.py", 'NAME = "%s"' % OLD_CN, 'NAME = "%s"' % cn, 1),
        ("packaging", "tools/export_build.py", 'README = """%s（' % OLD_CN, 'README = """%s（' % cn, 1),
        ("packaging", "tools/export_build.py", "       %s/" % OLD_CN, "       %s/" % cn, 1),
        ("packaging", "tools/release_all.py", '"_export", "%s")' % OLD_CN, '"_export", "%s")' % cn, 1),
        ("packaging", "tools/release_all.py", "    %s_" % OLD_CN, "    %s_" % cn, 2),
        ("packaging", "tools/deploy_itch.py", 'NAME = "%s"' % OLD_CN, 'NAME = "%s"' % cn, 1),
        ("packaging", "tools/deploy_itch.py", "%s_" % OLD_CN, "%s_" % cn, 2),
        ("packaging", "tools/runs_report.py", 'kv.get("config/name", "%s")' % OLD_CN, 'kv.get("config/name", "%s")' % cn, 1),
    ]
    # ---- promo
    R += [
        ("promo", "tools/promo_cover.py", 'TITLE = "%s"' % OLD_CN, 'TITLE = "%s"' % cn, 1),
        ("promo", "tools/promo_cover.py", 'TITLE_EN = "%s"' % OLD_EN.upper(), 'TITLE_EN = "%s"' % en.upper(), 1),
        ("promo", "tools/promo_xhs.py", '"%s", font=f, fill=GREY)' % OLD_CN, '"%s", font=f, fill=GREY)' % cn, 1),
        ("promo", "tools/promo_xhs.py", '("%s", 64, ORANGE1)' % OLD_EN, '("%s", 64, ORANGE1)' % en, 1),
    ]
    return R


COPY_FILES = ["art/promo/itch_page.md", "art/promo/toy_page.md", "art/promo/xhs/post.md", "docs/100_store_copy.md"]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cn", help="新中文名")
    ap.add_argument("en", help="新英文名（词间单空格，如 \"Lamplight Dive\"）")
    ap.add_argument("--split", type=int, default=2, help="标题文字版：前几个字用大号（缺省 2）")
    ap.add_argument("--groups", default="game,packaging,promo,copy")
    ap.add_argument("--apply", action="store_true", help="真的改文件（缺省只打印计划）")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    if not (1 <= a.split < len(a.cn)):
        sys.exit("--split 要在 1 到 %d 之间" % (len(a.cn) - 1))
    groups = a.groups.split(",")
    plan, bad = {}, []
    for g, f, old, new, n in rules(a.cn, a.en, a.split):
        if g not in groups:
            continue
        p = os.path.join(ROOT, f)
        s = open(p, encoding="utf-8").read() if os.path.exists(p) else ""
        hit = s.count(old)
        ok = hit == n
        print("[%s] %s  %s  命中 %d / 预期 %d\n      - %s\n      + %s" % (g, "OK " if ok else "!! ", f, hit, n, old.strip(), new.strip()))
        if not ok:
            bad.append(g)
        plan.setdefault(g, []).append((p, old, new))
    if "copy" in groups:
        for f in COPY_FILES:
            p = os.path.join(ROOT, f)
            if not os.path.exists(p):
                print("[copy] !!  %s 不存在" % f)
                continue
            s = open(p, encoding="utf-8").read()
            n_cn, n_en = s.count(OLD_CN), s.count(OLD_EN)
            print("[copy] OK  %s  中文名 %d 处、英文名 %d 处（全文替换）" % (f, n_cn, n_en))
            plan.setdefault("copy", []).append((p, OLD_CN, a.cn))
            plan["copy"].append((p, OLD_EN, a.en))
    bad = sorted(set(bad))
    if bad:
        print("\n命中次数对不上的组：%s —— 这些组不会改（代码变了，先回 docs/101 核对再更新规则）" % ", ".join(bad))
    if not a.apply:
        print("\n（只是计划；确认后加 --apply 执行，改完跑 python tools/check.py --auto）")
        return
    for g, items in plan.items():
        if g in bad:
            continue
        for p, old, new in items:
            s = open(p, encoding="utf-8").read()
            open(p, "w", encoding="utf-8", newline="").write(s.replace(old, new))
        print("已改：%s（%d 条）" % (g, len(items)))
    print("剩下人工步骤见 docs/101 §3（新 Logo、itch / Toy 页面标题、有字封面重出）")


if __name__ == "__main__":
    main()
