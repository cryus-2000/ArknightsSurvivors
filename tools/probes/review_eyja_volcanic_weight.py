"""Build faithful before/after review media from actual viewport PNGs."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/eyja_volcanic_weight"
sections = []
for key, title in [("low_lob", "普攻低抛与熔岩碎块"), ("ignite", "点燃重弹"), ("volcano", "S3 · 浮空持续投弹")]:
    pairs = []
    for i in range(72):
        pair = Image.new("RGB", (1800, 560))
        for col, version in enumerate(["before_unified", "after"]):
            with Image.open(OUT / version / key / f"f_{i:04d}.png") as im:
                pair.paste(im.convert("RGB").crop((240, 90, 690, 370)).resize((900, 560), Image.Resampling.NEAREST), (col * 900, 0))
        pairs.append(pair)
    palette = pairs[22].quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in pairs]
    for suffix, timings in [("", [70, 70, 60]), ("_slow", [130, 130, 140])]:
        frames[0].save(OUT / f"{key}{suffix}.gif", save_all=True, append_images=frames[1:],
                       duration=[timings[i % 3] for i in range(72)], loop=0, disposal=1)
    pairs[22].save(OUT / f"{key}_key.png")
    sections.append(f'<section><h2>{title}</h2><p>左旧右新 · 常速。<a href="{key}_slow.gif">半速</a> · <a href="after/{key}/f_0022.png">完整实机 PNG</a></p><img src="{key}.gif"><details><summary>关键瞬间</summary><img src="{key}_key.png"></details></section>')

trace = json.loads((OUT / "trace_verification.json").read_text(encoding="utf-8"))
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>艾雅法拉 · 三路熔岩与落地统一</title><style>body{max-width:1400px;margin:24px auto;padding:0 18px;background:#192530;color:#e4edf4;font:17px/1.7 system-ui}a{color:#a2d8f3}img{max-width:100%;image-rendering:pixelated}section{margin:30px 0;border-top:1px solid #526678}.note{padding:18px;background:#293c4c}</style><h1>艾雅法拉 · 三路熔岩与落地统一</h1><p class="note">左：上轮预览；右：本次。S3 三条弹道统一为同款完整岩壳、灼亮裂隙与短拖焰，附加弹恢复实体岩块，尺寸与主弹接近。取消四散火星，始终按 2 像素网格绘制。</p><p class="note">普攻、S2 和 S3 的落地共用一套效果：短促亮闪 → 贴地热斑 → 两块低矮碎屑消退。移除重复叠加的通用爆炸、旧帧条和冲击环；持续熔池也换为同一岩壳、暗红热区与亮缝，取消翻滚贴图和冒泡火星。原命中音效、顿帧、伤害和持续跳伤保留。</p><p>本轮只改美术；仍是 10 轮主弹、20 枚附加弹，目标、轨迹、飞行时间、伤害和半径不变。沿用已调整的普攻低抛 0.36 秒、直线速度 280，S2 速度 320，以及 S3 末轮后 0.28 秒落地收势。图鉴真实视口分别录制；每种 72 张 PNG、15 fps 采样。GIF 只裁切、最近邻放大与编码，玩法一致由单独 TRACE 核对。</p>'''
launches = json.loads((OUT / "airborne_launches.json").read_text(encoding="utf-8"))
page += f'<p>实际场景专项回归：{len(launches["launches"])} 轮主弹、{launches["bonus_count"]} 枚附加弹；发射均处于抬升后或浮空循环。本轮 S3 美术调整前后 {trace["trace_lines_identical"]} 行玩法 TRACE 一致，非视觉配置逐字段相同。</p>'
page += "".join(sections)
delivery_path = OUT / "delivery.json"
status = json.loads(delivery_path.read_text(encoding="utf-8")) if delivery_path.exists() else {}
page += f'<p>视觉效果待用户核对。定向轨迹与发射回归通过；完整分级检查：{status.get("checks", "运行中")}。<a href="delivery.json">交付记录</a></p></html>'
(OUT / "review.html").write_text(page, encoding="utf-8")
(OUT / "visual_checks.json").write_text(json.dumps({"source": "actual Godot gallery viewport", "frames_per_clip": 72, "clips": 3, "trace": trace, "visual_approval": "pending"}, ensure_ascii=False, indent=2), encoding="utf-8")
print(OUT / "review.html")
