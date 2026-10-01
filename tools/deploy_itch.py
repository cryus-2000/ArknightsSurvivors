# -*- coding: utf-8 -*-
"""itch.io 发布预备（docs/33「itch.io」）：只发对外版——Windows 加密包推到 <ITCH_TARGET>:windows，网页版推到 <ITCH_TARGET>:html5。
对内版（全部解锁、演练开）绝不上 itch：脚本只认 audience = public 且验证报告 failures 为空的产物。

    python tools/deploy_itch.py --ref <提交>                     # dry-run：检查产物、生成 itch 网页 zip、打印 butler 命令（不上传）
    python tools/deploy_itch.py --ref <提交> --apply --confirm <提交>   # 真推（用户确认发布后才跑）

来源：build/release/final_<提交>/ 里 release_all.py 出的
    方舟幸存者_Public_Encrypted_<日期>_<提交>.zip   + encrypted_game_verification_public_<提交>.json
    web/                                           + web_verification_public_<提交>.json
itch 网页 zip：把 web/ 的内容（index.html 在 zip 根目录、没有外层文件夹）打成 方舟幸存者_itch_html5_<提交>.zip，同目录。
网页导出是单线程模板（export_presets.cfg Web：variant/thread_support=false），**不需要 SharedArrayBuffer / COOP·COEP 头**，
itch 页面的「SharedArrayBuffer support」不用勾；勾了也能跑（tools/serve_web.py --coi 本地验证过两种）。

配置（环境变量优先，其次仓库根目录 .deploy.env，已在 .gitignore；模板 .deploy.env.example）：
    BUTLER_API_KEY   itch 的 butler 密钥（https://itch.io/user/settings/api-keys）；只传给 butler 进程，不打印、不写日志
    ITCH_TARGET      <用户名>/<游戏名>，例如 someone/arknights-survivors
缺密钥或缺 butler 时只能 dry-run。--apply 需要 --confirm <提交>，并且要先经用户确认发布（docs/33 清单第 6 条）。
"""
import argparse, glob, json, os, shutil, subprocess, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "build" / "release"
NAME = "方舟幸存者"
ITCH_MAX_FILES = 1000            # itch 网页包上限（文件数）
ITCH_MAX_FILE = 200 * 1000 * 1000   # 单文件上限（itch 文档：200 MB）


def load_config():
    cfg = {}
    env_file = ROOT / ".deploy.env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    for k in ("BUTLER_API_KEY", "ITCH_TARGET"):
        if os.environ.get(k):
            cfg[k] = os.environ[k]
    return cfg


def report_ok(path, audience, commit):
    if not path.is_file():
        return "缺验证报告 %s" % path.name
    r = json.loads(path.read_text(encoding="utf-8"))
    if r.get("failures"):
        return "验证报告有失败项：%s" % r["failures"]
    if r.get("audience") != audience or r.get("commit") != commit:
        return "验证报告的 audience / 提交对不上：%s / %s" % (r.get("audience"), r.get("commit"))
    return ""


def make_html5_zip(web, out):
    files = sorted(p for p in web.iterdir() if p.is_file())
    names = [p.name for p in files]
    if "index.html" not in names:
        raise SystemExit("网页包里没有 index.html：%s" % web)
    if len(files) > ITCH_MAX_FILES:
        raise SystemExit("网页包文件数 %d 超过 itch 上限 %d" % (len(files), ITCH_MAX_FILES))
    big = [p.name for p in files if p.stat().st_size > ITCH_MAX_FILE]
    if big:
        raise SystemExit("有文件超过 itch 单文件上限：%s" % big)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in files:
            # 分片本身已是 gzip，再压没意义，按存储放
            z.write(p, p.name, compress_type=zipfile.ZIP_STORED if p.suffix == ".gz" else zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(out) as z:
        if "index.html" not in z.namelist():
            raise SystemExit("zip 根目录没有 index.html")
    return len(files)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--apply", action="store_true", help="真推（缺省只 dry-run）")
    ap.add_argument("--confirm", default="", help="--apply 时必须再写一遍提交号")
    ap.add_argument("--release-dir", type=Path, default=RELEASE, help="final_<提交>/ 所在目录（缺省 build/release）")
    a = ap.parse_args()
    commit = subprocess.run(["git", "rev-parse", "--short=8", a.ref], cwd=ROOT, stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    if a.apply and a.confirm != commit:
        raise SystemExit("--apply 需要 --confirm %s（发布前先经用户确认）" % commit)
    final = a.release_dir.resolve() / ("final_%s" % commit)
    wins = sorted(glob.glob(str(final / ("%s_Public_Encrypted_*_%s.zip" % (NAME, commit)))))
    if not wins:
        raise SystemExit("没有对外 Windows 包：先跑 python tools/release_all.py --ref %s --only public" % commit)
    win = Path(wins[-1])
    web = final / "web"
    if not (web / "index.html").is_file():
        raise SystemExit("没有对外网页包：先跑 python tools/release_all.py --ref %s --only web" % commit)
    problems = [p for p in (report_ok(final / ("encrypted_game_verification_public_%s.json" % commit), "public", commit),
                            report_ok(final / ("web_verification_public_%s.json" % commit), "public", commit)) if p]
    if problems:
        raise SystemExit("拒绝：%s" % "；".join(problems))
    html5 = final / ("%s_itch_html5_%s.zip" % (NAME, commit))
    n = make_html5_zip(web, html5)
    cfg = load_config()
    target = cfg.get("ITCH_TARGET", "")
    butler = shutil.which("butler")
    cmds = [["butler", "push", str(win), "%s:windows" % (target or "<ITCH_TARGET>"), "--userversion", commit],
            ["butler", "push", str(html5), "%s:html5" % (target or "<ITCH_TARGET>"), "--userversion", commit]]
    print("%s：提交 %s" % ("推送" if a.apply else "dry-run（不上传）", commit))
    print("  Windows：%s（%.1f MB）" % (win, win.stat().st_size / 1048576))
    print("  网页：%s（%d 个文件，%.1f MB，index.html 在根目录；单线程导出，不需要 SharedArrayBuffer）" % (html5, n, html5.stat().st_size / 1048576))
    print("  butler：%s；密钥：%s；目标：%s" % (butler or "未安装", "已配置（不显示）" if cfg.get("BUTLER_API_KEY") else "未配置", target or "未配置"))
    for c in cmds:
        print("  > " + " ".join(c))
    if not a.apply:
        print("（dry-run：没有上传。真推需要 butler、BUTLER_API_KEY、ITCH_TARGET，并经用户确认后加 --apply --confirm %s）" % commit)
        return
    if not butler or not cfg.get("BUTLER_API_KEY") or not target:
        raise SystemExit("缺 butler / BUTLER_API_KEY / ITCH_TARGET，不能推送")
    env = dict(os.environ, BUTLER_API_KEY=cfg["BUTLER_API_KEY"])
    for c in cmds:
        c[0] = butler
        p = subprocess.run(c, env=env)
        if p.returncode != 0:
            raise SystemExit("butler 失败：%s" % " ".join(c[1:3]))
    print("已推送：%s:windows、%s:html5（版本 %s）" % (target, target, commit))


if __name__ == "__main__":
    main()
