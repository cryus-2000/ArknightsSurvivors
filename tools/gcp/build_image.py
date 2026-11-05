"""做 GCP 预装镜像（docs/256 §7）：开一台临时机跑 tools/gcp/image_setup.sh → 关机 → 从系统盘建镜像（family arkr-render）→ 删临时机。

  python tools/gcp/build_image.py                 # 预热用 claude/integ-1105 的导入缓存
  python tools/gcp/build_image.py --ref main

之后 batch.py / gcp_render.py 缺省用 family arkr-render 的最新镜像开机（没有这个 family 时退回 debian-12）。
素材大改后重做一次镜像，导入缓存就跟上了；旧镜像留着不碍事（同 family 取最新），可以 gcloud compute images delete 清。
"""
import argparse, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import batch as B

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", default="claude/integ-1105")
    ap.add_argument("--zone", default="us-central1-a")
    ap.add_argument("--family", default="arkr-render")
    a = ap.parse_args()
    proj = B.project()
    bucket = proj + "-batch"
    B.ensure_bucket(bucket, a.zone.rsplit("-", 1)[0])
    sa = B.ensure_identity(proj, bucket)
    name = "arkr-image-build"
    gs = "gs://%s/_image/%d" % (bucket, int(time.time()))
    t0 = time.time()
    B.gc("compute", "instances", "create", name, "--zone", a.zone, "--machine-type", "e2-standard-8",
         "--image-family", "debian-12", "--image-project", "debian-cloud", "--boot-disk-size", "20GB", "--boot-disk-type", "pd-balanced",
         "--service-account", sa, "--scopes", "cloud-platform", "--labels", "purpose=image",
         "--metadata", "image-gs=%s,image-ref=%s" % (gs, a.ref), "--metadata-from-file", "startup-script=" + os.path.join(HERE, "image_setup.sh"))
    print("临时机 %s 开机，装环境 + 预热导入（约 10 分钟）" % name)
    try:
        while True:
            time.sleep(30)
            d = B.gs_cat(gs + "/done")
            if d is not None:
                if d.strip() != "0":
                    sys.exit("镜像准备失败：%s（日志在临时机 /var/log/arkr_image.log）" % d.strip())
                break
        while "TERMINATED" not in B.gc("compute", "instances", "describe", name, "--zone", a.zone, "--format", "value(status)").stdout:
            time.sleep(10)
        img = "%s-%s" % (a.family, time.strftime("%m%d-%H%M"))
        B.gc("compute", "images", "create", img, "--source-disk", name, "--source-disk-zone", a.zone, "--family", a.family)
        print("镜像 %s（family %s）做好，用时 %.1f 分钟" % (img, a.family, (time.time() - t0) / 60))
    finally:
        B.gc("compute", "instances", "delete", name, "--zone", a.zone, "--quiet", check=False)


if __name__ == "__main__":
    main()
