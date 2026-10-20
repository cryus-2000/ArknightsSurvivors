"""Compare saved real viewport frames, without repainting or overlaying effects."""
from pathlib import Path
import json
import os
from html import escape
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/ulpianus_impact_revision'
CURRENT = ROOT / 'build/siege_ulpianus_runtime/ulpianus'
BEFORE = OUT / 'before/ulpianus'
OUT.mkdir(parents=True, exist_ok=True)
log = (CURRENT.parent / 'ulpianus_capture.log').read_text(encoding='utf-8')
assert 'failures=0' in log and 'SCRIPT ERROR' not in log and 'Parse Error' not in log

def crop(path):
    with Image.open(path) as im:
        return im.convert('RGB').crop((320, 190, 620, 350)).resize((900, 480), Image.Resampling.NEAREST)

def gif(name, frames, duration):
    board = Image.new('RGB', (frames[0].width, frames[0].height * 4))
    for n, i in enumerate([0, len(frames)//3, 2*len(frames)//3, len(frames)-1]):
        board.paste(frames[i], (0, n * frames[i].height))
    palette = board.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    encoded = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    encoded[0].save(OUT / name, save_all=True, append_images=encoded[1:], duration=duration, loop=0, disposal=1)

sections = []
for key, title, start, end in [('attack', '普通锚击', 40, 80), ('s1', 'S1 投锚与回拉', 160, 190), ('s3', 'S3 投出、弹射与落地', 320, 370)]:
    frames = []
    for i in range(start, end):
        pair = Image.new('RGB', (1800, 480))
        pair.paste(crop(BEFORE / f'f_{i:04d}.png'), (0, 0))
        pair.paste(crop(CURRENT / f'f_{i:04d}.png'), (900, 0))
        frames.append(pair)
    gif(key + '.gif', frames, 50)
    gif(key + '_slow.gif', frames, 100)
    sections.append(f'<section><h2>{title}</h2><p>左：之前；右：返修。相同采样时刻，20 fps 常速。<a href="{key}_slow.gif">半速</a></p><img src="{key}.gif"></section>')

evidence = json.loads((CURRENT / 'doctor_evidence.json').read_text())
assert all(s['height'] == 128 for s in evidence['samples'])
for action, label, count in [('idle', '待机', 20), ('run', '跑步', 16), ('death', '倒下', 16)]:
    frames = [crop(CURRENT / f'doctor_{action}_{i:02d}.png') for i in range(count)]
    gif('doctor_' + action + '.gif', frames, 50)
    sections.append(f'<section><h2>博士 · {label}</h2><p>已确认新画风。暂停场景取样真实角色渲染与动画，不模拟位移。</p><img class="doctor" src="doctor_{action}.gif"></section>')

# Inspect impact, water crest and wake as lossless PNGs, without GIF palette reduction.
for index in [169, 333, 334, 335, 336, 337, 338, 339]:
    pair = Image.new('RGB', (1800, 480))
    pair.paste(crop(BEFORE / f'f_{index:04d}.png'), (0, 0))
    pair.paste(crop(CURRENT / f'f_{index:04d}.png'), (900, 0))
    pair.save(OUT / f'compare_{index}.png')
sections.append('<section><h2>落地关键瞬间</h2><p>左旧右新；PNG 保留实际视口颜色。</p>' + ''.join(f'<a href="compare_{i}.png">f{i}</a> ' for i in [169, 333, 334, 335, 336, 337, 338, 339]) + '<img src="compare_336.png"></section>')
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>乌尔比安特效返修与博士新版</title><style>body{max-width:1400px;margin:24px auto;padding:0 18px;background:#192530;color:#e4edf4;font:17px/1.7 system-ui}a{color:#a2d8f3}img{width:100%;image-rendering:pixelated}img.doctor{max-width:900px}section{margin:36px 0;border-top:1px solid #5b6b79}.note{padding:18px;background:#293c4c}</style><h1>乌尔比安落地特效返修 · 博士新版已接入</h1><p class="note">去掉被放大的旧圆环和大块纯白水花。新版使用局部裂纹、小水花和延迟散开的细弧；伤害、范围、位移、命中与顿帧时间不变。博士使用此前确认的待机、跑步、倒下，不重新生成外观。</p><p>下方来自真实 Godot 视口，未后贴人物或特效。对比夹具按原来的固定时刻释放技能与控制测试敌人；不是自然对局或平衡测试。实机同种子与构建验证记录另列交付。</p>'''
page = page.replace('去掉被放大的旧圆环和大块纯白水花。新版使用局部裂纹、小水花和延迟散开的细弧；', '保留原版水花，取消粗灰收链大环与重复水花。新版使用局部裂纹、原水花和延迟散开的细弧；')
delivery_path = OUT / 'delivery.json'
if delivery_path.exists():
    delivery = json.loads(delivery_path.read_text(encoding='utf-8'))
    package = Path(delivery['package_zip'])
    assert package.is_file() and delivery['package_verified']
    link = escape(os.path.relpath(package, OUT).replace('\\', '/'), quote=True)
    page += f'<p class="note">独立内测包：{escape(delivery["commit"])}，资源、启动与 ZIP 一致性验证通过。<a href="{link}">本地测试包</a></p>'
page += ''.join(sections) + '<p>独立本地测试分支；尚未合入 main。画面采集退出仍有既有资源清理告警，未发现脚本或解析错误。</p></html>'
(OUT / 'review.html').write_text(page, encoding='utf-8')
print(OUT / 'review.html')
