# -*- coding: utf-8 -*-
"""PRTS 干员 / 敌人 Spine 参照帧（docs/36 §9.1，10-15 用户定；给 Codex 当干员美术参照，内部用，不进 git、不进包）。

从 PRTS 拉干员「默认皮肤 · 战斗正面」的 Spine 资源（3.8，或较早干员的 3.5.51；3.5 先经 prts_spine35.py 转 JSON）（.skel / .atlas / .png），本地渲染待机 / 攻击 / 技能参照帧。不开浏览器、不用 Godot。

    python tools/prts_spine.py mizuki                # 一名
    python tools/prts_spine.py --all                 # 18 名（OPS 表）
    python tools/prts_spine.py mizuki --flip         # 镜像（PRTS 的战斗正面朝右，和我们的帧条同向；朝向不对时用）
    python tools/prts_spine.py mizuki --size 1000 --refresh   # 重新下载

路径：PRTS 页面 `<中文名>/spine` 的原文（index.php?action=raw，一段 JSON）里的 prefix + skin.默认.战斗正面.file；
页面 HTML 对非浏览器请求返回 403，原文接口与 static.prts.wiki 可以直接取（带浏览器 UA，失败按 2 / 4 / 8 秒重试）。
输出 build/prts_ref/<id>/：idle_f00–f03（Idle 时长的 0 / 25 / 50 / 75%）、move_f00–f03（有移动动画时）、death_f00–f02（Die 0 / 50 / 100%）、attack_f00–f02（出手前 / 出手 / 收招）、skill_f00–f02（有技能动画时，同三帧），
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
    "lappland": "拉普兰德", "gladiia": "歌蕾蒂娅",   # 第四批设计稿（docs/122 / 123，10-22）
    "dusk_drgn": "小自在",   # 夕的召唤物（character_table token_10015_dusk_drgn）
    "ling_soul1": "清平", "ling_soul2": "逍遥", "ling_soul3": "弦惊",   # 令的召唤物（character_table token_10020_ling_soul1–3）
    "ling": "令", "phantom": "傀影", "dusk": "夕", "shu": "黍", "surtr": "史尔特尔", "fiammetta": "菲亚梅塔",   # 11-18 新干员（B 方案直接进包）
    "typhon": "提丰", "sbell2": "圣聆初雪",   # 11-20 萨米新干员（先只收参照）
}
# 页面缺失 / 页面给的路径在静态站 404 的干员：直接按静态站标准路径 spine38/char/<角色 id>/<角色 id>/<角色 id> 取（10-15 逐个试出来的）
DIRECT = {"irene": "char_4009_irene", "specter_unchained": "char_1023_ghost2", "lumen": "char_4042_lumen"}
# PRTS 没有 <名>/spine 页面的新干员：素材在 PRTS 的另一个资源站 torappu（assets/char_spine/<角色 id>/defaultskin/front/<角色 id>，Spine 3.8；10-15 试出）
TORAPPU = {"wisadel": "char_1035_wisdel", "ulpianus": "char_4145_ulpia", "logos": "char_4133_logos",
           # 11-18：PRTS 页面原文接口对脚本 403，新干员一律走 torappu（令已验证；其余 5 人 id 按游戏数据，拉不到再改）
           "ling": "char_2023_ling", "phantom": "char_250_phatom", "dusk": "char_2015_dusk", "shu": "char_2025_shu",
           "surtr": "char_350_surtr", "fiammetta": "char_300_phenxi",
           "typhon": "char_2012_typhon", "sbell2": "char_1046_sbell2",
           "ling_soul1": "token_10020_ling_soul1", "ling_soul2": "token_10020_ling_soul2", "ling_soul3": "token_10020_ling_soul3",
           "dusk_drgn": "token_10015_dusk_drgn"}
# 敌人 / Boss（11-19 用户批准敌人也走 Spine 直转；萨米主题 docs/391）：torappu assets/enemy_spine/<敌人 id>/<敌人 id>.{skel,atlas,png}（试出，无皮肤目录）
ENEMY = {"sami_shell": "enemy_2043_smsbr", "sami_caster": "enemy_2044_smwiz", "sami_drone": "enemy_2045_smdrn", "sami_warrior": "enemy_2046_smwar",
         "sami_vinebox": "enemy_2059_smbox", "sami_tree": "enemy_2047_smtree", "sami_blade": "enemy_2048_smgrd", "sami_blade2": "enemy_2049_smgrd2",
         "sami_will": "enemy_2054_smdeer", "snslime_a": "enemy_1067_snslime_2", "snow_icebreaker": "enemy_1069_icebrk_2",
         # 11-20 萨米全量（docs/399 §6）：其余中期 / 结局 Boss、双王随从、自走车、Boss 关借用敌人
         "sami_shaman": "enemy_2050_smsha", "sami_shaman2": "enemy_2051_smsha2", "sami_vine": "enemy_2052_smgia", "sami_vine2": "enemy_2053_smgia2",
         "sami_lead": "enemy_2055_smlead", "sami_cresson": "enemy_2056_smedzi", "sami_khan": "enemy_2057_smkght", "sami_lion": "enemy_2058_smlion",
         "sami_shadow": "enemy_2060_smshdw", "sami_hound": "enemy_2061_smhond", "sami_car": "enemy_2062_smcar",
         "ursus_uterer": "enemy_1108_uterer", "ursus_uterer2": "enemy_1108_uterer_2", "frost_drone": "enemy_1042_frostd",
         "snow_sbr": "enemy_1064_snsbr", "snow_icechisel": "enemy_1069_icebrk",
         "mh_shep": "enemy_1303_mhshep", "snow_mage": "enemy_1068_snmage_2", "mh_rockback": "enemy_1307_mhrhcr_2", "ursus_amord": "enemy_1110_uamord_2"}
OPS.update({"sami_shell": "染污躯壳", "sami_caster": "歪曲施法者", "sami_drone": "坍缩构造体", "sami_warrior": "木裂战士", "sami_vinebox": "巨壳藤蔓",
            "sami_tree": "积雪银凇", "sami_blade": "“邪魔的利刃”", "sami_blade2": "“邪魔的利刃”，游荡者", "sami_will": "“萨米的意志”", "snslime_a": "冰爆源石虫·α", "snow_icebreaker": "雪怪小队破冰者",
            "sami_shaman": "陷落雪祀", "sami_shaman2": "空洞雪祀", "sami_vine": "纠缠藤蔓", "sami_vine2": "古老藤蔓", "sami_lead": "“木裂”埃克提尔尼尔",
            "sami_cresson": "无垠回荡克雷松", "sami_khan": "哈兰杜汗，大地之鞭", "sami_lion": "路加萨尔古斯，历法之王", "sami_shadow": "可汗片影",
            "sami_hound": "王者友伴", "sami_car": "勘察用自走车", "ursus_uterer": "乌萨斯裂兽", "ursus_uterer2": "乌萨斯裂兽族母", "frost_drone": "寒霜",
            "snow_sbr": "雪怪小队", "snow_icechisel": "雪怪小队凿冰人",
            "mh_shep": "角兽", "snow_mage": "雪怪术师组长", "mh_rockback": "坚岩冠兽", "ursus_amord": "乌萨斯高级着铠术师"})
PICK = {
    "idle": ["Idle"],
    "move": ["Move", "Move_Loop", "Run", "Run_Loop", "Walk"],
    "death": ["Die", "Dead", "Death"],
    "attack": ["Attack", "Attack_Loop", "Combat", "Attack_1", "Attack_A"],
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
    elif oid in ENEMY:
        c = ENEMY[oid]
        m = {"name": name, "prefix": "https://torappu.prts.wiki/assets/enemy_spine/", "file": "%s/%s" % (c, c)}
    elif oid in TORAPPU:
        c = TORAPPU[oid]
        m = {"name": name, "prefix": "https://torappu.prts.wiki/assets/char_spine/", "file": "%s/defaultskin/front/%s" % (c, c)}
    elif oid in DIRECT:
        c = DIRECT[oid]
        m = {"name": name, "prefix": "https://static.prts.wiki/spine38/", "file": "char/%s/%s/%s" % (c, c, c)}
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
    mv = pick(anims, "move")
    if mv:
        d = float(anims[mv]["dur"])
        frames += [{"name": "move_f%02d" % k, "anim": mv, "t": d * k / 4.0} for k in range(4)]
    for kind in ["attack", "skill"]:
        an = pick(anims, kind)
        if an:
            frames += [{"name": "%s_f%02d" % (kind, k), "anim": an, "t": t} for k, t in enumerate(three(anims[an]))]
    de = pick(anims, "death")
    if de:
        d = float(anims[de]["dur"])
        frames += [{"name": "death_f%02d" % k, "anim": de, "t": d * k / 2.0} for k in range(3)]
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
