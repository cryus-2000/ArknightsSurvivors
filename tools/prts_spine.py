# -*- coding: utf-8 -*-
"""PRTS 干员 Spine 参照帧（docs/36 §9.1，10-15 用户定；给 Codex 当干员美术参照，内部用，不进 git、不进包）。

从 PRTS 拉干员「默认皮肤 · 战斗正面」的 Spine 资源（3.8，或较早干员的 3.5.51；3.5 先经 prts_spine35.py 转 JSON）（.skel / .atlas / .png），本地渲染待机 / 攻击 / 技能参照帧。不开浏览器、不用 Godot。

    python tools/prts_spine.py mizuki                # 一名
    python tools/prts_spine.py --all                 # 18 名（OPS 表）
    python tools/prts_spine.py mizuki --flip         # 镜像（PRTS 的战斗正面朝右，和我们的帧条同向；朝向不对时用）
    python tools/prts_spine.py mizuki --size 1000 --refresh   # 重新下载

路径：PRTS 页面 `<中文名>/spine` 的原文（index.php?action=raw，一段 JSON）里的 prefix + skin.默认.战斗正面.file；
页面 HTML 对非浏览器请求返回 403，原文接口与 static.prts.wiki 可以直接取（带浏览器 UA，失败按 2 / 4 / 8 秒重试）。
输出 build/prts_ref/<id>/：idle_f00–f03（Idle 时长的 0 / 25 / 50 / 75%）、attack_f00–f02（出手前 / 出手 / 收招）、skill_f00–f02（有技能动画时，同三帧），
1000×1000 透明底，同一干员各帧同一缩放、脚底对齐；另出 <id>_sheet.png（带动画名与帧号的拼图）与 <id>_info.json（动画清单、时长、事件）。
原始资源放 build/prts_ref/_raw/<id>/；渲染器依赖（spine-ts 3.8 运行时、@napi-rs/canvas）首次自动装到 build/prts_ref/_node/。

出手帧取攻击动画里的 OnAttack 事件时刻（明日方舟的 Spine 都打这个事件），没有事件时取时长 40%；出手前 = 出手时刻的一半，收招 = 出手与结束的中点。
攻击 / 技能动画名不统一（Attack / Attack_Loop / Combat；Skill / Skill_Begin / Skill_2_Loop …）：按 PICK 的优先顺序取第一个存在的。
"""
import argparse, json, os, subprocess, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import prts_spine35
import godot_runner as _GR   # 只用 common_root：输出放主仓库的 build/（各工作树共用，不进 git）
OUT = os.path.join(_GR.common_root(), "build", "prts_ref")
RAW = os.path.join(OUT, "_raw")
NODE_DIR = os.path.join(OUT, "_node")
RUNTIME = os.path.join(NODE_DIR, "spine-canvas-3.8.js")
RUNTIME_URL = "https://raw.githubusercontent.com/EsotericSoftware/spine-runtimes/3.8/spine-ts/build/spine-canvas.js"
# Spine 3.5 用 3.5.51 标签版（3.5 分支头上已混入 3.6 格式）；3.5 运行时没有二进制读取器，先用 prts_spine35.py 转 JSON
RUNTIME35 = os.path.join(NODE_DIR, "spine-canvas-3.5.51.js")
RUNTIME35_URL = "https://raw.githubusercontent.com/EsotericSoftware/spine-runtimes/3.5.51/spine-ts/build/spine-canvas.js"
RENDER_JS = os.path.join(ROOT, "tools", "prts_spine_render.js")
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

# 干员 id → PRTS 中文页面名（docs/23 干员表；新干员加在这里）
OPS = {
    "mizuki": "水月", "siege": "推进之王", "skadi": "斯卡蒂", "saria": "塞雷娅", "wisadel": "维什戴尔", "eyjafjalla": "艾雅法拉",
    "kaltsit": "凯尔希", "suzuran": "铃兰", "ulpianus": "乌尔比安", "irene": "艾丽妮", "specter_unchained": "归溟幽灵鲨", "logos": "逻各斯",
    "lumen": "流明", "skalter": "浊心斯卡蒂", "texas": "德克萨斯", "hoshiguma": "星熊", "exusiai": "能天使", "angelina": "安洁莉娜",
}
PICK = {
    "idle": ["Idle"],
    "attack": ["Attack", "Attack_Loop", "Combat", "Attack_1"],
    "skill": ["Skill", "Skill_Loop", "Skill_1", "Skill_2", "Skill_2_Loop", "Skill_3", "Skill_3_Loop", "Skill_Begin", "Skill_2_Begin", "Skill_3_Begin"],
}


def fetch(url, dest=None, tries=4):
    last = None
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*", "Accept-Language": "zh-CN,zh;q=0.9"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            if dest:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest + ".part", "wb") as f:
                    f.write(data)
                os.replace(dest + ".part", dest)
            return data
        except Exception as e:   # 限速 / 断线：退避重试
            last = e
            time.sleep(2 * (2 ** k))
    raise RuntimeError("下载失败 %s：%s" % (url, last))


def ensure_renderer():
    os.makedirs(NODE_DIR, exist_ok=True)
    if not os.path.exists(RUNTIME):
        fetch(RUNTIME_URL, RUNTIME)
    if not os.path.exists(RUNTIME35):
        fetch(RUNTIME35_URL, RUNTIME35)
    if not os.path.isdir(os.path.join(NODE_DIR, "node_modules", "@napi-rs", "canvas")):
        if not os.path.exists(os.path.join(NODE_DIR, "package.json")):
            open(os.path.join(NODE_DIR, "package.json"), "w").write('{"name": "prts-spine-render", "private": true}\n')
        subprocess.run("npm install @napi-rs/canvas@0.1 --no-audit --no-fund", cwd=NODE_DIR, shell=True, check=True)


def spine_file(name):
    raw = fetch("https://prts.wiki/index.php?title=%s&action=raw" % urllib.parse.quote(name + "/spine")).decode("utf-8")
    d = json.loads(raw)
    return d["prefix"], d["skin"]["默认"]["战斗正面"]["file"]


def download(oid, name, refresh):
    d = os.path.join(RAW, oid)
    meta = os.path.join(d, "meta.json")
    if os.path.exists(meta) and not refresh:
        m = json.load(open(meta, encoding="utf-8"))
    else:
        prefix, f = spine_file(name)
        m = {"name": name, "prefix": prefix, "file": f}
    base = m["prefix"] + m["file"]
    stem = os.path.basename(m["file"])
    skel, atlas = os.path.join(d, stem + ".skel"), os.path.join(d, stem + ".atlas")
    for p, ext in [(skel, ".skel"), (atlas, ".atlas")]:
        if refresh or not os.path.exists(p):
            fetch(base + ext, p)
    # 页图：.atlas 里每一页的图名（单独一行、以 .png 结尾）
    pages = [l.strip() for l in open(atlas, encoding="utf-8") if l.strip().endswith(".png") and ":" not in l]
    for pg in pages:
        p = os.path.join(d, pg)
        if refresh or not os.path.exists(p):
            fetch(m["prefix"] + os.path.dirname(m["file"]) + "/" + pg, p)
    m["pages"] = pages
    json.dump(m, open(meta, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return skel, atlas


def run_render(job, runtime=RUNTIME):
    jp = os.path.join(OUT, "_job_%d.json" % os.getpid())
    json.dump(job, open(jp, "w", encoding="utf-8"), ensure_ascii=False)
    env = dict(os.environ, NODE_PATH=os.path.join(NODE_DIR, "node_modules"))
    r = subprocess.run(["node", RENDER_JS, runtime, jp], capture_output=True, text=True, encoding="utf-8", env=env)
    os.remove(jp)
    if r.returncode != 0:
        raise RuntimeError("渲染失败：" + (r.stderr or r.stdout)[-1500:])
    return json.loads(r.stdout.strip().splitlines()[-1])


def pick(anims, kind):
    for n in PICK[kind]:
        if n in anims:
            return n
    if kind == "skill":   # 兜底：任何带 Skill 的（不要 Begin / End 时优先 Loop）
        cand = sorted(a for a in anims if "skill" in a.lower())
        loops = [a for a in cand if "loop" in a.lower()]
        return (loops or cand or [None])[0]
    return None


def three(info):
    dur = float(info["dur"])
    ev = [e["t"] for e in info["events"] if "attack" in e["name"].lower()]
    hit = ev[0] if ev else dur * 0.4
    return [hit * 0.5, hit, (hit + dur) * 0.5]


def sheet(oid, frames, out_dir):
    from PIL import Image, ImageDraw
    rows = {}
    for f in frames:
        rows.setdefault(f["name"].split("_f")[0], []).append(f)
    th = 250
    cols = max(len(v) for v in rows.values())
    img = Image.new("RGBA", (cols * th, len(rows) * (th + 22)), (40, 42, 54, 255))
    dr = ImageDraw.Draw(img)
    for r, (kind, fs) in enumerate(rows.items()):
        for c, f in enumerate(fs):
            fr = Image.open(f["file"]).convert("RGBA").resize((th, th), Image.LANCZOS)
            img.alpha_composite(fr, (c * th, r * (th + 22) + 22))
            dr.text((c * th + 4, r * (th + 22) + 4), "%s  %s  t=%.2fs" % (f["name"], f["anim"], f["t"]), fill=(255, 230, 120, 255))
    p = os.path.join(out_dir, "%s_sheet.png" % oid)
    img.save(p)
    return p


def do_one(oid, a):
    name = OPS.get(oid, oid)
    skel, atlas = download(oid, name, a.refresh)
    out_dir = os.path.join(OUT, oid)
    base = {"skel": skel, "atlas": atlas, "out_dir": out_dir, "size": a.size, "flip": a.flip}
    runtime = RUNTIME
    raw = open(skel, "rb").read()
    if b"3.5." in raw[:64]:   # 头部版本串：3.5.x 走转换 + 3.5 运行时
        js = skel[:-5] + ".35.json"
        json.dump(prts_spine35.convert(raw), open(js, "w", encoding="utf-8"), ensure_ascii=False)
        base["json"], runtime = js, RUNTIME35
    probe = run_render(dict(base, frames=[]), runtime)
    anims = probe["anims"]
    frames = []
    ia = pick(anims, "idle")
    if ia:
        d = float(anims[ia]["dur"])
        frames += [{"name": "idle_f%02d" % k, "anim": ia, "t": d * k / 4.0} for k in range(4)]
    for kind in ["attack", "skill"]:
        an = pick(anims, kind)
        if an:
            frames += [{"name": "%s_f%02d" % (kind, k), "anim": an, "t": t} for k, t in enumerate(three(anims[an]))]
    res = run_render(dict(base, frames=frames), runtime)
    sp = sheet(oid, res["frames"], out_dir)
    json.dump({"id": oid, "name": name, "anims": anims, "frames": res["frames"], "scale": res["scale"]},
              open(os.path.join(out_dir, "%s_info.json" % oid), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    kinds = sorted({f["name"].split("_f")[0] for f in res["frames"]})
    return "%s（%s）：%d 帧 %s，拼图 %s" % (oid, name, len(res["frames"]), "/".join(kinds), sp)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--flip", action="store_true")
    ap.add_argument("--size", type=int, default=1000)
    ap.add_argument("--refresh", action="store_true")
    a = ap.parse_args()
    ids = list(OPS) if a.all else a.ids
    if not ids:
        ap.error("给干员 id 或 --all")
    ensure_renderer()
    fails = []
    for oid in ids:
        try:
            print(do_one(oid, a), flush=True)
        except Exception as e:
            fails.append((oid, str(e)[:300]))
            print("失败 %s：%s" % (oid, str(e)[:300]), flush=True)
        time.sleep(1.0)   # 对 PRTS 客气一点
    print("完成 %d / %d；失败 %s" % (len(ids) - len(fails), len(ids), [f[0] for f in fails]))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
