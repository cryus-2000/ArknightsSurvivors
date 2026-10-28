# -*- coding: utf-8 -*-
"""像素人物体型量测（界面与美术 10-15，docs/103 体型模板的数据来源）。

样本：每名干员 + 博士的待机 f0（@2x 量、换算成 1x 像素报）。
- 几何项（脚本自动）：站立高、头宽、肩宽、腿长、脚底 x。
- 脸部项（人工标注）：眼睛 / 下巴是 1x 下 1–2 像素的东西，自动识别不可靠（白发角色会把头发当皮肤），
  在 @2x ×11 网格图（build/body_metrics/face2x_*.png）上人工读数，写在下面的 ANNOT 里。

定义（全部按 1x 像素报；@2x 读数 ÷ 2）：
    站立高 H     = 脚底行 − 最高不透明行 + 1（含帽 / 耳 / 角；脚底按 sprites.foot y）
    头高         = 下巴行 − 最高不透明行（头饰算进头）
    头高         = 下巴 − 发顶 / 额头（不含帽 / 角 / 耳 / 光环，见 HAIR_TOP）；头饰高 = 发顶 − 最高不透明行
    头身比       = 头高 / 站立高
    头宽         = 眼高那一行主体段的宽（含两侧头发；不含武器 / 尾巴：取这一行最长的连续段）
    眼距         = 两瞳中心 x 差
    眼高         = (眼心 y − 发顶) / 头高（越大眼越靠下）
    下巴宽       = 下巴行往上 1 像素（1x）处脸部宽度；下巴形 = 人工标（圆 / 尖 / 方）
    肩宽         = 下巴往下 1–4 像素（1x）里不透明行宽的最大值
    腿长占比     = (脚底 − 两腿分开的最高行) / 站立高（下半身里从脚往上找连续的「行内 ≥ 2 段、间隔 ≥ 2 像素 @2x」；
                   裙 / 长外套盖住腿时只量到裙摆，偏小，看备注）
    眼到下巴     = 下巴行 − 眼心 y（脸下半的长度，不受帽子 / 角 / 耳影响，比头身比更能比脸型）
    脚底 x       = 最低 3 行（@2x）不透明像素的 x 均值 ÷ 2
    姿势（不驼背，10-15 用户定，docs/103 §5）：
    前倾         = 头部中心 x − 骨盆中心 x（1x，朝右为正），|前倾| ≤ 1 合格
    脖子         = 肩线 y − 下巴 y（1x），≥ 2 合格
    这三个点人工标（POSTURE 表）：自动取中点会被长发、尾巴、武器、披风带偏（10-15 试过，偏差到 ±8 像素），
    剪影上也分不出肩线。头部中心 = 颅顶到下巴那块头（不含马尾 / 耳 / 角 / 帽檐）的左右中点；骨盆中心 = 胯部
    左右中点（裙 / 外套盖住时按两腿内侧中点）；肩线 = 肩膀最高点所在行。新画 / 返修交付必须补这一行

用法：python tools/body_metrics.py [--json out.json]  → 终端表 + build/body_metrics/report.md
"""
import argparse, json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import asset_paths
NAMES = {}

# 人工标注（@2x 坐标，待机 f0）：左眼 x、右眼 x、眼 y、下巴 y、下巴宽、下巴形、眼睛尺寸 w×h（@2x）、备注
# None = 看不到（帽檐 / 面罩 / 侧脸 / 兜帽）
ANNOT = {
    "angelina": (43, 54, 48.5, 56, 10, "圆", "2×2", ""),
    "exusiai": (45, None, 49, 56, 10, "圆", "2×2", "右眼被刘海遮住"),
    "eyjafjalla": (44, 53, 49, 57, 9, "圆", "2×3", ""),
    "hoshiguma": (None, None, 47, 53, 8, "圆", "4×1", "侧脸，只见一只眼"),
    "irene": (48, 58, 52, 59, 10, "圆", "3×2", ""),
    "kaltsit": (50, 61, 50.5, 57, 11, "圆", "3×3", ""),
    "logos": (53, 59, 49, 58, 8, "尖", "2×2", "下巴窄"),
    "lumen": (51.5, 58.5, 51, 59, 9, "圆", "4×2", ""),
    "mizuki": (45.5, 53.5, 46.5, 53, 10, "圆", "2×2", ""),
    "saria": (37.5, 45.5, 40.5, 44, 8, "方", "2×2", "脸小（成女），盾占画面"),
    "siege": (41, 51, 37.5, 43, 10, "圆", "3×2", ""),
    "skadi": (41, 49, 47.5, 52, 8, "尖", "2×2", ""),
    "skalter": (48, 54.5, 51, 56, 7, "尖", "2×2", ""),
    "specter_unchained": (50.5, 57.5, 59, 64, 8, "尖", "2×2", ""),
    "suzuran": (45.5, 54, 47.5, 56, 10, "圆", "2×2", ""),
    "texas": (44.5, 55.5, 52.5, 57, 11, "圆", "2×2", ""),
    "ulpianus": (None, None, None, 53, 12, "方", "—", "帽檐与面罩遮眼"),
    "wisadel": (49.5, 57.5, 50.5, 56, 9, "尖", "2×2", ""),
    "doctor": (None, None, None, None, None, "—", "—", "兜帽，无脸"),
}


# 发顶 / 额头行（1x，人工读整身网格 build/body_metrics/grid_*.png；不含帽 / 角 / 耳 / 光环 / 头饰，±1 像素）。
# 头高（口径 10-15 协调人定）= 下巴 − 发顶；头饰高 = 发顶 − 最高不透明行
HAIR_TOP = {"angelina": 16, "exusiai": 15, "eyjafjalla": 15, "hoshiguma": 17, "irene": 18, "kaltsit": 16, "logos": 17,
            "lumen": 18, "mizuki": 17, "saria": 11, "siege": 10, "skadi": 21, "skalter": 20, "specter_unchained": 19,
            "suzuran": 17, "texas": 17, "ulpianus": 22, "wisadel": 16}
# 帽子盖住头顶的四人（斯卡蒂、浊心斯卡蒂、水月、乌尔比安）：看得见的发顶在帽檐下，量出来头只有 4–8 像素，不可用。
# 改按「眼心 − 8.75」推头顶（8.75 = 其余 13 人眼心到发顶的中位）；乌尔比安面罩遮眼，按「下巴 − 12」（其余人头高中位）推
HAIR_TOP.update({"skadi": 15.0, "skalter": 16.75, "mizuki": 14.5, "ulpianus": 14.5})
HAT_EST = {"skadi", "skalter", "mizuki", "ulpianus"}

# 姿势人工标（1x，待机 f0，在 build/body_metrics/grid_*.png 上读）：头部中心 x、骨盆中心 x、肩线 y。定义见文件头
# 现有干员不按新卡返修（docs/103 §3.1），这里只标新画 / 返修的交付
POSTURE = {}


def char_json(cid):
    p = os.path.join(ROOT, "game", "data", "characters", cid + ".json")
    if not os.path.exists(p):
        p = os.path.join(ROOT, "game", "data", cid + ".json")
    return json.load(open(p, encoding="utf-8"))


def idle(cid):
    d = char_json(cid)
    NAMES[cid] = d.get("name", cid)
    sp = d.get("sprites", {})
    i = sp.get("idle")
    tex = i if isinstance(i, str) else i["tex"]
    foot = (i.get("foot") if isinstance(i, dict) else None) or sp.get("foot") or [24, 46]
    im = Image.open(asset_paths.runtime_png(tex + "@2x")).convert("RGBA")
    return im.crop((0, 0, im.height, im.height)), foot


def runs(row):
    out, start = [], None
    for x, a in enumerate(row):
        if a and start is None:
            start = x
        if not a and start is not None:
            out.append((start, x - 1)); start = None
    if start is not None:
        out.append((start, len(row) - 1))
    return out


def measure(cid):
    f, foot = idle(cid)
    W, H = f.size
    A = [[f.getpixel((x, y))[3] > 0 for x in range(W)] for y in range(H)]
    rows = [y for y in range(H) if any(A[y])]
    top, bot = rows[0], rows[-1]
    foot_y = foot[1] * 2 + 1   # @2x 脚底行
    an = ANNOT[cid]
    lx, rx, ey, chin, chin_w, chin_shape, eye_sz, note = an
    stand = (foot_y - top + 1) / 2.0

    def width(y):
        r = runs(A[y])
        if not r:
            return 0
        # 主体 = 跨过画布中线附近的最大段（武器多是细长独立段）
        r.sort(key=lambda s: s[1] - s[0], reverse=True)
        return r[0][1] - r[0][0] + 1

    res = {"id": cid, "name": NAMES[cid], "stand": stand}
    if chin is not None:
        ht = HAIR_TOP.get(cid)
        head_h = (chin / 2.0 - ht) if ht is not None else (chin - top) / 2.0
        res["head_h"] = head_h
        res["headwear_h"] = (ht - top / 2.0) if ht is not None else None
        res["head_ratio"] = round(head_h / stand, 3)
        wy = int(round(ey)) if ey is not None else (top + chin) // 2
        res["head_w"] = width(wy) / 2.0   # 眼高那一行的主体宽（含两侧头发；尾巴 / 披发在这一行以下不算）
        if ey is not None:
            res["eye_chin"] = (chin - ey) / 2.0
        res["shoulder_w"] = max(width(y) for y in range(chin + 2, min(H, chin + 9))) / 2.0
        if cid in POSTURE:
            hcx, pcx, shy = POSTURE[cid]
            res["lean"] = round(hcx - pcx, 1)
            res["neck"] = round(shy - chin / 2.0, 1)
            res["posture_ok"] = "✓" if abs(res["lean"]) <= 1 and res["neck"] >= 2 else "✗"
        res["chin_w"] = chin_w / 2.0 if chin_w else None
    res["chin_shape"] = chin_shape
    if lx is not None and rx is not None:
        res["eye_d"] = (rx - lx) / 2.0
    if ey is not None and chin is not None:
        ht2 = HAIR_TOP.get(cid, top / 2.0)
        res["eye_pos"] = round((ey / 2.0 - ht2) / (chin / 2.0 - ht2), 2)   # 0 = 发顶，1 = 下巴
    res["eye_size"] = eye_sz
    # 腿：从脚往上，行内主体有 ≥ 2 段且间隔 ≥ 2
    split, miss = None, 0
    lo = top + int((foot_y - top) * 0.5)   # 只在下半身找
    for y in range(min(bot, foot_y), lo, -1):
        r = [s for s in runs(A[y]) if s[1] - s[0] >= 1]
        gap = len(r) >= 2 and any(r[i + 1][0] - r[i][1] - 1 >= 2 for i in range(len(r) - 1))
        if gap:
            split, miss = y, 0
        elif split is not None:
            miss += 1
            if miss > 1:
                break
    res["leg_ratio"] = round((foot_y - split) / 2.0 / stand, 2) if split else None
    xs = [x for y in range(max(top, bot - 2), bot + 1) for x in range(W) if A[y][x]]
    res["foot_x"] = round(sum(xs) / len(xs) / 2.0, 1)
    res["note"] = (note + "；" if note else "") + "头顶按眼高推（帽遮）" if cid in HAT_EST else note
    return res


ORDER = ["angelina", "exusiai", "eyjafjalla", "hoshiguma", "irene", "kaltsit", "logos", "lumen", "mizuki", "saria",
         "siege", "skadi", "skalter", "specter_unchained", "suzuran", "texas", "ulpianus", "wisadel", "doctor"]
COLS = [("stand", "站立高"), ("head_h", "头高"), ("headwear_h", "头饰高"), ("head_w", "头宽"), ("head_ratio", "头身比"), ("eye_d", "眼距"), ("eye_pos", "眼高"), ("eye_chin", "眼到下巴"),
        ("eye_size", "眼(@2x)"), ("chin_w", "下巴宽"), ("chin_shape", "下巴形"), ("shoulder_w", "肩宽"), ("leg_ratio", "腿长占比"), ("lean", "前倾"), ("neck", "脖子"), ("posture_ok", "姿势"), ("foot_x", "脚底x"), ("note", "备注")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    rs = [measure(c) for c in ORDER]
    head = "| id | 名 | " + " | ".join(c[1] for c in COLS) + " |"
    lines = [head, "|" + "---|" * (len(COLS) + 2)]
    for r in rs:
        lines.append("| %s | %s | " % (r["id"], r["name"]) + " | ".join("" if r.get(k) is None else str(r.get(k)) for k, _ in COLS) + " |")
    text = "\n".join(lines)
    print(text)
    od = os.path.join(ROOT, "build", "body_metrics")
    os.makedirs(od, exist_ok=True)
    open(os.path.join(od, "report.md"), "w", encoding="utf-8").write("# 体型量测（tools/body_metrics.py，1x 像素）\n\n" + text + "\n")
    if a.json:
        json.dump(rs, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
