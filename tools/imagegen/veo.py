"""Veo 图生视频（Vertex AI），给 PV 做动态预演用：拿一张参考图当首帧，生成一段几秒的镜头运动。

  python tools/imagegen/veo.py --tag op_reef --image first.png [--last last.png] --prompt "..." [--seconds 8] [--model veo-3.1-fast-generate-001]

- 只用标准库直连；令牌每次调 gcloud 现取（复用 pixgen._gcloud），项目取 gcloud 当前项目；不打印、不写盘。
- 按生成的秒数计费（Vertex 项目账单）；缺省快速版、不出声音（PV 有配乐）。
- 产物在 build/imagegen/<tag>/veo_*.mp4（不进 git）+ log.json。只作预演 / 参考，不进成片。
"""
import argparse, base64, json, sys, time, urllib.request, urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixgen import _gcloud, OUT  # noqa: E402

BASE = "https://us-central1-aiplatform.googleapis.com/v1/projects/{p}/locations/us-central1/publishers/google/models/{m}"


def _post(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={
        "Content-Type": "application/json", "Authorization": "Bearer " + _gcloud("auth", "print-access-token")})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit("HTTP %d: %s" % (e.code, e.read().decode()[:600]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--seconds", type=int, default=8)
    ap.add_argument("--model", default="veo-3.1-fast-generate-001")
    ap.add_argument("--resolution", default="1080p")
    ap.add_argument("--last", default="", help="尾帧图（可选）：给定首尾帧逼出镜头运动——推镜头用原图 → 裁近图，拉远反过来")
    a = ap.parse_args()
    base = BASE.format(p=_gcloud("config", "get-value", "project"), m=a.model)
    img = base64.b64encode(Path(a.image).read_bytes()).decode()
    inst = {"prompt": a.prompt, "image": {"bytesBase64Encoded": img, "mimeType": "image/png"}}
    if a.last:
        inst["lastFrame"] = {"bytesBase64Encoded": base64.b64encode(Path(a.last).read_bytes()).decode(), "mimeType": "image/png"}
    body = {"instances": [inst],
            "parameters": {"aspectRatio": "16:9", "durationSeconds": a.seconds, "sampleCount": 1,
                           "generateAudio": False, "resolution": a.resolution}}
    op = _post(base + ":predictLongRunning", body)["name"]
    t0 = time.time()
    while True:
        time.sleep(10)
        r = _post(base + ":fetchPredictOperation", {"operationName": op})
        if r.get("done"):
            break
        if time.time() - t0 > 900:
            sys.exit("超时：" + op)
    if "error" in r:
        sys.exit("失败：" + json.dumps(r["error"], ensure_ascii=False)[:600])
    vids = (r.get("response") or {}).get("videos") or []
    if not vids:
        sys.exit("没有视频（可能被安全过滤）：" + json.dumps(r.get("response", {}), ensure_ascii=False)[:600])
    d = OUT / a.tag
    d.mkdir(parents=True, exist_ok=True)
    files = []
    for i, v in enumerate(vids):
        f = d / ("veo_%d_%d.mp4" % (int(time.time()), i))
        f.write_bytes(base64.b64decode(v["bytesBase64Encoded"]))
        files.append(str(f))
        print("video", f.relative_to(OUT.parents[1]))
    (d / "log.json").write_text(json.dumps({"model": a.model, "seconds": a.seconds, "resolution": a.resolution,
                                            "image": a.image, "last": a.last, "prompt": a.prompt, "files": files,
                                            "elapsed_s": round(time.time() - t0)}, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
