"""网页加载页多语言（11-16，docs/22「加载链路」）：生成 tools/web/boot_l10n.js 的内联文本。
字典 = tools/web/loader_l10n.json：ui 段按 key 从 game/l10n/ui.csv 取英 / 日 / 韩（游戏里已有的术语），hand 段手写。
Toy 包锁中文：LOCK = 1、字典为空（不带外语文案）。
用法：import web_loader_l10n; web_loader_l10n.boot_js(root, toy)；单独跑 python tools/web_loader_l10n.py 检查字典（缺 key / 缺语言报错）。
"""
import csv, json, os, sys

LANGS = ("en", "ja", "ko")


def table(root):
    """{中文原文: [en, ja, ko]}；ui.csv 里找不到的 key 直接报错（改了 key 要跟着改 loader_l10n.json）"""
    src = json.load(open(os.path.join(root, "tools", "web", "loader_l10n.json"), encoding="utf-8"))
    rows = {r["keys"]: r for r in csv.DictReader(open(os.path.join(root, "game", "l10n", "ui.csv"), encoding="utf-8"))}
    out, bad = {}, []
    for zh, key in src["ui"].items():
        r = rows.get(key)
        if not r or not all(r.get(lg) for lg in LANGS):
            bad.append("%s（%s）" % (zh, key))
            continue
        out[zh] = [r[lg] for lg in LANGS]
    for zh, v in src["hand"].items():
        if not (isinstance(v, list) and len(v) == 3 and all(v)):
            bad.append(zh)
            continue
        out[zh] = v
    if bad:
        raise SystemExit("loader_l10n.json：ui.csv 里找不到或缺语言：%s" % "、".join(bad))
    return out


def boot_js(root, toy):
    js = open(os.path.join(root, "tools", "web", "boot_l10n.js"), encoding="utf-8").read()
    assert "/*SY_LOCK_ZH*/0" in js and "/*SY_L10N*/{}" in js
    d = {} if toy else table(root)
    return js.replace("/*SY_LOCK_ZH*/0", "1" if toy else "0").replace("/*SY_L10N*/{}", json.dumps(d, ensure_ascii=False, separators=(",", ":")))


def shell_html(root, toy):
    """首帧壳：诊断卡底下那行反馈提示按渠道写（Toy 私信 UP 主，只中文；itch 发到页面评论区，四种语言）"""
    html = open(os.path.join(root, "tools", "web", "boot_shell.html"), encoding="utf-8").read()
    assert "<!--SY_HINT-->" in html
    if toy:
        hint = '<span class="l-zh">截图这张卡私信 UP 主</span>'
    else:
        zh = "截图这张卡，发到 itch 页面的评论区"
        tr = table(root)[zh]
        hint = '<span class="l-zh">%s</span><span class="l-en">%s</span><span class="l-ja">%s</span><span class="l-ko">%s</span>' % ((zh,) + tuple(tr))
    return html.replace("<!--SY_HINT-->", hint)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    t = table(root)
    print("加载页字典 %d 条（en / ja / ko 齐）" % len(t))
    sys.exit(0)
