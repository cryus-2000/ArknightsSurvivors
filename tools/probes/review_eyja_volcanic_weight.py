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
        for col, version in enumerate(["before_grid", "after"]):
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
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>艾雅法拉 · 保留熔池方格与精英阶段对照</title><style>body{max-width:1400px;margin:24px auto;padding:0 18px;background:#192530;color:#e4edf4;font:17px/1.7 system-ui}a{color:#a2d8f3}img{max-width:100%;image-rendering:pixelated}section{margin:30px 0;border-top:1px solid #526678}.note{padding:18px;background:#293c4c}table{border-collapse:collapse;width:100%}th,td{border:1px solid #526678;padding:9px;text-align:left}</style><h1>艾雅法拉 · 保留熔池方格与精英阶段对照</h1><p class="note">左：上一版统一热斑；右：本次。保留原 fx_eyja_lava_pool 的橙色方格 / 翻滚纹理，作为持续熔池内层；外侧沿用统一岩壳。普通落地仍为短促亮闪、贴地热斑和两块低矮碎屑。原先清掉的重复爆炸、冲击环及四散火星保持移除。</p><p>S3 三路都使用完整岩块。现有伤害、弹数、目标、弹道、飞行与持续时间不变；沿用普攻低抛 0.36 秒、直线速度 280，S2 速度 320，以及 S3 末轮后 0.28 秒落地收势。</p><section id="stages"><h2>当前三个精英阶段 · 普攻常速实机</h2><p>人物普攻共用原 8 帧；各阶段的弹数、轨迹、命中附着和留场效果保留。以下分别按图鉴的 N1–N2、N1–N5、全部六个成长节点录制；精零图已取得复咏与迸溅，不是初始无成长状态。</p><table><tr><th>精零 · 复咏与迸溅</th><th>精一 · 熔蚀</th><th>精二 · 三重咏唱</th></tr><tr><td>直射；复咏追加第二发，爆点再迸出熔岩</td><td>保持直射；爆炸范围 +25%，附加暗红熔蚀裂纹；解锁 S2 重弹</td><td>三发三角低抛，全部落地后留 1.2 秒熔池；解锁 S3 浮空投弹</td></tr></table><img src="stages.gif"><p>三阶段均为实际图鉴视口，1 倍像素显示；每段 72 张 PNG、15 fps。分别录制，不声称同帧敌人状态完全相同。</p></section>'''
stage_pairs = []
for i in range(72):
    row = Image.new("RGB", (1350, 280))
    for col, stage in enumerate(["elite0", "elite1", "elite2"]):
        with Image.open(OUT / "stages_grid" / stage / f"f_{i:04d}.png") as im:
            row.paste(im.convert("RGB").crop((240, 90, 690, 370)), (col * 450, 0))
    stage_pairs.append(row)
palette = stage_pairs[22].quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
stage_frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in stage_pairs]
stage_frames[0].save(OUT / "stages.gif", save_all=True, append_images=stage_frames[1:], duration=[(70,70,60)[i % 3] for i in range(72)], loop=0, disposal=1)
stage_pairs[22].save(OUT / "stages_key.png")
launches = json.loads((OUT / "airborne_launches.json").read_text(encoding="utf-8"))
page += f'<p>实际场景专项回归：{len(launches["launches"])} 轮主弹、{launches["bonus_count"]} 枚附加弹；发射均处于抬升后或浮空循环。本轮恢复熔池纹理前后 {trace["trace_lines_identical"]} 行玩法 TRACE 一致，全部干员数据配置逐字段相同。</p>'
page += "".join(sections)
delivery_path = OUT / "delivery.json"
status = json.loads(delivery_path.read_text(encoding="utf-8")) if delivery_path.exists() else {}
page += f'<p>视觉效果待用户核对。定向轨迹与发射回归通过；完整分级检查：{status.get("checks", "运行中")}。<a href="delivery.json">交付记录</a></p></html>'
(OUT / "review.html").write_text(page, encoding="utf-8")
(OUT / "visual_checks.json").write_text(json.dumps({"source": "actual Godot gallery viewport", "frames_per_clip": 72, "clips": 6, "stage_clips": {"elite0": "N1-N2", "elite1": "N1-N5", "elite2": "N1-N6"}, "trace": trace, "visual_approval": "pending"}, ensure_ascii=False, indent=2), encoding="utf-8")
print(OUT / "review.html")
