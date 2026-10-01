# -*- coding: utf-8 -*-
"""网页版部署到阿里云 OSS + CDN（docs/33「网页部署」）。缺省只做 dry-run：列出要上传的对象、响应头与要刷新的 CDN 地址，不连阿里云。

    python tools/deploy_web.py --ref <提交>                       # dry-run：对外 + 对内两个网页包
    python tools/deploy_web.py --ref <提交> --only public         # 只看对外（或 internal）
    python tools/deploy_web.py --ref <提交> --apply --confirm <提交>   # 真上传（用户确认发布后才跑；地域 / 域名定了才接通）

来源：build/release/final_<提交>/web/（对外）与 web_internal/（对内），由 tools/release_all.py 出；
必须有同目录的 web_verification_<public|internal>_<提交>.json 且 failures 为空、audience 与目标一致——
对内包（全部解锁、演练开）绝不会被传到对外地址。dry-run 时缺验证报告只警告，--apply 时直接拒绝。

布局（每个目标 = Bucket + 前缀 + CDN 域名）：
    <前缀>/index.html          Cache-Control: no-cache；部署时在 <head> 后插入 <base href="v/<提交>/">
    <前缀>/version.json        no-cache：提交号、audience、部署时间（排查用）
    <前缀>/v/<提交>/<其余文件>   public, max-age=31536000, immutable（网页包文件名不带哈希，所以按提交号分目录，旧版本留着可回滚）
分片 *.pck.NN.gz / *.wasm.NN.gz 按 application/octet-stream 原样存，不设 Content-Encoding（加载器按 1f8b 魔数自己解压，
CDN 若再压缩或解压也兼容）；文本类（html / js / json / txt）交给 CDN 智能压缩（gzip + brotli，在 CDN 控制台按类型开）。
上传完刷新 CDN：<域名>/<前缀>/index.html、<域名>/<前缀>/、version.json（版本目录是新路径，不用刷新）。

存档隔离：网页存档在浏览器 IndexedDB，按网站源（协议 + 域名 + 端口）隔离，所以对外 / 对内必须是两个不同的 CDN 域名；
同一个域名下分两个前缀会共用存档——脚本检查两边域名不同，相同就拒绝。

配置（全部走环境变量；也可写进仓库根目录 .deploy.env，已在 .gitignore，模板见 .deploy.env.example；环境变量优先）：
    OSS_ACCESS_KEY_ID / OSS_ACCESS_KEY_SECRET   RAM 子账号 AccessKey（只给这两个 Bucket 的写权限 + CDN 刷新权限）
    DEPLOY_REGION                               OSS 地域，例如 cn-hangzhou
    DEPLOY_PUBLIC_BUCKET / DEPLOY_PUBLIC_PREFIX / DEPLOY_PUBLIC_DOMAIN
    DEPLOY_INTERNAL_BUCKET / DEPLOY_INTERNAL_PREFIX / DEPLOY_INTERNAL_DOMAIN
真上传用阿里云官方 Python SDK（--apply 时才导入）：pip install alibabacloud-oss-v2 alibabacloud-cdn20180510
（OSS 用 V4 签名；按对象设置 Content-Type / Cache-Control；上传后逐个 HEAD 核对大小）。AccessKey 不打印、不写日志。
"""
import argparse, datetime, json, os, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "build" / "release"
LONG = "public, max-age=31536000, immutable"
NO_CACHE = "no-cache"
TYPES = {".html": "text/html; charset=utf-8", ".js": "application/javascript; charset=utf-8", ".json": "application/json; charset=utf-8",
         ".txt": "text/plain; charset=utf-8", ".png": "image/png", ".wasm": "application/wasm", ".gz": "application/octet-stream",
         ".pck": "application/octet-stream", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".ico": "image/x-icon"}
TARGETS = {"public": ("web", "PUBLIC"), "internal": ("web_internal", "INTERNAL")}
SECRET_KEYS = ("OSS_ACCESS_KEY_ID", "OSS_ACCESS_KEY_SECRET")


def load_config():
    """环境变量优先；没有的从仓库根目录 .deploy.env（KEY=VALUE，# 开头为注释）补"""
    cfg = {}
    env_file = ROOT / ".deploy.env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    for k, v in os.environ.items():
        if k.startswith("DEPLOY_") or k in SECRET_KEYS:
            cfg[k] = v
    return cfg


def target_conf(cfg, aud):
    tag = TARGETS[aud][1]
    prefix = cfg.get("DEPLOY_%s_PREFIX" % tag, "").strip("/")
    return {"bucket": cfg.get("DEPLOY_%s_BUCKET" % tag, ""), "prefix": prefix, "domain": cfg.get("DEPLOY_%s_DOMAIN" % tag, "").rstrip("/")}


def key(prefix, rel):
    return "/".join(p for p in (prefix, rel) if p)


def content_type(name):
    return TYPES.get(os.path.splitext(name)[1].lower(), "application/octet-stream")


def with_base(html, commit):
    """在 <head> 后插入 <base href="v/<提交>/">：页面里的相对地址（index.js、引擎取的 index.pck / index.wasm、加载器的分片）都落到版本目录"""
    if "<base " in html:
        raise SystemExit("index.html 已经有 <base>，不知道该怎么改写")
    m = re.search(r"<head[^>]*>", html)
    if not m:
        raise SystemExit("index.html 里找不到 <head>")
    return html[:m.end()] + '\n<base href="v/%s/">' % commit + html[m.end():]


def check_source(src, aud, commit, apply):
    """来源目录必须是 release_all 出的、验证通过、audience 与目标一致的那一份"""
    problems = []
    if not (src / "index.html").is_file():
        raise SystemExit("没有网页包：%s（先跑 python tools/release_all.py --ref %s --only %s）" % (src, commit, TARGETS[aud][0]))
    report = src.parent / ("web_verification_%s_%s.json" % (aud, commit))
    if not report.is_file():
        problems.append("缺验证报告 %s" % report.name)
    else:
        r = json.loads(report.read_text(encoding="utf-8"))
        if r.get("failures"):
            problems.append("验证报告有失败项：%s" % r["failures"])
        if r.get("audience") != aud or r.get("commit") != commit:
            problems.append("验证报告的 audience / 提交对不上：%s / %s" % (r.get("audience"), r.get("commit")))
        if Path(r.get("dir", "")).resolve() != src.resolve() and r.get("dir"):
            problems.append("验证报告验的是别的目录：%s" % r.get("dir"))
    if problems and apply:
        raise SystemExit("拒绝上传 %s：%s" % (aud, "；".join(problems)))
    return problems


def plan(src, aud, commit, tc, deployed_at):
    """要上传的对象：[(OSS key, 本地文件或 None, 内容 bytes 或 None, Content-Type, Cache-Control)]"""
    objs = []
    for f in sorted(p for p in src.iterdir() if p.is_file()):
        if f.name == "index.html":
            continue
        objs.append((key(tc["prefix"], "v/%s/%s" % (commit, f.name)), f, None, content_type(f.name), LONG))
    html = with_base((src / "index.html").read_text(encoding="utf-8"), commit).encode("utf-8")
    objs.append((key(tc["prefix"], "index.html"), None, html, TYPES[".html"], NO_CACHE))
    ver = json.dumps({"commit": commit, "audience": aud, "deployed_at": deployed_at}, ensure_ascii=False).encode("utf-8")
    objs.append((key(tc["prefix"], "version.json"), None, ver, TYPES[".json"], NO_CACHE))
    return objs


def refresh_urls(tc):
    base = "https://%s/%s" % (tc["domain"], (tc["prefix"] + "/") if tc["prefix"] else "")
    return [base, base + "index.html", base + "version.json"]


def apply_upload(cfg, tc, objs, urls):
    """真上传 + CDN 刷新（--apply）。2026-10-01 只写好、未接通：地域 / 域名用户定了再实测"""
    try:
        import alibabacloud_oss_v2 as oss
        from alibabacloud_cdn20180510.client import Client as CdnClient
        from alibabacloud_cdn20180510 import models as cdn_models
        from alibabacloud_tea_openapi import models as open_api_models
    except ImportError:
        raise SystemExit("缺阿里云 SDK：pip install alibabacloud-oss-v2 alibabacloud-cdn20180510")
    ak, sk = cfg.get("OSS_ACCESS_KEY_ID", ""), cfg.get("OSS_ACCESS_KEY_SECRET", "")
    if not ak or not sk or not cfg.get("DEPLOY_REGION"):
        raise SystemExit("缺 OSS_ACCESS_KEY_ID / OSS_ACCESS_KEY_SECRET / DEPLOY_REGION")
    conf = oss.config.load_default()
    conf.credentials_provider = oss.credentials.StaticCredentialsProvider(ak, sk)
    conf.region = cfg["DEPLOY_REGION"]
    client = oss.Client(conf)
    for k, path, data, ctype, cache in objs:
        body = data if data is not None else path.read_bytes()
        client.put_object(oss.PutObjectRequest(bucket=tc["bucket"], key=k, body=body, content_type=ctype, cache_control=cache))
        head = client.head_object(oss.HeadObjectRequest(bucket=tc["bucket"], key=k))
        if int(head.content_length) != len(body):
            raise SystemExit("上传后大小不符：%s" % k)
        print("  已上传 %s（%d 字节）" % (k, len(body)))
    cdn = CdnClient(open_api_models.Config(access_key_id=ak, access_key_secret=sk, endpoint="cdn.aliyuncs.com"))
    files = [u for u in urls if not u.endswith("/")]
    dirs = [u for u in urls if u.endswith("/")]
    if files:
        cdn.refresh_object_caches(cdn_models.RefreshObjectCachesRequest(object_path="\n".join(files), object_type="File"))
    if dirs:
        cdn.refresh_object_caches(cdn_models.RefreshObjectCachesRequest(object_path="\n".join(dirs), object_type="Directory"))
    print("  已提交 CDN 刷新：%s" % ", ".join(urls))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True, help="要部署的提交（build/release/final_<提交>/ 里的网页包）")
    ap.add_argument("--only", choices=list(TARGETS), help="只部署对外或对内")
    ap.add_argument("--apply", action="store_true", help="真上传（缺省只 dry-run）")
    ap.add_argument("--confirm", default="", help="--apply 时必须再写一遍提交号，防误操作")
    ap.add_argument("--release-dir", type=Path, default=RELEASE, help="final_<提交>/ 所在目录（缺省 build/release）")
    ap.add_argument("--stage", type=Path, default=None, help="dry-run 时按 OSS 布局把对象写进这个本地目录（<目录>/<public|internal>/<key>），用于本地起静态服务预览")
    a = ap.parse_args()
    commit = subprocess.run(["git", "rev-parse", "--short", a.ref], cwd=ROOT, stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    if a.apply and a.confirm != commit:
        raise SystemExit("--apply 需要 --confirm %s（发布前先经用户确认，docs/33 清单第 6 条）" % commit)
    cfg = load_config()
    auds = [a.only] if a.only else ["public", "internal"]
    tcs = {aud: target_conf(cfg, aud) for aud in TARGETS}
    pub, inn = tcs["public"], tcs["internal"]
    if pub["domain"] and inn["domain"] and pub["domain"].lower() == inn["domain"].lower():
        raise SystemExit("对外与对内用了同一个域名 %s：网页存档按网站源隔离，两版会共用存档。对内要换一个域名（或子域名）" % pub["domain"])
    if pub["bucket"] and pub["bucket"] == inn["bucket"] and pub["prefix"] == inn["prefix"]:
        raise SystemExit("对外与对内是同一个 Bucket 的同一个前缀，会互相覆盖")
    deployed_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print("%s：提交 %s（%s）" % ("上传" if a.apply else "dry-run（不连阿里云）", commit, "、".join(auds)))
    print("AccessKey：%s" % ("已配置（不显示）" if cfg.get("OSS_ACCESS_KEY_ID") else "未配置"), "；地域：%s" % (cfg.get("DEPLOY_REGION") or "未配置"))
    for aud in auds:
        tc = tcs[aud]
        src = a.release_dir.resolve() / ("final_%s" % commit) / TARGETS[aud][0]
        problems = check_source(src, aud, commit, a.apply)
        missing = [n for n, v in (("Bucket", tc["bucket"]), ("域名", tc["domain"])) if not v]
        if missing and a.apply:
            raise SystemExit("%s 缺配置：%s（DEPLOY_%s_*）" % (aud, "、".join(missing), TARGETS[aud][1]))
        objs = plan(src, aud, commit, tc, deployed_at)
        urls = refresh_urls(dict(tc, domain=tc["domain"] or "<DEPLOY_%s_DOMAIN>" % TARGETS[aud][1]))
        total = sum(len(d) if d is not None else p.stat().st_size for _, p, d, _, _ in objs)
        print("\n[%s] %s → oss://%s/%s（%d 个对象，%.1f MiB）" % (aud, src, tc["bucket"] or "<DEPLOY_%s_BUCKET>" % TARGETS[aud][1],
              (tc["prefix"] + "/") if tc["prefix"] else "", len(objs), total / 1048576))
        for p in problems:
            print("  ⚠ " + p + "（--apply 时会拒绝）")
        for k, p, d, ctype, cache in objs:
            size = len(d) if d is not None else p.stat().st_size
            print("  %-48s %10d  %-34s %s" % (k, size, ctype, cache))
        print("  CDN 刷新：" + "  ".join(urls))
        if a.stage and not a.apply:
            root = a.stage.resolve() / aud
            for k, p, d, _, _ in objs:
                dst = root / k
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(d if d is not None else p.read_bytes())
            print("  已按布局写到本地：%s（入口 %s）" % (root, root / key(tc["prefix"], "index.html")))
        if a.apply:
            apply_upload(cfg, tc, objs, urls)
    if not a.apply:
        print("\n（dry-run：没有连接阿里云。真上传要用户确认发布后加 --apply --confirm %s）" % commit)


if __name__ == "__main__":
    main()
