# -*- coding: utf-8 -*-
"""Veo 图生视频（Vertex AI，按 Cloud 项目计费；令牌每次调 gcloud 现取，同 pixgen.py）。
  python tools/imagegen/veo.py <首帧.png> <输出.mp4> --prompt "<动作描述>" [--model veo-3.0-fast-generate-001] [--secs 8]
产物不进 git。"""
import argparse, base64, json, sys, time, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import pixgen

URL = "https://us-central1-aiplatform.googleapis.com/v1/projects/{p}/locations/us-central1/publishers/google/models/{m}:{op}"


def _post(url, body):
    tok = pixgen._gcloud("auth", "print-access-token")
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=120))
    except urllib.error.HTTPError as e:
        sys.exit("HTTP %d %s" % (e.code, e.read().decode()[:600]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image"); ap.add_argument("out")
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--model", default="veo-3.1-fast-generate-001")
    ap.add_argument("--secs", type=int, default=8)
    ap.add_argument("--neg", default="text, watermark, blurry, smooth 3d render, photorealistic")
    a = ap.parse_args()
    proj = pixgen._gcloud("config", "get-value", "project")
    img = base64.b64encode(Path(a.image).read_bytes()).decode()
    body = {"instances": [{"prompt": a.prompt, "image": {"bytesBase64Encoded": img, "mimeType": "image/png"}}],
            "parameters": {"aspectRatio": "16:9", "durationSeconds": a.secs, "sampleCount": 1, "negativePrompt": a.neg,
                           "resolution": "1080p", "generateAudio": False, "personGeneration": "dont_allow"}}
    r = _post(URL.format(p=proj, m=a.model, op="predictLongRunning"), body)
    name = r["name"]
    print("operation", name.split("/")[-1], flush=True)
    t0 = time.time()
    while True:
        time.sleep(10)
        st = _post(URL.format(p=proj, m=a.model, op="fetchPredictOperation"), {"operationName": name})
        if st.get("done"):
            break
        if time.time() - t0 > 900:
            sys.exit("超时")
    if "error" in st:
        sys.exit("失败 " + json.dumps(st["error"])[:600])
    vids = st["response"].get("videos") or []
    if not vids:
        sys.exit("没有视频（可能被安全过滤）：" + json.dumps(st["response"])[:600])
    Path(a.out).write_bytes(base64.b64decode(vids[0]["bytesBase64Encoded"]))
    print("ok", a.out, "%.0fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
