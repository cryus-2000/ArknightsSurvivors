"""本机大文件存档到 Cloud Storage（docs/41 §3.9 末）：腾硬盘，要用时拉回。只用本机 gcloud 登录，不建密钥。

  python tools/gcp/archive.py push <路径> [<路径> ...] [--delete]   # 上传 → 逐文件核对大小 + MD5 → （--delete）删本机
  python tools/gcp/archive.py pull <路径>                          # 拉回原位置（路径写法同 push，可只拉一个子目录 / 文件）
  python tools/gcp/archive.py ls [<前缀>]                          # 看桶里有什么（按存档清单）
  python tools/gcp/archive.py verify <路径>                        # 只核对，不删

路径：E:/ArknightsSurvivors 下的相对或绝对路径（主工作区的 build/...，或 .worktrees/... 等）；只收这个目录里的东西。
桶：gs://<项目>-archive（australia-southeast1，Nearline；最少计 30 天，拉回按量收费），对象名 = e-ark/<相对路径>。
清单：每次 push 往桶里 e-ark/_manifest/<时间>.json 写一份（相对路径、大小、MD5、本机修改时间），ls 读它。
"""
import argparse, base64, hashlib, json, os, shutil, subprocess, sys, tempfile, time

ROOT = "E:/ArknightsSurvivors"
PREFIX = "e-ark"
GCLOUD = shutil.which("gcloud") or shutil.which("gcloud.cmd") or "gcloud"


def gc(*a, check=True):
    # gcloud 本身是 Python：Windows 下管道输出缺省走 GBK，中文文件名会对不上核对表
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    r = subprocess.run([GCLOUD] + list(a), capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
    if check and r.returncode != 0:
        raise RuntimeError("gcloud %s\n%s" % (" ".join(a[:4]), r.stderr[-2000:]))
    return r


def bucket():
    p = gc("config", "get-value", "project").stdout.strip()
    return "gs://%s-archive" % p


def rel(path):
    ap = os.path.abspath(path if os.path.isabs(path) else os.path.join(ROOT, path)).replace("\\", "/")
    root = os.path.abspath(ROOT).replace("\\", "/")
    if not ap.lower().startswith(root.lower() + "/"):
        sys.exit("只收 %s 下的路径：%s" % (ROOT, path))
    return ap, ap[len(root) + 1:]


def local_files(ap):
    if os.path.isfile(ap):
        return [ap]
    out = []
    for d, _, fs in os.walk(ap):
        out += [os.path.join(d, f).replace("\\", "/") for f in fs]
    return sorted(out)


def md5_b64(fn):
    h = hashlib.md5()
    with open(fn, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return base64.b64encode(h.digest()).decode()


def remote_index(b, rp, is_file):
    """对象名 → (大小, md5)"""
    url = "%s/%s/%s" % (b, PREFIX, rp) + ("" if is_file else "/**")
    r = gc("storage", "objects", "list", url, "--format=json(name,size,md5_hash)", check=False)
    if r.returncode != 0:
        return {}
    return {o["name"]: (int(o["size"]), o.get("md5_hash", "")) for o in json.loads(r.stdout or "[]")}


def verify(b, ap, rp):
    files = local_files(ap)
    idx = remote_index(b, rp, os.path.isfile(ap))
    root = os.path.abspath(ROOT).replace("\\", "/")
    bad, rows = [], []
    for fn in files:
        name = "%s/%s" % (PREFIX, fn[len(root) + 1:])
        size, md5 = os.path.getsize(fn), md5_b64(fn)
        got = idx.get(name)
        if got != (size, md5):
            bad.append((name, (size, md5), got))
        rows.append({"path": fn[len(root) + 1:], "size": size, "md5": md5, "mtime": int(os.path.getmtime(fn))})
    return files, bad, rows


def cmd_push(a):
    b = bucket()
    manifest = []
    for p in a.paths:
        ap, rp = rel(p)
        if not os.path.exists(ap):
            print("不存在，跳过：", ap)
            continue
        n = len(local_files(ap))
        mb = sum(os.path.getsize(f) for f in local_files(ap)) / 1e6
        print("上传 %s（%d 个文件，%.0f MB）" % (rp, n, mb), flush=True)
        if os.path.isfile(ap):
            gc("storage", "cp", ap, "%s/%s/%s" % (b, PREFIX, rp))
        else:
            gc("storage", "rsync", "-r", ap, "%s/%s/%s" % (b, PREFIX, rp))
        files, bad, rows = verify(b, ap, rp)
        if bad:
            print("  核对失败 %d / %d，不删：" % (len(bad), len(files)), bad[:3])
            continue
        print("  核对通过 %d / %d" % (len(files), len(files)), flush=True)
        manifest += rows
        if a.delete:
            shutil.rmtree(ap) if os.path.isdir(ap) else os.remove(ap)
            print("  已删本机", ap)
    if manifest:
        tmp = os.path.join(tempfile.mkdtemp(), "m.json")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"time": time.strftime("%Y-%m-%d %H:%M:%S"), "files": manifest}, f, ensure_ascii=False)
        gc("storage", "cp", tmp, "%s/%s/_manifest/%s.json" % (b, PREFIX, time.strftime("%Y%m%d_%H%M%S")))


def cmd_verify(a):
    b = bucket()
    for p in a.paths:
        ap, rp = rel(p)
        files, bad, _ = verify(b, ap, rp)
        print("%s：%d 个文件，不一致 %d" % (rp, len(files), len(bad)))
        for x in bad[:5]:
            print("  ", x)


def cmd_pull(a):
    b = bucket()
    ap, rp = rel(a.path)
    src = "%s/%s/%s" % (b, PREFIX, rp)
    if gc("storage", "objects", "describe", src, check=False).returncode == 0:
        os.makedirs(os.path.dirname(ap), exist_ok=True)
        gc("storage", "cp", src, ap)
    else:
        os.makedirs(ap, exist_ok=True)
        gc("storage", "rsync", "-r", src, ap)
    print("已拉回", ap)


def cmd_ls(a):
    b = bucket()
    r = gc("storage", "ls", "%s/%s/_manifest/" % (b, PREFIX), check=False)
    tops = {}
    for m in r.stdout.split():
        for f in json.loads(gc("storage", "cat", m).stdout)["files"]:
            if a.prefix and not f["path"].startswith(a.prefix):
                continue
            parts = f["path"].split("/")
            k = "/".join(parts[:2] if len(parts) > 2 else parts)
            t = tops.setdefault(k, [0, 0])
            t[0] += 1
            t[1] += f["size"]
    for k in sorted(tops):
        print("%-70s %6d 个  %8.1f MB" % (k, tops[k][0], tops[k][1] / 1e6))


def main():
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="op", required=True)
    p = sub.add_parser("push"); p.add_argument("paths", nargs="+"); p.add_argument("--delete", action="store_true")
    v = sub.add_parser("verify"); v.add_argument("paths", nargs="+")
    q = sub.add_parser("pull"); q.add_argument("path")
    l = sub.add_parser("ls"); l.add_argument("prefix", nargs="?", default="")
    a = ap.parse_args()
    {"push": cmd_push, "verify": cmd_verify, "pull": cmd_pull, "ls": cmd_ls}[a.op](a)


if __name__ == "__main__":
    main()
