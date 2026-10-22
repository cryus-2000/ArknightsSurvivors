"""弱技能特效提亮（docs/127 FX-B3，10-23 用户：「你能尝试修改一下部分特效吗」）。
只抬明度（HSV 的 V 往 1 靠 lift 比例），色相 / 饱和 / alpha / 像素格不动；1x 与 @2x 同改。改前原图备份到主仓库 build/ta_review/fx_backup/。
用法：python -X utf8 tools/probes/fx_brighten.py
"""
import colorsys
import os
import shutil
import subprocess
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_gc = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
COMMON = os.path.dirname(_gc if os.path.isabs(_gc) else os.path.join(ROOT, _gc))
INC = os.path.join(ROOT, "art", "incoming")
BAK = os.path.join(COMMON, "build", "ta_review", "fx_backup")
os.makedirs(BAK, exist_ok=True)
# 名字 → 提亮比例（V' = V + (1 − V) × lift）；量化依据见 build/ta_review/fx_metrics.json 的 val
LIFT = {
    "fx_texas_sword_drop": 0.45, "fx_texas_pin_sword": 0.45, "fx_texas_rain_mark": 0.4,   # 德克萨斯剑雨：V 0.22–0.25
    "fx_hoshiguma_guard_glow": 0.35, "fx_hoshiguma_saw_spark": 0.3,                        # 星熊：V 0.37–0.40
    "fx_siege_rock_spike": 0.35, "fx_siege_fissure_tile": 0.3,                             # 推进之王：V 0.38–0.40
    "fx_skalter_wave_big": 0.25,                                                           # 浊心斯卡蒂鲸影：V 0.59，和深海地面同色
}


def lift(path, k):
    im = Image.open(path).convert("RGBA")
    px = im.load()
    cache = {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            c = (r, g, b)
            if c not in cache:
                h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                v2 = v + (1.0 - v) * k
                rr, gg, bb = colorsys.hsv_to_rgb(h, s, v2)
                cache[c] = (round(rr * 255), round(gg * 255), round(bb * 255))
            px[x, y] = cache[c] + (a,)
    im.save(path)


for name, k in LIFT.items():
    for suf in ("@2x.png", ".png"):
        p = os.path.join(INC, name + suf)
        if not os.path.exists(p):
            continue
        b = os.path.join(BAK, name + suf)
        if not os.path.exists(b):
            shutil.copy(p, b)   # 只在第一次备份（重跑不覆盖原图）
        shutil.copy(b, p)       # 每次都从原图重算，重跑结果一致
        lift(p, k)
        print("lift", name + suf, k)
