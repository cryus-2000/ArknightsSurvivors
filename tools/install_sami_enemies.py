#!/usr/bin/env python3
"""萨米敌人 / Boss 像素帧条接进萨米主题（11-25，docs/399 §10）。

来源：tools/spine_px_enemy.py --dst <目录> 出的运行时帧条（@2x = 1 倍最近邻 ×2，同水月像素尺度）+ 规格 tools/spine_run_trial/cfg/sami_enemies_sprites.json。
做的事（可重复运行）：
  1. 按 game/themes/sami/data/enemies.json 每个敌人的 tex_final，把现有敌人帧条契约里的五条复制进 game/art/enemies/sami/：
     本体（待机）/ _move / _attack / _death / _wound（有的才装）；Boss 另装 1 倍本体与各动作（同 install_enemy_redraw.BOSS_1X：boss_intro 读 1 倍）。
     目录里不在本次清单的旧帧条（11-20 的原生 @2x 样例、rush / combat 等契约外动作）连同 .import 一起删掉。
  2. 写 game/themes/sami/data/enemy_pixels.json / enemy_redraw.json = 水月同名文件 + 萨米条目（萨米局里仍有水月贴图的东西，比如鸭爵），
     theme.json 的 enemy_pixels / enemy_redraw 指过去；水月主题一个字不动。
  3. art.gd V6_FRAMES 里登记萨米 _death 帧条 [帧数, 帧数 / 时长]（单独一段标记，别手改）。
  4. enemies.json 的 tex 换成 tex_final（水月占位退役）。
新 png 的 .import 由 Godot 生成（--imports，在 F 盘临时工程里跑一次 --import，fix_alpha_border 改 false 同现有敌人）。

    python tools/install_sami_enemies.py --src F:/ArknightsSurvivors_build/kind-dijkstra/sami_px [--imports]
"""
import argparse, glob, json, os, re, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import asset_paths

SPEC = ROOT / "tools" / "spine_run_trial" / "cfg" / "sami_enemies_sprites.json"
THEME = ROOT / "game" / "themes" / "sami"
DEEP = ROOT / "game" / "themes" / "deep_sea" / "data"
ART = ROOT / "game" / "art" / "enemies" / "sami"
ART_GD = ROOT / "game" / "scripts" / "art.gd"
BEGIN = "\t# >>> sami 死亡帧条（tools/install_sami_enemies.py 生成，别手改）\n"
END = "\t# <<< sami\n"
ACTS = ["", "_move", "_attack", "_death", "_wound"]   # 现有敌人帧条契约（world.gd：本体 / 移动 / 攻击 / 受击；game.gd：死亡）


def patch_art_gd(deaths: dict) -> None:
    s = ART_GD.read_text(encoding="utf-8")
    i = s.index("const V6_FRAMES := {")
    j = s.index("\n}\n", i)
    blk = s[i:j]
    if BEGIN in blk:
        a = blk.index(BEGIN)
        b = blk.index(END) + len(END)
        blk = blk[:a].rstrip("\n") + blk[b:]
    ks = sorted(deaths)
    lines = [BEGIN]
    for n in range(0, len(ks), 4):
        lines.append("\t" + " ".join('"%s": [%d, %.1f],' % (k, deaths[k][0], deaths[k][1]) for k in ks[n:n + 4]) + "\n")
    lines.append(END)
    blk = blk.rstrip("\n") + "\n" + "".join(lines).rstrip("\n")
    ART_GD.write_text(s[:i] + blk + s[j:], encoding="utf-8", newline="\n")


def gen_imports(pngs: list) -> None:
    import godot_runner as gr
    tmp = Path("F:/ArknightsSurvivors_build/sami_enemy_sprites/_imp")
    shutil.rmtree(tmp, ignore_errors=True)
    d = tmp / "art" / "enemies" / "sami"
    d.mkdir(parents=True)
    (tmp / "project.godot").write_text('config_version=5\n\n[application]\n\nconfig/name="imp"\n', encoding="utf-8")
    for p in pngs:
        shutil.copy(p, d)
    r = subprocess.run([gr.find_godot(), "--headless", "--path", str(tmp), "--import", "--audio-driver", "Dummy"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
    n = 0
    for p in pngs:
        f = d / (os.path.basename(p) + ".import")
        if f.exists() and "uid=" in f.read_text(encoding="utf-8"):
            txt = f.read_text(encoding="utf-8").replace("process/fix_alpha_border=true", "process/fix_alpha_border=false")
            Path(p + ".import").write_text(txt, encoding="utf-8", newline="\n")
            n += 1
    print("import rc", r.returncode, "生成", n, "/", len(pngs))
    shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="spine_px_enemy.py --dst 的目录")
    ap.add_argument("--imports", action="store_true", help="给没有 .import 的新 png 跑 Godot 生成")
    a = ap.parse_args()
    spec = json.loads(SPEC.read_text(encoding="utf-8"))["sprites"]
    ef = THEME / "data" / "enemies.json"
    edata = json.loads(ef.read_text(encoding="utf-8"))
    pix = json.loads((DEEP / "enemy_pixels.json").read_text(encoding="utf-8"))
    red = json.loads((DEEP / "enemy_redraw.json").read_text(encoding="utf-8"))
    keep, deaths, n_files = set(), {}, 0
    ART.mkdir(parents=True, exist_ok=True)
    for eid, e in edata["enemies"].items():
        if not isinstance(e, dict) or not str(e.get("tex_final", "")).startswith("e_sami_"):
            continue
        base = e["tex_final"]
        boss = os.path.exists(os.path.join(a.src, base + ".png"))
        for suf in ACTS:
            key = base + suf
            if key not in spec:
                continue
            for tail in (("@2x.png", ".png") if boss else ("@2x.png",)):
                src = os.path.join(a.src, key + tail)
                if not os.path.exists(src):
                    print("缺", src)
                    return 1
                dst = asset_paths.out_png(key + tail[:-4])
                if not os.path.exists(dst) or open(src, "rb").read() != open(dst, "rb").read():
                    shutil.copyfile(src, dst)
                keep.add(os.path.basename(dst))
                n_files += 1
            sp = spec[key]
            pix[key] = sp["pixels"]
            red[key] = sp["redraw"]
            if suf == "_death":
                r = sp["redraw"]
                deaths[key] = (r["frames"], r["frames"] / max(0.1, r["duration"]))
        if e.get("tex") != base:
            e["tex"] = base
    removed = 0
    for p in glob.glob(str(ART / "*.png")):
        if os.path.basename(p) not in keep:
            os.remove(p)
            removed += 1
            if os.path.exists(p + ".import"):
                os.remove(p + ".import")
    ef.write_text(json.dumps(edata, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    (THEME / "data" / "enemy_pixels.json").write_text(json.dumps(pix, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    (THEME / "data" / "enemy_redraw.json").write_text(json.dumps(red, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    tf = THEME / "theme.json"
    t = json.loads(tf.read_text(encoding="utf-8"))
    t["data"]["enemy_pixels"] = "res://themes/sami/data/enemy_pixels.json"
    t["data"]["enemy_redraw"] = "res://themes/sami/data/enemy_redraw.json"
    tf.write_text(json.dumps(t, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    patch_art_gd(deaths)
    print("装 %d 个文件，删旧 %d 个，死亡帧条 %d 条" % (n_files, removed, len(deaths)))
    if a.imports:
        gen_imports([p for p in glob.glob(str(ART / "*.png")) if not os.path.exists(p + ".import")])
    return 0


if __name__ == "__main__":
    sys.exit(main())
