"""干员 1 倍帧条（10-23 用户定「1 倍，整套替换」，docs/128）：给每条干员帧条出 art/incoming/<tex>@1x.png，
引擎在 render/op_1x 开着时优先用它（art.gd op_1x_on），1 美术像素 = 1 贴图像素，与怪物同密度。

两种来源：
  ① 原作 Spine 逐部件 1 倍像素化（tools/spine_run_trial/run_trial.js，scaleMul）：待机 idle、跑步 run、普攻 attack，
     外加新槽 move_attack（攻击上半身 + 跑步步态腿，用户 10-23「边跑边攻击」）。帧数、脚底与原 @2x 帧条相同；
     缩放按原待机首帧身高对齐（各人原画布尺度不同）；普攻按原生 OnAttack 时刻对齐 fire 帧。
     斯卡蒂普攻换成自制「侧向劈砍」（cfg/skadi_sideslash_power.json，用户 10-23 逐版定：从拖剑位起手、剑不过肩不挡脸、加力量感）。
  ② 其余帧条（技能 / 入场 / 死亡 / 召唤物 …）：@2x 逐帧 2×2 合并（按 alpha 加权取色、覆盖过半才留）+ 本条调色板。

用法：python -X utf8 tools/op_1x/make_op_1x.py [--only mizuki,skadi] [--jobs 6] [--dry]
输出：art/incoming/<tex>@1x.png；中间帧与对照在 build/op_1x/（主仓库 build，不进 git）。
需要：主仓库 build/prts_ref（Spine 原始资源 + node 依赖，tools/prts_spine.py 下载）、build/lg_src（拉普兰德 / 歌蕾蒂娅调色板）。
"""
import argparse, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _GR
COMMON = _GR.common_root()
INC = os.path.join(ROOT, "art", "incoming")
CHARS = os.path.join(ROOT, "game", "data", "characters")
RT = os.path.join(ROOT, "tools", "spine_run_trial")
CFG = os.path.join(RT, "cfg")
REF = os.path.join(COMMON, "build", "prts_ref")
OUT = os.path.join(COMMON, "build", "op_1x")
NODE_PATH = os.path.join(REF, "_node", "node_modules")

# 普攻用的原生动画（没有列出的干员：Attack；None = 不用 Spine，走 ②）
ATTACK_ANIM = {"logos": "Attack_1", "wisadel": "Attack_A", "texas": "Attack_Loop", "skalter": None}
# 斯卡蒂普攻：自制关键帧（帧数 9，出手第 5 帧）
SKADI_ATTACK_CFG = "skadi_sideslash_power.json"


def info(op):
    return json.load(open(os.path.join(REF, op, op + "_info.json"), encoding="utf-8"))["anims"]


def walk_tex(v, acc):
    if isinstance(v, dict):
        if isinstance(v.get("tex"), str):
            acc.add(v["tex"])
        for x in v.values():
            walk_tex(x, acc)
    elif isinstance(v, list):
        for x in v:
            walk_tex(x, acc)
    elif isinstance(v, str) and os.path.exists(os.path.join(INC, v + "@2x.png")):
        acc.add(v)


def spec(sprites, kind):
    v = sprites.get(kind)
    if v is None:
        return None
    return {"tex": v} if isinstance(v, str) else v


# ---------------------------------------------------------------- ② 通用 2×2 合并
def downsample(img2, frames):
    W, H = img2.size
    fw2 = W // frames
    fw, fh = (fw2 + 1) // 2, (H + 1) // 2
    src = np.asarray(img2.convert("RGBA")).astype(np.float64)
    out = np.zeros((fh, fw * frames, 4), np.uint8)
    for f in range(frames):
        cell = np.zeros((fh * 2, fw * 2, 4))
        cell[:H, :fw2] = src[:, f * fw2:(f + 1) * fw2]
        blk = cell.reshape(fh, 2, fw, 2, 4)
        a = blk[..., 3]
        asum = a.sum(axis=(1, 3))
        rgb = (blk[..., :3] * a[..., None]).sum(axis=(1, 3)) / np.maximum(asum, 1)[..., None]
        keep = (a >= 128).sum(axis=(1, 3)) >= 2
        o = np.zeros((fh, fw, 4), np.uint8)
        o[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
        o[..., 3] = np.where(keep, 255, 0)
        out[:, f * fw:(f + 1) * fw] = o
    res = Image.fromarray(out, "RGBA")
    # 调色板：本条 @2x 不透明像素量化到 32 色，合并后的颜色映射回去（去掉 2×2 平均出来的中间色）
    opaque = Image.new("RGB", img2.size)
    opaque.paste(img2.convert("RGB"), mask=img2.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    pal = opaque.quantize(32, method=Image.Quantize.MEDIANCUT)
    alpha = res.getchannel("A")
    q = res.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGBA")
    q.putalpha(alpha)
    return q


# ---------------------------------------------------------------- ① Spine 渲染
def run_node(cfg_path, out_dir):
    env = dict(os.environ, NODE_PATH=NODE_PATH)
    r = subprocess.run(["node", os.path.join(RT, "run_trial.js"), cfg_path, "--out", out_dir], cwd=COMMON, env=env,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise RuntimeError(f"run_trial 失败 {cfg_path}: {r.stdout[-300:]} {r.stderr[-300:]}")


def write_cfg(op, name, cfg):
    d = os.path.join(OUT, op, "_cfg")
    os.makedirs(d, exist_ok=True)
    # run_trial 按 cfg 所在目录找 src：把 src 文件一起放过去
    src = cfg.get("src")
    if src and not os.path.exists(os.path.join(d, src)):
        open(os.path.join(d, src), "wb").write(open(os.path.join(CFG, src), "rb").read())
    p = os.path.join(d, name + ".json")
    json.dump(cfg, open(p, "w", encoding="utf-8"), ensure_ascii=False)
    return p


def anchor_of(cfg):
    size = cfg.get("canvas", 128)
    return size / 2, 120 + (size - 128) / 2


def compose(frames_dir, n, fw, fh, foot, anc, mirror=False):
    """渲染帧（锚点 anc = 脚底中心）贴进 fw×fh 帧格，锚点对到 json 的 foot"""
    # Preserve original scale and foot; extend right/bottom only if native
    # attachments would be clipped. Same contract as the approved art package.
    for i in range(n):
        probe = Image.open(os.path.join(frames_dir, f"f{i:02d}.png")).convert("RGBA")
        ax = anc[0]
        if mirror:
            probe = probe.transpose(Image.FLIP_LEFT_RIGHT)
            ax = probe.width - ax
        box = probe.getbbox()
        if box:
            dx, dy = round(foot[0] - ax), round(foot[1] - anc[1])
            if box[0] + dx < 0 or box[1] + dy < 0:
                raise ValueError("Native frame needs left/top padding and an explicit foot update")
            if box[2] + dx > fw:
                fw = box[2] + dx + 1
            if box[3] + dy > fh:
                fh = box[3] + dy + 1
    out = Image.new("RGBA", (fw * n, fh), (0, 0, 0, 0))
    for i in range(n):
        f = Image.open(os.path.join(frames_dir, f"f{i:02d}.png")).convert("RGBA")
        ax = anc[0]
        if mirror:
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
            ax = f.width - anc[0]
        cell = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        cell.paste(f, (int(round(foot[0] - ax)), int(round(foot[1] - anc[1]))), f)
        out.paste(cell, (i * fw, 0))
    return out


def skalter_fallback_eyes(img, kind):
    """Retain legacy hover motion; recolor its authored iris cells only.

    These coordinates describe the existing 64px, eight-frame hover sources,
    not a face detector. Occluded / closed eyes remain untouched.
    """
    if img.size != (512, 64):
        raise ValueError("Skalter hover source changed; review iris registration")
    out = img.copy()
    ys = [32, 31, 31, 31, 32, 33, 33, 33] if kind == "run" else [34, 34, 34, 34, 34, 35, 35, 35]
    xs = (32, 36) if kind == "run" else (31, 35)
    for i, y in enumerate(ys):
        for x in xs:
            px = i * 64 + x
            r, g, b, a = out.getpixel((px, y))
            if a and r > 80 and r > g * 1.6 and r > b * 1.2:
                out.putpixel((px, y), (203, 53, 70, a))
                r, g, b, a = out.getpixel((px, y - 1))
                if a and r > 80 and r > g * 1.6 and r > b * 1.2:
                    out.putpixel((px, y - 1), (128, 29, 44, a))
    return out


def sample_attack(anims, anim, n, fire):
    d = anims[anim]["dur"]
    ev = [e["t"] for e in anims[anim].get("events", []) if e["name"] == "OnAttack"]
    te = ev[0] if ev else d * 0.4
    if fire is None or fire <= 0 or fire >= n:
        return [round(i * d / n, 6) for i in range(n)]
    return [round(te * i / fire, 6) if i < fire else round(te + (d - te) * (i - fire) / (n - fire), 6) for i in range(n)]


def bbox_h(img):
    b = img.getbbox()
    return (b[3] - b[1]) if b else 0


def build_op(op, dry=False):
    with open(os.path.join(CHARS, op + ".json"), encoding="utf-8") as source:
        jd = json.load(source)
    sprites = jd.get("sprites", {})
    texs = set()
    walk_tex(sprites, texs)
    # 特效帧条（fx_*，如维什戴尔魂火）不是小人，保持 @2x（10-23 协调人核包时发现误转）
    texs = sorted(t for t in texs if os.path.exists(os.path.join(INC, t + "@2x.png")) and not t.startswith("fx_"))
    done, done2x, log = {}, {}, []
    base_cfg_p = os.path.join(CFG, op + ".json")
    anims = info(op) if os.path.exists(os.path.join(REF, op, op + "_info.json")) else {}
    spine_ok = os.path.exists(base_cfg_p) and bool(anims)
    if spine_ok:
        with open(base_cfg_p, encoding="utf-8") as source:
            base = json.load(source)
        base["noMouth"] = True
        base["pixelEyes"] = op in {"wisadel", "specter_unchained", "skalter"}
        base.pop("keys", None); base.pop("poses", None); base.pop("sample", None)
        base["canvas"] = max(192, base.get("canvas", 128))
        sm0 = base.get("scaleMul") or 1
        # 缩放：原待机首帧身高（1x）÷ Spine 1 倍待机身高
        idle = spec(sprites, "idle")
        k = 1.0
        if idle and os.path.exists(os.path.join(INC, idle["tex"] + "@2x.png")):
            im = Image.open(os.path.join(INC, idle["tex"] + "@2x.png")).convert("RGBA")
            nfr = int(idle.get("frames", max(1, im.width // im.height)))
            h_old = bbox_h(im.crop((0, 0, im.width // nfr, im.height))) / 2
            mcfg = dict(base, scaleMul=sm0 * 0.5)
            mdir = os.path.join(OUT, op, "_measure")
            run_node(write_cfg(op, "_measure", mcfg), mdir)
            h_new = bbox_h(Image.open(os.path.join(mdir, "idle_t0.png")))
            k = h_old / h_new if h_new else 1.0
        scale = sm0 * 0.5 * k
        log.append(f"scale k={k:.3f}")

        def slot_job(kind, mode, times=None, keyed=None, mirror=False, frames=None, dens=1):
            sp = spec(sprites, kind)
            if sp is None:
                return None
            im2 = Image.open(os.path.join(INC, sp["tex"] + "@2x.png"))
            n = frames or int(sp.get("frames", max(1, im2.width // im2.height)))
            fw, fh = (im2.width // int(sp.get("frames", max(1, im2.width // im2.height))) + 1) // 2, (im2.height + 1) // 2
            im2.close()
            foot = sp.get("foot", sprites.get("foot", [24, 46]))
            fw, fh, foot = fw * dens, fh * dens, [foot[0] * dens, foot[1] * dens]   # dens 2 = 同时出 @2x（斯卡蒂新普攻，render/op_1x 关时用）
            if keyed:
                c = json.load(open(os.path.join(CFG, keyed), encoding="utf-8"))
                c["scaleMul"] = scale * dens
                c["noMouth"] = dens == 1
                c["pixelEyes"] = dens == 1 and op in {"wisadel", "specter_unchained", "skalter"}
                if mode == "move":
                    c["runLegs"] = True
            else:
                c = dict(base, scaleMul=scale)
                if mode == "move":
                    c["mode"] = "move_attack"
                if times is not None:
                    c["sample"] = {"anim": times[0], "times": times[1]}
            name = f"{kind}_{mode}" + ("_2x" if dens == 2 else "")
            d = os.path.join(OUT, op, name)
            run_node(write_cfg(op, name, c), d)
            return compose(d, n, fw, fh, foot, anchor_of(c), mirror=bool(sp.get("mirror")))

        # 跑步
        run = spec(sprites, "run")
        if run and int(run.get("frames", 8)) == 8 and base.get("mode") != "float":
            done[run["tex"]] = ("run", lambda: slot_job("run", "run"))
        # 待机
        if idle and "Idle" in anims:
            n = int(idle.get("frames", 8))
            ic = os.path.join(CFG, op + "_idle.json")
            times = None
            if os.path.exists(ic):
                t = json.load(open(ic, encoding="utf-8")).get("sample", {}).get("times")
                if t and len(t) == n:
                    times = t
            if times is None:
                times = [round(i * anims["Idle"]["dur"] / n, 6) for i in range(n)]
            done[idle["tex"]] = ("idle", lambda times=times: slot_job("idle", "stand", ("Idle", times)))
        # 普攻 + 移动攻击
        att = spec(sprites, "attack")
        aa = ATTACK_ANIM.get(op, "Attack")
        V2 = "op_skadi_attack_v2"   # 新普攻帧条名（json 已改指过来；重复跑不再叠后缀）
        if att and op == "skadi":
            done[V2] = ("attack", lambda: slot_job("attack", "stand", keyed=SKADI_ATTACK_CFG, frames=9))
            done[f"op_{op}_move_attack"] = ("move_attack", lambda: slot_job("attack", "move", keyed=SKADI_ATTACK_CFG, frames=9))
            done2x[V2] = lambda: slot_job("attack", "stand", keyed=SKADI_ATTACK_CFG, frames=9, dens=2)
        elif att and aa and aa in anims:
            n = int(att.get("frames", 8))
            times = sample_attack(anims, aa, n, att.get("fire"))
            done[att["tex"]] = ("attack", lambda times=times: slot_job("attack", "stand", (aa, times)))
            done[f"op_{op}_move_attack"] = ("move_attack", lambda times=times: slot_job("attack", "move", (aa, times)))

    results = {}
    if not dry:
        for tex, (kind, fn) in done.items():
            try:
                img = fn()
                if img is not None:
                    results[tex] = img
                    log.append(f"spine {kind} -> {tex}")
            except Exception as e:
                raise RuntimeError(f"{op} {kind} native export failed; existing assets preserved") from e
        for tex in texs:
            if tex in results:
                continue
            im2 = Image.open(os.path.join(INC, tex + "@2x.png")).convert("RGBA")
            fr = None
            for kind, v in sprites.items():
                s = spec(sprites, kind) if isinstance(v, (str, dict)) else None
                if s and s.get("tex") == tex and s.get("frames"):
                    fr = int(s["frames"]); break
            fr = fr or max(1, im2.width // im2.height)
            if im2.width % fr:
                fr = max(1, im2.width // im2.height)
            results[tex] = downsample(im2, fr)
            if op == "skalter" and tex in {"op_skalter_run", "op_skalter_attack"}:
                results[tex] = skalter_fallback_eyes(results[tex], "run" if tex.endswith("_run") else "attack")
        for tex, img in results.items():
            img.save(os.path.join(INC, tex + "@1x.png"))
        for tex, fn in done2x.items():
            fn().save(os.path.join(INC, tex + "@2x.png"))
            log.append(f"spine @2x -> {tex}")
    return op, log, sorted(results)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    ops = sorted(f[:-5] for f in os.listdir(CHARS) if f.endswith(".json"))
    if a.only:
        ops = [o for o in ops if o in a.only.split(",")]
    with ThreadPoolExecutor(a.jobs) as ex:
        for op, log, texs in ex.map(lambda o: build_op(o, a.dry), ops):
            print(op, len(texs), "条 |", "; ".join(log))


if __name__ == "__main__":
    main()
