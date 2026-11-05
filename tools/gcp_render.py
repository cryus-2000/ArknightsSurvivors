#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在 GCP 虚拟机上出截图 / 录像（docs/256）：本机只写代码，不开 Godot 渲染。

  python tools/gcp_render.py --branch <分支或提交> --job <任务> [--args "<任务参数>"] [--name <名>]

做的事：tools/gcp/batch.py 开一台抢占式虚拟机 → checkout 指定提交 → 装 xvfb + Mesa 软件 OpenGL + 中文字体 + ffmpeg、生成 game/art/index.json →
跑任务脚本（Godot 一律 --rendering-driver opengl3，画在 Xvfb 虚拟屏上）→ 日志 / 报告推 cloud-results/render-<名> 分支，
PNG / MP4（任务写在 $MEDIA 下的）传 Cloud Storage → 本机下载到 <主仓库>/Claude outputs/render-<名>/。
媒体合计 ≤ --git-mb（缺省 20 MB）时另外也提交进 cloud-results/render-<名>（build/cloud/render-<名>/media/），超过只放桶里（7 天自动删）和本机。

任务（tools/gcp/render_jobs/<任务>.sh，与被测提交无关，总用本机这份）：
  pxplane    tools/pxplane_shots.py 的 demo / rec / trace（docs/246）；--args "demo;rec --seed 11 --from 480 --secs 20"
  trace_ab   同种子 TRACE 开 / 关对比；--args 'cases=skadi:23:300,mizuki:11:300 a="--bal=fx/px_plane=0" b="--bal=fx/px_plane=1"'
  custom     --cmd '<命令>'：自己写，PNG / MP4 放 $MEDIA

例：
  python tools/gcp_render.py --branch claude/pixelfx-plane-skadi --job pxplane --name skadi
  python tools/gcp_render.py --branch claude/pixelfx-plane-skadi --job trace_ab --args 'cases=skadi:23:300'
  python tools/gcp_render.py --branch HEAD --job custom --cmd 'python3 tools/pxplane_shots.py demo --modes 3 --out $MEDIA'
本机提交不在 origin 上也行（batch.py 会传 bundle）。原作参照图不上 GCP：要「原作」一栏，下载后在本机拼。
提速（docs/256 §7–8）：缺省 c2d-highcpu-8 + 预装镜像 arkr-render（开机到开始渲染约 1 分钟）；--split 把一个任务拆到多台并行
  （pxplane：demo 按招 4 台 + rec + trace；trace_ab：每局一台；custom：每条 --cmd 一台），结果合到同一个 cloud-results/render-<名>。
"""
import argparse, os, re, shlex, subprocess, sys, tempfile, time

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
GCPD = os.path.join(TOOLS, "gcp")
sys.path.insert(0, GCPD)
import batch as B


def resolve(ref):
    for r in (ref, "origin/" + ref):
        p = subprocess.run(["git", "-C", ROOT, "rev-parse", "--verify", "-q", r + "^{commit}"], capture_output=True, text=True)
        if p.returncode == 0:
            return p.stdout.strip()
    # 拉进一个本次专用的命名引用：FETCH_HEAD 是工作树共用的，几个会话同时跑会互相冲掉（11-05 金样重录因此写坏一次）
    tmp = "refs/gcp-render/resolve-%d" % os.getpid()
    subprocess.run(["git", "-C", ROOT, "fetch", "-q", "origin", "%s:%s" % (ref, tmp)], capture_output=True)
    p = subprocess.run(["git", "-C", ROOT, "rev-parse", "--verify", "-q", tmp + "^{commit}"], capture_output=True, text=True)
    subprocess.run(["git", "-C", ROOT, "update-ref", "-d", tmp], capture_output=True)
    if p.returncode == 0:
        return p.stdout.strip()
    sys.exit("找不到提交 / 分支：%s" % ref)


def main_root():
    d = subprocess.run(["git", "-C", ROOT, "rev-parse", "--git-common-dir"], capture_output=True, text=True).stdout.strip()
    d = d if os.path.isabs(d) else os.path.join(ROOT, d)
    return os.path.dirname(os.path.abspath(d))


def build_cmds(a):
    prep = open(os.path.join(GCPD, "render_prep.sh"), encoding="utf-8").read()
    parts = ["# ---- render_prep.sh ----", prep]
    # 辅助 Python 脚本原样写到 /work/（被测提交里可能没有）
    for helper in ("render_trace_ab.py",):
        body = open(os.path.join(GCPD, helper), encoding="utf-8").read()
        parts.append("cat > /work/%s <<'ARK_HELPER_EOF'\n%s\nARK_HELPER_EOF" % (helper, body))
    parts.append("export RENDER_ARGS=%s" % shlex.quote(a.args or ""))
    if a.args is None:
        parts.append("unset RENDER_ARGS")
    if a.job == "custom":
        if not a.cmd:
            sys.exit("--job custom 要给 --cmd")
        parts.append("# ---- custom ----\n" + "\n".join(a.cmd))
    else:
        f = os.path.join(GCPD, "render_jobs", a.job + ".sh")
        if not os.path.exists(f):
            sys.exit("没有任务 %s（tools/gcp/render_jobs/ 下：%s）" % (a.job, ", ".join(x[:-3] for x in os.listdir(os.path.dirname(f)))))
        parts.append("# ---- render_jobs/%s.sh ----\n( %s\n) || JOB_RC=$?" % (a.job, open(f, encoding="utf-8").read()))
    parts.append('find "$MEDIA" -type f -printf "%s\\t%P\\n" | sort -k2 > "$OUT/media_manifest.txt" || true')
    parts.append('echo "media：$(wc -l < "$OUT/media_manifest.txt") 个文件，$(du -sh "$MEDIA" | cut -f1)"')
    parts.append("exit ${JOB_RC:-0}")
    return "JOB_RC=0\n" + "\n".join(parts) + "\n"


def add_media_commit(tag, dest, files):
    """把下载下来的媒体加进 cloud-results/<tag> 的结果提交上（小体积时）"""
    base = subprocess.run(["git", "-C", ROOT, "rev-parse", "origin/cloud-results/" + tag], capture_output=True, text=True).stdout.strip()
    if not base:
        return None
    idx = os.path.join(tempfile.mkdtemp(), "index")
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    subprocess.run(["git", "-C", ROOT, "read-tree", base], env=env, check=True)
    for rel in files:
        blob = subprocess.run(["git", "-C", ROOT, "hash-object", "-w", os.path.join(dest, rel)], capture_output=True, text=True, check=True).stdout.strip()
        subprocess.run(["git", "-C", ROOT, "update-index", "--add", "--cacheinfo", "100644,%s,build/cloud/%s/media/%s" % (blob, tag, rel.replace(os.sep, "/"))],
                       env=env, check=True)
    tree = subprocess.run(["git", "-C", ROOT, "write-tree"], env=env, capture_output=True, text=True, check=True).stdout.strip()
    c = subprocess.run(["git", "-C", ROOT, "commit-tree", tree, "-p", base, "-m", "render %s：媒体 %d 个" % (tag, len(files))], capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run(["git", "-C", ROOT, "push", "-q", "-f", "origin", "%s:refs/heads/cloud-results/%s" % (c, tag)], check=True)
    return c


PX_DEFAULT = 'demo;rec --seed 11 --from 480 --secs 20;trace --seed 23 --maxt 300 --extra "--elite2 --sptest"'   # 同 render_jobs/pxplane.sh 缺省


def split_parts(a):
    """--split：把一个任务拆成几段，每段一台机器（docs/256 §8）。
    pxplane：按分号分子命令；不带 --modes 的 demo 再按招拆成 4 段（普攻 / S1 / S2 / S3，各自出三栏 + 三档图）。
    custom：每条 --cmd 一台。trace_ab：cases 里每局一台。"""
    if a.job == "pxplane":
        out = []
        for seg in [x.strip() for x in (a.args or PX_DEFAULT).split(";") if x.strip()]:
            if seg.split()[0] == "demo" and "--modes" not in seg:
                out += [("demo-m%s" % m, seg + " --modes %s" % m, None) for m in ("3", "0", "1", "2")]
            else:
                out.append((seg.split()[0], seg, None))
        return out
    if a.job == "custom":
        return [("c%d" % k, a.args, [c]) for k, c in enumerate(a.cmd or [])]
    if a.job == "trace_ab":
        m = re.search(r"cases=(\S+)", a.args or "")
        cs = m.group(1).split(",") if m else ["skadi:23:300"]
        return [(c.replace(":", "-"), (a.args or "").replace(m.group(0), "cases=" + c) if m else "cases=" + c, None) for c in cs]
    return [("all", a.args, a.cmd)]


def run_tag(tag, sha, a, args, cmd):
    b = argparse.Namespace(**vars(a))
    b.args, b.cmd = args, cmd
    cf = os.path.join(tempfile.mkdtemp(), "cmds.sh")
    open(cf, "w", encoding="utf-8", newline="\n").write(build_cmds(b))
    log = os.path.join(tempfile.mkdtemp(), tag + ".log")
    with open(log, "w", encoding="utf-8") as fh:
        rc = subprocess.run([sys.executable, "-I", os.path.join(GCPD, "batch.py"), "run", tag, "--commit", sha, "--cmd-file", cf,
                             "--machine", a.machine, "--hours", str(a.hours)] + (["--no-image"] if a.no_image else []),
                            stdout=fh if a.split else None, stderr=subprocess.STDOUT if a.split else None).returncode
    txt = open(log, encoding="utf-8", errors="replace").read() if a.split else ""
    return rc, txt


def fetch_media(tag, dest):
    gs = "gs://%s-batch/%s/media" % (B.project(), tag)
    ls = B.gc("storage", "ls", gs + "/**", check=False)
    if ls.returncode == 0 and ls.stdout.strip():
        B.gc("storage", "cp", "-r", gs + "/*", dest, "-q", check=False)
    return gs


def merge_parts(tag, sha, ptags):
    """各段的 cloud-results/<段> 合成一个 cloud-results/<tag>：build/cloud/<tag>/<段名>/…，合完删掉各段分支"""
    idx = os.path.join(tempfile.mkdtemp(), "index")
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    g = lambda *x, **kw: subprocess.run(["git", "-C", ROOT] + list(x), capture_output=True, text=True, **kw)
    g("read-tree", sha, env=env, check=True)
    got = []
    for pt, lab in ptags:
        if g("fetch", "-q", "origin", "refs/heads/cloud-results/%s:refs/remotes/origin/cloud-results/%s" % (pt, pt)).returncode != 0:
            continue
        r = g("read-tree", "--prefix=build/cloud/%s/%s/" % (tag, lab), "origin/cloud-results/%s:build/cloud/%s" % (pt, pt), env=env)
        if r.returncode == 0:
            got.append(pt)
    tree = g("write-tree", env=env, check=True).stdout.strip()
    c = g("commit-tree", tree, "-p", sha, "-m", "render %s：%d 段合并（%s）" % (tag, len(got), " ".join(got)), check=True).stdout.strip()
    g("push", "-q", "-f", "origin", "%s:refs/heads/cloud-results/%s" % (c, tag), check=True)
    for pt in got:
        g("push", "-q", "origin", "--delete", "cloud-results/" + pt)
    return c, got


def main():
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--branch", required=True, help="分支名（本机或 origin）或提交号")
    ap.add_argument("--job", required=True, help="tools/gcp/render_jobs/<任务>.sh，或 custom")
    ap.add_argument("--args", default=None, help="任务参数（见各任务脚本开头）")
    ap.add_argument("--cmd", action="append", help="--job custom 的命令（可多条）")
    ap.add_argument("--name", default=None, help="结果名：分支 cloud-results/render-<名>、本机目录 Claude outputs/render-<名>（缺省 任务-提交前 8 位）")
    ap.add_argument("--out", default=None, help="同 --name，写成 cloud-results/render-<名> 也认")
    ap.add_argument("--dest", default=None, help="本机下载目录（缺省 <主仓库>/Claude outputs/render-<名>）")
    ap.add_argument("--machine", default="c2d-highcpu-8", help="缺省 c2d-highcpu-8（docs/256 §7：同一 demo 449 秒，n2-standard-8 568、e2-standard-8 844，且最便宜）")
    ap.add_argument("--hours", type=float, default=2.0)
    ap.add_argument("--split", action="store_true", help="按子项拆到多台机器并行（pxplane：demo 按招 4 台 + rec + trace；custom：每条 --cmd 一台；trace_ab：每局一台）")
    ap.add_argument("--no-image", action="store_true", help="不用预装镜像 arkr-render（对照提速用）")
    ap.add_argument("--git-mb", type=float, default=20.0, help="媒体合计不超过这么多 MB 时也提交进结果分支；0 = 从不")
    ap.add_argument("--dry", action="store_true", help="只打印要下发的命令（--split 时打印拆分）")
    a = ap.parse_args()
    if a.job == "custom" and not a.cmd:
        sys.exit("--job custom 要给 --cmd")
    sha = resolve(a.branch)
    name = a.name or (re.sub(r"^cloud-results/render-", "", a.out) if a.out else "%s-%s" % (a.job, sha[:8]))
    tag = "render-" + re.sub(r"[^A-Za-z0-9._-]+", "-", name)
    parts = split_parts(a) if a.split else [("all", a.args, a.cmd)]
    if a.dry:
        if a.split:
            for lab, ar, cm in parts:
                print("[%s] args=%s cmd=%s" % (lab, ar, cm))
        else:
            print(build_cmds(a))
        return
    dest = a.dest or os.path.join(main_root(), "Claude outputs", tag)
    os.makedirs(dest, exist_ok=True)
    t0 = time.time()
    print("出图 %s：提交 %s，任务 %s %s%s" % (tag, sha[:10], a.job, a.args or "", "（拆 %d 台：%s）" % (len(parts), " / ".join(p[0] for p in parts)) if a.split else ""))
    if not a.split:
        rc, _ = run_tag(tag, sha, a, a.args, a.cmd)
        gs = fetch_media(tag, dest)
    else:
        from concurrent.futures import ThreadPoolExecutor
        ptags = [(tag + "-" + re.sub(r"[^A-Za-z0-9._-]+", "-", lab), lab) for lab, _, _ in parts]

        def one(k):
            pt, lab = ptags[k]
            time.sleep(k * 3)   # 错开开机请求
            t1 = time.time()
            rc1, txt = run_tag(pt, sha, a, parts[k][1], parts[k][2])
            fetch_media(pt, dest)
            sec = re.search(r"secs: (.*)", txt)
            print("  [%s] rc=%d %.1f 分钟 %s" % (lab, rc1, (time.time() - t1) / 60, sec.group(1) if sec else ""), flush=True)
            return rc1
        with ThreadPoolExecutor(len(parts)) as ex:
            rcs = list(ex.map(one, range(len(parts))))
        rc = max(rcs)
        c, got = merge_parts(tag, sha, ptags)
        print("合并 %d / %d 段 → cloud-results/%s（%s）" % (len(got), len(parts), tag, c[:10]))
        gs = "gs://%s-batch/%s-*/media" % (B.project(), tag)
    files = [os.path.relpath(os.path.join(dp, f), dest) for dp, _, fs in os.walk(dest) for f in fs]
    mb = sum(os.path.getsize(os.path.join(dest, f)) for f in files) / 1e6
    print("媒体 %d 个、%.1f MB → %s" % (len(files), mb, dest))
    if files and a.git_mb > 0 and mb <= a.git_mb:
        subprocess.run(["git", "-C", ROOT, "fetch", "-q", "origin", "refs/heads/cloud-results/%s:refs/remotes/origin/cloud-results/%s" % (tag, tag)], check=False)
        c = add_media_commit(tag, dest, files)
        if c:
            print("媒体也已提交进 cloud-results/%s（%s）" % (tag, c[:10]))
    elif files:
        print("媒体超过 %.0f MB，只放本机和 %s（7 天自动删）" % (a.git_mb, gs))
    print("全程 %.1f 分钟，rc=%d" % ((time.time() - t0) / 60, rc))
    sys.exit(rc)


if __name__ == "__main__":
    main()
