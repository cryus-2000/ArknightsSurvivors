"""在 Google Cloud 虚拟机上跑批跑（docs/41 §3.9）：不花 Claude 额度，结果照旧推到 cloud-results/<tag>。

  python tools/gcp/batch.py run <tag> [--commit <提交>] --cmd "<命令>" [--cmd ...]   # 一条命令跑完：开机 → 跑 → 收结果 → 推分支 → 删机
  python tools/gcp/batch.py run <tag> --cmd-file cmds.sh
  python tools/gcp/batch.py collect <tag>     # 本机中途断了：虚拟机跑完后再收结果、推分支
  python tools/gcp/batch.py ls                # 列出还在的批跑虚拟机（应当为空）
  python tools/gcp/batch.py kill <tag>        # 手动删机

命令在虚拟机的仓库根目录用 bash 跑（set -euo pipefail），已 source tools/cloud/env.sh，可用变量：
  $OUT = build/cloud/<tag>（结果放这里，只有它会被收回）、$TAG、$GODOT、$GODOT_MAX_PROCS（= 核数）。
例：
  --cmd 'python3 tools/balance_run.py --preset starts --bot expert --seeds 4 --nocache --jobs $GODOT_MAX_PROCS --tag $TAG --out $OUT'
  --cmd 'bash tools/cloud/run_cloud.sh && mv build/cloud/[0-9]*_*/ $OUT/'

虚拟机：缺省 e2-standard-8 抢占式（spot），us-central1-a，最长 --hours 小时后由 GCE 强制删除；
跑完（成功或失败）虚拟机自己删除，本机脚本结束时再删一次兜底。抢占式被回收时自动改用标准机重跑一次。
虚拟机上没有 GitHub 令牌：只读拉公开仓库，结果传 Cloud Storage（gs://<项目>-batch/<tag>/，7 天自动删），由本机推分支。
"""
import argparse, io, json, os, re, shutil, subprocess, sys, tarfile, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
GCLOUD = shutil.which("gcloud") or shutil.which("gcloud.cmd") or "gcloud"
# us-central1 牌价（美元 / 小时，2026-10），只用于估算花费
PRICE = {("e2-standard-8", "SPOT"): 0.0806, ("e2-standard-8", "STANDARD"): 0.2681,
         ("e2-highcpu-8", "SPOT"): 0.0595, ("e2-highcpu-8", "STANDARD"): 0.1979,
         ("e2-standard-4", "SPOT"): 0.0403, ("e2-standard-4", "STANDARD"): 0.1340}
EXTRA_PER_H = 0.005 + 0.0055   # 临时外网 IP + 30 GB pd-balanced


def sh(args, check=True, capture=True, inp=None):
    r = subprocess.run(args, capture_output=capture, text=True, encoding="utf-8", errors="replace", input=inp)
    if check and r.returncode != 0:
        raise RuntimeError("%s\n%s" % (" ".join(args[:6]), (r.stderr or "")[-2000:]))
    return r


def gc(*a, **kw):
    return sh([GCLOUD] + list(a), **kw)


def git(*a, **kw):
    return sh(["git", "-C", REPO] + list(a), **kw)


def project():
    p = gc("config", "get-value", "project").stdout.strip()
    if not p:
        sys.exit("gcloud 没有设置项目（gcloud config set project <id>）")
    return p


def vm_name(tag):
    n = "batch-" + re.sub(r"[^a-z0-9-]+", "-", tag.lower()).strip("-")
    return n[:63].rstrip("-")


def ensure_bucket(bucket, region):
    if gc("storage", "buckets", "describe", "gs://" + bucket, check=False).returncode == 0:
        return
    print("建桶 gs://%s（%s，对象 7 天后自动删）" % (bucket, region))
    gc("storage", "buckets", "create", "gs://" + bucket, "--location", region, "--uniform-bucket-level-access")
    rule = os.path.join(tempfile.mkdtemp(), "lc.json")
    with open(rule, "w") as f:
        json.dump({"rule": [{"action": {"type": "Delete"}, "condition": {"age": 7}}]}, f)
    gc("storage", "buckets", "update", "gs://" + bucket, "--lifecycle-file", rule)


def gs_cat(path):
    r = gc("storage", "cat", path, check=False)
    return r.stdout if r.returncode == 0 else None


def vm_exists(name, zone):
    return gc("compute", "instances", "describe", name, "--zone", zone, "--format=value(status)", check=False).returncode == 0


def delete_vm(name, zone):
    if vm_exists(name, zone):
        print("删除虚拟机", name)
        gc("compute", "instances", "delete", name, "--zone", zone, "--quiet", check=False)


def on_origin(sha):
    """提交是否已在 origin 的某个分支上（是就让虚拟机直接从 GitHub 浅拉）"""
    r = git("branch", "-r", "--contains", sha, check=False)
    return r.returncode == 0 and any(l.strip().startswith("origin/") for l in r.stdout.splitlines())


def create_vm(a, name, gs, sha, base, cmds, model):
    md = {"batch-tag": a.tag, "batch-commit": sha, "batch-gs": gs, "batch-timeout": str(int(a.hours * 3600 - 900))}
    if base:
        md["batch-bundle-base"] = base
    tmp = tempfile.mkdtemp()
    cmdf = os.path.join(tmp, "cmds.sh")
    with open(cmdf, "w", encoding="utf-8", newline="\n") as f:
        f.write(cmds + "\n")
    args = ["compute", "instances", "create", name, "--zone", a.zone, "--machine-type", a.machine,
            "--image-family", "debian-12", "--image-project", "debian-cloud",
            "--boot-disk-size", "30GB", "--boot-disk-type", "pd-balanced",
            "--scopes", "cloud-platform", "--labels", "purpose=batch",
            "--provisioning-model", model, "--instance-termination-action", "DELETE",
            "--max-run-duration", "%ds" % int(a.hours * 3600),
            "--metadata", ",".join("%s=%s" % kv for kv in md.items()),
            "--metadata-from-file", "startup-script=%s,batch-cmds=%s" % (os.path.join(HERE, "vm_startup.sh"), cmdf)]
    print("开机 %s（%s %s，%s，最长 %.1f 小时）" % (name, a.machine, model, a.zone, a.hours))
    gc(*args)


def wait(name, zone, gs, poll):
    """等 done 标记；返回 rc，虚拟机没打标记就消失（被抢占 / 超时）返回 None"""
    last = ""
    while True:
        time.sleep(poll)
        done = gs_cat(gs + "/done")
        if done is not None:
            return int(done.strip() or 1)
        st = (gs_cat(gs + "/status") or "").strip()
        prog = (gs_cat(gs + "/progress") or "").strip().splitlines()
        line = "[%s] %s | %s" % (time.strftime("%H:%M"), st, prog[-1][:120] if prog else "")
        if line[8:] != last:
            print(line, flush=True)
            last = line[8:]
        if not vm_exists(name, zone):
            time.sleep(20)   # 刚写完 done 就删机的竞态
            done = gs_cat(gs + "/done")
            return int(done.strip() or 1) if done is not None else None


def collect(tag, sha, gs, push=True):
    """下载结果 → 在被测提交之上建一个只加 build/cloud/<tag>/ 的提交 → 推 cloud-results/<tag>"""
    tmp = tempfile.mkdtemp(prefix="gcpbatch_")
    tgz = os.path.join(tmp, "result.tar.gz")
    gc("storage", "cp", gs + "/result.tar.gz", tgz, "-q")
    idx = os.path.join(tmp, "index")
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    subprocess.run(["git", "-C", REPO, "read-tree", sha], env=env, check=True)
    n = 0
    with tarfile.open(tgz) as t:
        for m in t.getmembers():
            if not m.isfile() or ".." in m.name.split("/"):
                continue
            data = t.extractfile(m).read()
            blob = subprocess.run(["git", "-C", REPO, "hash-object", "-w", "--stdin"], input=data,
                                  capture_output=True, check=True).stdout.decode().strip()
            subprocess.run(["git", "-C", REPO, "update-index", "--add", "--cacheinfo",
                            "100644,%s,build/cloud/%s" % (blob, m.name)], env=env, check=True)
            n += 1
    tree = subprocess.run(["git", "-C", REPO, "write-tree"], env=env, capture_output=True, check=True, text=True).stdout.strip()
    commit = git("commit-tree", tree, "-p", sha, "-m", "cloud %s (gcp)" % tag).stdout.strip()
    print("结果 %d 个文件 → 提交 %s" % (n, commit[:10]))
    if push:
        git("push", "-f", "origin", "%s:refs/heads/cloud-results/%s" % (commit, tag))
        git("fetch", "-q", "origin", "refs/heads/cloud-results/%s:refs/remotes/origin/cloud-results/%s" % (tag, tag), check=False)
        print("已推 cloud-results/%s" % tag)
    shutil.rmtree(tmp, ignore_errors=True)
    return commit


def env_txt(gs, tag):
    tmp = tempfile.mkdtemp()
    gc("storage", "cp", gs + "/result.tar.gz", os.path.join(tmp, "r.tgz"), "-q")
    with tarfile.open(os.path.join(tmp, "r.tgz")) as t:
        try:
            return t.extractfile("%s/env.txt" % tag).read().decode("utf-8", "replace")
        except KeyError:
            return ""


def cmd_run(a):
    proj = project()
    bucket = proj + "-batch"
    region = a.zone.rsplit("-", 1)[0]
    gs = "gs://%s/%s" % (bucket, a.tag)
    sha = git("rev-parse", "--verify", a.commit + "^{commit}").stdout.strip()
    cmds = "\n".join(a.cmd or [])
    if a.cmd_file:
        cmds += "\n" + open(a.cmd_file, encoding="utf-8").read()
    if not cmds.strip():
        sys.exit("没有要跑的命令（--cmd / --cmd-file）")
    name = vm_name(a.tag)
    ensure_bucket(bucket, region)
    gc("storage", "rm", "-r", gs, "-q", check=False)   # 同名重跑：清掉旧标记
    base = ""
    if not on_origin(sha):
        base = git("merge-base", sha, "origin/main").stdout.strip()
        tmp = tempfile.mkdtemp()
        bnd = os.path.join(tmp, "repo.bundle")
        git("bundle", "create", bnd, sha, "^" + base)
        print("提交 %s 不在 origin 上：上传 bundle（基于 %s，%.1f MB）" % (sha[:10], base[:10], os.path.getsize(bnd) / 1e6))
        gc("storage", "cp", bnd, gs + "/repo.bundle", "-q")
    t0 = time.time()
    model = "STANDARD" if a.standard else "SPOT"
    rc = None
    try:
        for attempt in range(2):
            create_vm(a, name, gs, sha, base, cmds, model)
            rc = wait(name, a.zone, gs, a.poll)
            if rc is not None or model == "STANDARD":
                break
            print("抢占式虚拟机没跑完就没了（被回收或超时），改用标准机重跑一次")
            model = "STANDARD"
    except KeyboardInterrupt:
        print("中断")
    finally:
        delete_vm(name, a.zone)
    mins = (time.time() - t0) / 60
    if rc is None:
        log = gs_cat(gs + "/vm.log") or ""
        print("\n".join(log.splitlines()[-30:]))
        sys.exit("虚拟机没跑完（%.1f 分钟）；日志在 %s/vm.log" % (mins, gs))
    print(env_txt(gs, a.tag).strip())
    cost = mins / 60 * (PRICE.get((a.machine, model), 0.27) + EXTRA_PER_H)
    print("rc=%d  全程 %.1f 分钟  估算花费 $%.3f（%s %s 牌价）" % (rc, mins, cost, a.machine, model))
    if rc in (97, 98):
        sys.exit("虚拟机准备失败（rc=%d），没有结果；日志 %s/vm.log" % (rc, gs))
    collect(a.tag, sha, gs, push=not a.no_push)
    sys.exit(rc)


def cmd_collect(a):
    gs = "gs://%s-batch/%s" % (project(), a.tag)
    if gs_cat(gs + "/done") is None:
        sys.exit("%s 还没有 done 标记" % gs)
    sha = re.search(r"commit: (\w+)", env_txt(gs, a.tag)).group(1)
    collect(a.tag, sha, gs, push=not a.no_push)


def cmd_ls(a):
    print(gc("compute", "instances", "list", "--filter", "labels.purpose=batch",
             "--format", "table(name,zone.basename(),machineType.basename(),status,creationTimestamp)").stdout or "（没有）")


def cmd_kill(a):
    delete_vm(vm_name(a.tag), a.zone)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="op", required=True)
    r = sub.add_parser("run")
    r.add_argument("tag")
    r.add_argument("--commit", default="HEAD")
    r.add_argument("--cmd", action="append")
    r.add_argument("--cmd-file")
    r.add_argument("--machine", default="e2-standard-8")
    r.add_argument("--zone", default="us-central1-a")
    r.add_argument("--standard", action="store_true", help="用标准机（缺省抢占式 spot，便宜约 70%%）")
    r.add_argument("--hours", type=float, default=3.0, help="最长运行时间，到点 GCE 强制删机")
    r.add_argument("--poll", type=int, default=60)
    r.add_argument("--no-push", action="store_true", help="只建结果提交不推（调试用）")
    c = sub.add_parser("collect")
    c.add_argument("tag")
    c.add_argument("--no-push", action="store_true")
    sub.add_parser("ls")
    k = sub.add_parser("kill")
    k.add_argument("tag")
    k.add_argument("--zone", default="us-central1-a")
    a = ap.parse_args()
    {"run": cmd_run, "collect": cmd_collect, "ls": cmd_ls, "kill": cmd_kill}[a.op](a)


if __name__ == "__main__":
    main()
