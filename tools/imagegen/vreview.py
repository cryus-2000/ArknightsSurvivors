"""视觉预审：把对照录像 / 截图交给 Gemini 多模态模型按检查单过一遍，发给用户之前先滤掉明显毛病（技能 .claude/skills/vreview）。

  python tools/imagegen/vreview.py ult_fx  build/ult_rec/x/u_kaltsit.mp4 --note "凯尔希：代表色青绿 #59F2D9"
  python tools/imagegen/vreview.py card_ui shot_choice_1.png shot_choice_2.png
  python tools/imagegen/vreview.py ult_fx  对照.mp4 --crop right      # 左旧右新的对照片只审右半

- 检查单在同目录 vreview_lists.json（ult_fx / card_ui / record_sprite …），加单子只改数据文件。
- 后端同 pixgen：Vertex（gcloud 现取令牌、gcloud 当前项目计费），令牌不打印不写盘。缺省 gemini-3-flash-preview（Flash 档），
  --model gemini-3.1-flash-lite 更便宜。视频先用 ffmpeg 缩到 960 宽、去声音，按 --fps 抽帧给模型（缺省 5，特效帧跳要看细就加到 10）。
- 本地量化探针（不靠模型）：视频逐秒近白像素占比（亮度封顶口径），结果一并给模型和打印。
- 输出：每条问题的文件 / 时间点 / 位置、检查项、严重度、一句改法，最后结论「可以发用户 / 先改」；JSON 存 build/vreview/。
  退出码 0 = 可以发，1 = 先改，2 = 调用失败。每次调用打印 token 数和估算花费。预审只是过滤，最终仍由用户看。
"""
import argparse, base64, json, os, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "vreview"
LISTS = Path(__file__).with_name("vreview_lists.json")
VERTEX = "https://aiplatform.googleapis.com/v1/projects/{p}/locations/global/publishers/google/models/{m}:generateContent"
MODEL = os.environ.get("VREVIEW_MODEL", "gemini-3-flash-preview")
THINK = os.environ.get("VREVIEW_THINK", "low")
VOTES = int(os.environ.get("VREVIEW_VOTES", "3"))   # 思考档 minimal / low / medium / high：思考 token 按输出价计，是花费大头
# 美元 / 百万 token（输入 文本·图·视频同价；输出含思考）。估算用，以 Cloud 账单为准
PRICE = {"gemini-3-flash-preview": (0.50, 3.00), "gemini-3.1-flash-lite": (0.25, 1.50)}

SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "issues": {"type": "ARRAY", "items": {"type": "OBJECT", "properties": {
            "file": {"type": "INTEGER", "description": "1-based file number"},
            "time": {"type": "STRING", "description": "video timestamp m:ss.s or range, empty for images"},
            "where": {"type": "STRING", "description": "screen position, e.g. 'center', 'left card', 'around the operator'"},
            "item": {"type": "STRING", "description": "checklist item id"},
            "severity": {"type": "STRING", "enum": ["high", "mid", "low"]},
            "desc": {"type": "STRING", "description": "what is wrong, one sentence, Simplified Chinese"},
            "fix": {"type": "STRING", "description": "how to fix, one sentence, Simplified Chinese"},
            "confidence": {"type": "NUMBER", "description": "0-1"}},
            "required": ["file", "item", "severity", "desc", "fix", "confidence"]}},
        "verdict": {"type": "STRING", "enum": ["pass", "fix"]},
        "summary": {"type": "STRING", "description": "one or two sentences, Simplified Chinese"}},
    "required": ["issues", "verdict", "summary"]}


def _gcloud(*args):
    g = shutil.which("gcloud") or shutil.which("gcloud.cmd")
    if not g:
        cand = Path(os.environ.get("LOCALAPPDATA", "")) / "Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd"
        g = str(cand) if cand.exists() else None
    if not g:
        sys.exit("找不到 gcloud；装 Google Cloud CLI 并 gcloud auth login")
    r = subprocess.run([g, *args], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit("gcloud " + args[0] + " 失败：" + r.stderr.strip()[:300])
    return r.stdout.strip()


def _ff():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return shutil.which("ffmpeg") or sys.exit("找不到 ffmpeg（pip install imageio-ffmpeg）")


CROPS = {"left": "iw/2:ih:0:0", "right": "iw/2:ih:iw/2:0", "": None}


def _prep_video(path, crop, tmp):
    """缩到 960 宽、30 帧、去声音、crf 30：一般 1–3 MB，直接内联"""
    vf = ([f"crop={CROPS.get(crop, crop)}"] if crop else []) + ["scale='min(960,iw)':-2", "fps=30"]
    out = Path(tmp) / (Path(path).stem + "_vr.mp4")
    r = subprocess.run([_ff(), "-y", "-loglevel", "error", "-i", str(path), "-vf", ",".join(vf), "-an",
                        "-c:v", "libx264", "-crf", "30", "-pix_fmt", "yuv420p", str(out)], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("ffmpeg 失败：" + r.stderr[:300])
    return out


def _prep_image(path, crop, tmp):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    if crop in ("left", "right"):
        im = im.crop((0, 0, im.width // 2, im.height)) if crop == "left" else im.crop((im.width // 2, 0, im.width, im.height))
    if max(im.size) > 2048:
        k = 2048 / max(im.size)
        im = im.resize((int(im.width * k), int(im.height * k)))
    out = Path(tmp) / (Path(path).stem + "_vr.png")
    im.save(out)
    return out


def white_probe(video, fps=5):
    """逐帧近白像素占比（三通道都 ≥ 0.9 × 255），按秒取最大；返回 [(秒, 占比)]"""
    import numpy as np
    w, h = 320, 180
    r = subprocess.run([_ff(), "-loglevel", "error", "-i", str(video), "-vf", f"fps={fps},scale={w}:{h}", "-f", "rawvideo",
                        "-pix_fmt", "rgb24", "-"], capture_output=True)
    a = np.frombuffer(r.stdout, np.uint8)
    n = len(a) // (w * h * 3)
    if n == 0:
        return []
    a = a[:n * w * h * 3].reshape(n, h, w, 3)
    frac = (a.min(-1) >= 230).reshape(n, -1).mean(1)
    per = {}
    for i, f in enumerate(frac):
        s = i // fps
        per[s] = max(per.get(s, 0.0), float(f))
    return sorted(per.items())


def build_prompt(lst, note, files, probes):
    items = "\n".join(f"- {it['id']} ({it['name']}, default severity {it['sev']}): {it['rule']}" for it in lst["items"])
    fl = "\n".join(f"File #{i + 1}: {Path(f).name}" for i, f in enumerate(files))
    pr = ""
    if probes:
        pr = "\nMeasured locally (trust these numbers): share of near-white pixels per second, per video:\n" + "\n".join(
            f"File #{i}: " + ", ".join(f"{s}s {v:.0%}" for s, v in p if v >= 0.02) for i, p in probes.items())
    return f"""You are a strict visual QA reviewer for a game studio. Review the attached media against the checklist BEFORE it is shown to the producer.
Context: {lst['context']}
{('Note from the artist: ' + note) if note else ''}
Files (in the order attached):
{fl}
{pr}
Checklist (only report problems that match one of these items; use the item id):
{items}

Rules:
- Report only problems you can actually see. For each, give the file number, the video timestamp (m:ss.s, or a range) or empty for images, where on screen, the item id, severity (high / mid / low), what is wrong and a one-sentence fix, both in Simplified Chinese, and your confidence 0-1.
- Do not report things outside the checklist, do not praise, do not report the same problem twice.
- verdict = "fix" if there is any high-severity issue with confidence >= 0.6, otherwise "pass".
- summary: one or two sentences in Simplified Chinese."""


def call(model, parts, tries=5, think=THINK):
    url = VERTEX.format(p=_gcloud("config", "get-value", "project"), m=model)
    body = {"contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseMimeType": "application/json", "responseSchema": SCHEMA, "temperature": 0.2,
                                 **({"thinkingConfig": {"thinkingLevel": think}} if think else {})}}
    data = json.dumps(body).encode()
    for k in range(tries):
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json",
                                                              "Authorization": "Bearer " + _gcloud("auth", "print-access-token")})
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:400]
            if e.code in (429, 500, 502, 503, 504) and k < tries - 1:
                print(f"HTTP {e.code}，{30 * (k + 1)} 秒后重试", file=sys.stderr)
                time.sleep(30 * (k + 1))
                continue
            print(f"HTTP {e.code}: {msg}", file=sys.stderr)
            sys.exit(2)


def cost(model, usage):
    pin, pout = PRICE.get(model, (0.5, 3.0))
    tin = usage.get("promptTokenCount", 0)
    tout = usage.get("candidatesTokenCount", 0) + usage.get("thoughtsTokenCount", 0)
    return tin, tout, (tin * pin + tout * pout) / 1e6


def _vote(runs):
    """多次独立审阅取多数：某检查项（同文件）在过半次数里被报成会挡发的问题（high 且把握 ≥ 0.6）才算 high，其余降成 mid；
    每项只留把握最高的那条描述。结论按表决后的问题重算"""
    need = len(runs) // 2 + 1
    seen, best = {}, {}
    for r in runs:
        ks = set()
        for it in r.get("issues", []):
            k = (it.get("file", 1), it["item"])
            if it["severity"] == "high" and it.get("confidence", 0) >= 0.6:
                ks.add(k)
            if k not in best or it.get("confidence", 0) > best[k].get("confidence", 0):
                best[k] = dict(it)
        for k in ks:
            seen[k] = seen.get(k, 0) + 1
    issues = []
    for k, it in best.items():
        n = seen.get(k, 0)
        if n >= need:
            it["severity"] = "high"
        elif it["severity"] == "high":
            it["severity"] = "mid"
        it["votes"] = f"{n}/{len(runs)}"
        issues.append(it)
    verdict = "fix" if any(i["severity"] == "high" for i in issues) else "pass"
    return {"issues": issues, "verdict": verdict, "summary": next((r["summary"] for r in runs if r.get("verdict") == verdict), runs[0].get("summary", ""))}


def review(list_name, files, note="", model=MODEL, fps=5, crop="", quiet=False, think=THINK, votes=1):
    lists = json.loads(LISTS.read_text(encoding="utf-8"))
    if list_name not in lists:
        sys.exit(f"没有检查单 {list_name}；现有：{', '.join(lists)}")
    lst = lists[list_name]
    parts, probes = [], {}
    with tempfile.TemporaryDirectory() as tmp:
        for i, f in enumerate(files):
            ext = Path(f).suffix.lower()
            parts.append({"text": f"File #{i + 1}: {Path(f).name}"})
            if ext in (".mp4", ".mov", ".webm"):
                v = _prep_video(f, crop, tmp)
                probes[i + 1] = white_probe(v)
                parts.append({"inlineData": {"mimeType": "video/mp4", "data": base64.b64encode(v.read_bytes()).decode()},
                              "videoMetadata": {"fps": fps}})
            else:
                im = _prep_image(f, crop, tmp)
                parts.append({"inlineData": {"mimeType": "image/png", "data": base64.b64encode(im.read_bytes()).decode()}})
        parts.append({"text": build_prompt(lst, note, files, probes)})
        runs, tin, tout, usd, usage = [], 0, 0, 0.0, []
        for _ in range(max(1, votes)):
            res = call(model, parts, think=think)
            txt = "".join(p.get("text", "") for c in res.get("candidates", []) for p in c.get("content", {}).get("parts", []))
            try:
                runs.append(json.loads(txt))
            except json.JSONDecodeError:
                sys.exit("模型没回 JSON：" + txt[:300])
            a, b, c = cost(model, res.get("usageMetadata", {}))
            tin, tout, usd = tin + a, tout + b, usd + c
            usage.append(res.get("usageMetadata", {}))
    out = runs[0] if len(runs) == 1 else _vote(runs)
    names = {it["id"]: it["name"] for it in lst["items"]}
    out.update({"list": list_name, "files": [str(f) for f in files], "model": model, "think": think, "fps": fps, "crop": crop, "note": note,
                "probe_white": {str(k): v for k, v in probes.items()}, "tokens_in": tin, "tokens_out": tout, "usd": round(usd, 4),
                "votes": len(runs), "usage": usage})
    if not quiet:
        print(f"【{lst['title']}】{len(files)} 个文件，模型 {model}")
        for k, p in probes.items():
            mx = max((v for _, v in p), default=0.0)
            print(f"  探针：文件 {k} 近白像素最高 {mx:.0%}" + ("（超过 12%，疑似发白）" if mx > 0.12 else ""))
        for it in sorted(out["issues"], key=lambda x: ("high", "mid", "low").index(x["severity"])):
            t = f" {it.get('time')}" if it.get("time") else ""
            print(f"  [{it['severity']}] 文件 {it['file']}{t} {it.get('where', '')}｜{names.get(it['item'], it['item'])}："
                  f"{it['desc']} → {it['fix']}（把握 {it.get('confidence', 0):.1f}" + (f"，{it['votes']} 次" if "votes" in it else "") + "）")
        print("  结论：" + ("可以发用户" if out["verdict"] == "pass" else "先改") + "。" + out.get("summary", ""))
        print(f"  花费：{out['votes']} 次调用，输入 {tin} + 输出 {tout} token，约 {usd:.4f} 美元（估算）")
    return out


def main():
    for st in (sys.stdout, sys.stderr):
        try:
            st.reconfigure(encoding="utf-8")
        except AttributeError:
            pass
    ap = argparse.ArgumentParser()
    ap.add_argument("list", help="检查单名（vreview_lists.json）")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--note", default="", help="给审阅的说明：干员、代表色、这版改了什么")
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--think", default=THINK, help="思考档 minimal / low / medium / high（缺省 low；空串 = 模型自定，贵且慢）")
    ap.add_argument("--votes", type=int, default=VOTES, help="独立审几次取多数（缺省 3；主观项每次结果会变，表决后稳）")
    ap.add_argument("--fps", type=float, default=5, help="视频给模型的抽帧率（缺省 5）")
    ap.add_argument("--crop", default="", help="left / right（对照片只审一半）或 ffmpeg crop 表达式 w:h:x:y")
    ap.add_argument("--json", default="", help="结果另存路径（缺省 build/vreview/<首个文件名>_<检查单>.json）")
    a = ap.parse_args()
    out = review(a.list, a.files, a.note, a.model, a.fps, a.crop, think=a.think, votes=a.votes)
    OUT.mkdir(parents=True, exist_ok=True)
    jp = Path(a.json) if a.json else OUT / f"{Path(a.files[0]).stem}_{a.list}{'_' + a.crop if a.crop in ('left', 'right') else ''}.json"
    jp.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print("  结果：" + str(jp))
    sys.exit(0 if out["verdict"] == "pass" else 1)


if __name__ == "__main__":
    main()
