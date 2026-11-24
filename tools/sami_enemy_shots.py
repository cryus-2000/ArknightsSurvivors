# -*- coding: utf-8 -*-
"""萨米敌人局内截图对照（11-25，docs/399 §10）：每个敌人一局 --theme=sami --spawntest=<id>（第 20 帧刷在队长右侧），
取第 SHOT 帧整屏截图（1280×720，1 倍），按敌人脚底位置裁一块，与原作参照帧（build/prts_ref/<src>/idle_f00.png）并排拼成对照表。
窗口经 godot_runner（屏幕外、静音），本机最多 2 个并行。

    python tools/sami_enemy_shots.py --out F:/ArknightsSurvivors_build/sami_enemy_sprites [id …]
"""
import argparse, glob, json, os, shutil, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR
import spine_px_enemy as SE

SHOT = 48   # --spawntest --spawnhold 第 48 帧（镜头已跟上队长瞬移；敌人钉在原位、打不死，脚底屏幕位置由 SPAWNPOS 行给出）
SHOT_AT = {"lead": 72}   # 木裂选招不受 busy_t 管，第 30–60 帧自己的预警圈盖住本体；66–96 帧干净
FONT = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 16)
FONT_S = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 13)


def ids_of():
    d = json.load(open(os.path.join(ROOT, "game", "themes", "sami", "data", "enemies.json"), encoding="utf-8"))["enemies"]
    return [k for k, v in d.items() if isinstance(v, dict) and str(v.get("tex", "")).startswith("e_sami_")]


def shoot(game, out, eid):
    sd = os.path.join(out, "_" + eid)
    shutil.rmtree(sd, ignore_errors=True)
    os.makedirs(sd)
    cmd = [GR.find_godot(), "--path", game, "--resolution", "1280x720", "--audio-driver", "Dummy", "--fixed-fps", "60", "--",
           "--balance", "--theme=sami", "--seed=1", "--op=mizuki", "--spawntest=" + eid, "--spawnhold", "--nohud", "--shotdir=" + sd]
    o, e, to = GR.run_godot(cmd, 240)
    shot = SHOT_AT.get(eid, SHOT)
    p = os.path.join(sd, "shot_spawn_%s_%03d.png" % (eid, shot))
    if not os.path.exists(p):
        return eid, None, "没截到%s %s" % ("（超时）" if to else "", "；".join(GR.script_errors(o, e)[:2]))
    dst = os.path.join(out, "ingame_%s.png" % eid)
    shutil.copy2(p, dst)
    pos = [l.split() for l in o.splitlines() if l.startswith("SPAWNPOS %d " % shot)]
    if pos:
        json.dump([float(pos[0][3]), float(pos[0][4])], open(dst[:-4] + ".json", "w"))
    shutil.rmtree(sd, ignore_errors=True)
    return eid, dst, "；".join(GR.script_errors(o, e)[:2])


def sheet(out, shots):
    BG = (40, 46, 58, 255)
    cells = []
    for eid, p in shots:
        e = SE.ENEMIES[eid]
        full = Image.open(p).convert("RGBA")
        # 按 SPAWNPOS（敌人脚底在屏幕上的位置）裁一块，大 Boss 给大框
        big = e["tier"] == "boss"
        cx, cy = json.load(open(p[:-4] + ".json"))
        cx, cy = int(cx), int(cy)
        bw, bh = (340, 300) if big else (160, 120)
        down = 120 if big else 40   # SPAWNPOS 是 e.pos（身体中心偏下），Boss 的脚底在它下方更远
        crop = full.crop((cx - bw // 2, cy - bh + down, cx + bw // 2, cy + down))
        ref = glob.glob(os.path.join(SE.COMMON, "build", "prts_ref", e["src"], "idle_f00.png"))
        r = Image.open(ref[0]).convert("RGBA") if ref else Image.new("RGBA", (10, 10))
        if r.getbbox():
            r = r.crop(r.getbbox())
        k = min((bh - 10) / r.height, (bw - 10) / r.width)
        r = r.resize((max(1, int(r.width * k)), max(1, int(r.height * k))), Image.LANCZOS)
        cells.append((eid, e["name"], r, crop, bw, bh))
    cols = 4
    cw = max(c[4] for c in cells) * 2 + 30
    rows = [cells[i:i + cols] for i in range(0, len(cells), cols)]
    rhs = [max(c[5] for c in rr) + 30 for rr in rows]
    img = Image.new("RGBA", (cw * cols + 10, 40 + sum(rhs)), BG)
    dr = ImageDraw.Draw(img)
    dr.text((10, 8), "萨米敌人：左 = 原作（待机，缩放到框内），右 = 局内截图 1 倍（1280×720，--theme=sami --spawntest --spawnhold，第 %d 帧，木裂第 72 帧；朝向队长）" % SHOT, font=FONT, fill=(255, 235, 150, 255))
    y = 40
    for rr, rh in zip(rows, rhs):
        for i, (eid, name, r, crop, bw, bh) in enumerate(rr):
            x = 10 + cw * i
            dr.text((x, y), "%s %s" % (eid, name), font=FONT_S, fill=(200, 210, 225, 255))
            img.alpha_composite(r, (x + (bw - r.width) // 2, y + 22 + bh - r.height))
            img.alpha_composite(crop, (x + bw + 10, y + 22))
        y += rh
    p = os.path.join(out, "sami_enemy_ingame_vs_canon.png")
    img.save(p)
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(p[:-4] + "_x2.png")
    print(p, img.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--out", required=True)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--sheet-only", action="store_true")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    ids = a.ids or ids_of()
    game = os.path.join(ROOT, "game")
    if a.sheet_only:
        res = [(i, os.path.join(a.out, "ingame_%s.png" % i), "") for i in ids if os.path.exists(os.path.join(a.out, "ingame_%s.png" % i))]
    else:
        GR.ensure_imported(game)
        with ThreadPoolExecutor(a.jobs) as ex:
            res = list(ex.map(lambda i: shoot(game, a.out, i), ids))
    for eid, p, w in res:
        if w:
            print(eid, w)
    sheet(a.out, [(i, p) for i, p, _ in res if p])


if __name__ == "__main__":
    main()
