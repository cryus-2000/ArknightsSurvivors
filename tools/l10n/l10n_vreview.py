"""英文版截图预审（docs/276 §12）：Vertex Gemini 逐张看英文界面截图，查溢出 / 截断 / 残留中文 / 裸 key / 文字重叠。
  python tools/l10n/l10n_vreview.py <目录或 PNG…> [--model gemini-3-flash-preview] [--only en_]
结果写 build/l10n_work/vreview_<目录名>.json，并打印每张的问题清单与高严重度合计。退出码 0 = 无高严重度问题。
鉴权同 translate_vertex.py（gcloud 令牌，不用 key）。只看文件名以 --only 前缀开头的图（缺省 en_）。
"""
import argparse, base64, json, os, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import translate_vertex as T  # noqa: E402

ROOT = T.ROOT
PROMPT = """You are QA-reviewing a screenshot of the ENGLISH version of a game UI (1280x720 desktop or a phone-ratio layout).
The game was translated from Chinese. Report only VISIBLE problems of these kinds:
- "chinese": Chinese characters still visible in game UI text (ignore character art, logos and the language selector cell that says 中文).
- "overflow": text running outside its box, button, card or panel, or past the screen edge.
- "overlap": two pieces of text drawn on top of each other, or text covering another UI element so it is hard to read.
- "truncated": text cut off mid-word, or ending with an ellipsis where important information is lost (a short ellipsis on a long description inside a fixed box is low severity).
- "raw_key": an internal key or placeholder shown to the player, e.g. op.mizuki.skills.1.desc, {$s1_mult}, %d, short:..., NaN.
- "broken": garbled text, tofu boxes, mixed-up words.
Severity: high = a player cannot read or understand it; medium = clearly ugly or partly hidden; low = minor.
Do not report decorative uppercase English labels, the art style, or translation word choice.
Return JSON: {"issues": [{"kind": ..., "severity": "high|medium|low", "where": "short location on screen", "text": "the visible text involved", "fix": "short suggestion"}]}. Empty list if clean."""


def review(png, model):
    data = base64.b64encode(open(png, "rb").read()).decode()
    url = T.VERTEX.format(p=T._gcloud("config", "get-value", "project"), m=model)
    body = {"contents": [{"role": "user", "parts": [{"inline_data": {"mime_type": "image/png", "data": data}}, {"text": PROMPT}]}],
            "generationConfig": {"responseMimeType": "application/json", "temperature": 0.1}}
    import urllib.request, time
    delay = 4.0
    for k in range(6):
        req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + T._token()})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                res = json.load(r)
            txt = "".join(p.get("text", "") for c in res.get("candidates", []) for p in c.get("content", {}).get("parts", []) if not p.get("thought"))
            out = json.loads(txt)
            return out.get("issues", []) if isinstance(out, dict) else out, res.get("usageMetadata", {})
        except Exception as e:  # 429 / 5xx / 解析失败：退避重试
            if getattr(e, "code", None) == 401:
                T._tok["t"] = None
            time.sleep(delay); delay *= 2
    return [{"kind": "error", "severity": "low", "where": "-", "text": "review failed", "fix": ""}], {}


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--model", default="gemini-3-flash-preview")
    ap.add_argument("--only", default="en_")
    a = ap.parse_args()
    files = []
    for p in a.paths:
        if os.path.isdir(p):
            files += sorted(str(x) for x in Path(p).glob("*.png") if x.name.startswith(a.only))
        else:
            files.append(p)
    allres = {}
    high = 0
    tok_in = tok_out = 0
    for f in files:
        issues, um = review(f, a.model)
        tok_in += um.get("promptTokenCount", 0); tok_out += um.get("candidatesTokenCount", 0) + um.get("thoughtsTokenCount", 0)
        allres[os.path.basename(f)] = issues
        hi = [i for i in issues if i.get("severity") == "high"]
        high += len(hi)
        print("%-40s %d 条（高 %d）" % (os.path.basename(f), len(issues), len(hi)))
        for i in issues:
            print("    [%s/%s] %s：%s → %s" % (i.get("severity"), i.get("kind"), i.get("where"), str(i.get("text"))[:70], i.get("fix", "")))
    name = Path(a.paths[0]).name if os.path.isdir(a.paths[0]) else "files"
    out = ROOT / "build/l10n_work" / ("vreview_%s.json" % name)
    out.parent.mkdir(parents=True, exist_ok=True)
    json.dump(allres, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("共 %d 张，高严重度 %d 条；token 入 %d 出 %d（约 $%.3f，按 flash 档 0.5 / 3 美元每百万估）→ %s" % (
        len(files), high, tok_in, tok_out, tok_in / 1e6 * 0.5 + tok_out / 1e6 * 3.0, out))
    sys.exit(1 if high else 0)


if __name__ == "__main__":
    main()
