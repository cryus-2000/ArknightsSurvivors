"""凯尔希本体 / 流明 / 艾丽妮候选审阅图：常速 GIF（游戏内时序）、4 倍慢放、8 倍逐帧、旧版对照；汇总成一页 HTML。

先跑 package_kaltsit_lumen_irene.py。输出 build/op_klc/review/。
"""
from pathlib import Path
import base64
import io
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'build/op_klc'
OUT = SRC / 'review'
BG = (48, 61, 77, 255)
NAMES = {'kaltsit': '凯尔希', 'lumen': '流明', 'irene': '艾丽妮'}
LABEL = {
    'idle': '待机（原作 Idle）', 'run': '跑步（新做）', 'attack': '普攻', 'skill': '技能 / S1', 'command': '指令手势（新做，S2 / S3）',
    'attack_beam': '精二光柱普攻（新做）', 'skill_s2': 'S2', 'skill_s3_start': 'S3 起手', 'skill_s3_loop': 'S3 持续', 'skill_s3_end': 'S3 收势',
    'attack_retrial': '三段刺（再审，新做）', 'finisher': '裂潮余波：刺 → 锥斩 → 举炮补枪（新做）',
}
SRC_NOTE = {
    ('kaltsit', 'attack'): '原作 Attack（治疗）', ('kaltsit', 'skill'): '同普攻条（S1 原作无独立轨），按旧技能时长播',
    ('lumen', 'attack'): '新做：举灯伞朝敌瞄准、出手', ('lumen', 'skill'): '原作 Skill_1', ('lumen', 'skill_s2'): '原作 Skill_2',
    ('lumen', 'skill_s3_start'): '原作 Skill_3_Begin', ('lumen', 'skill_s3_loop'): '原作 Skill_3_Idle', ('lumen', 'skill_s3_end'): '原作 Skill_3_End',
    ('irene', 'attack'): '原作 Attack（两段刺）', ('irene', 'skill'): '原作 Skill_1（去掉原作刀光）', ('irene', 'skill_s2'): '原作 Skill_2（去掉原作刀光）',
    ('irene', 'skill_s3_start'): '原作 Skill_3_Start', ('irene', 'skill_s3_loop'): '原作 Skill_3_Attack 中段（原作这段人物透明，强制显示）',
    ('irene', 'skill_s3_end'): '原作 Skill_3_Attack 落地段',
}
# 旧条：(文件, 帧宽 @2x, 原点 @2x, fps)
OLD = {
    'kaltsit': {'idle': ('op_kaltsit_idle', 96, (48, 92), 4), 'run': ('op_kaltsit_run', 96, (48, 92), 10), 'attack': ('op_kaltsit_attack', 96, (48, 92), 14),
                'skill': ('op_kaltsit_skill', 96, (48, 92), 12), 'command': ('op_kaltsit_command', 96, (48, 92), 12)},
    'lumen': {'idle': ('op_lumen_idle', 96, (48, 92), 4), 'run': ('op_lumen_run', 96, (48, 92), 10), 'attack': ('op_lumen_attack', 96, (48, 92), 12),
              'attack_beam': ('op_lumen_attack', 96, (48, 92), 12), 'skill': ('op_lumen_skill', 96, (48, 92), 12), 'skill_s2': ('op_lumen_skill', 96, (48, 92), 12),
              'skill_s3_start': ('op_lumen_skill', 96, (48, 92), 12)},
    'irene': {'idle': ('op_irene_idle', 96, (48, 92), 4), 'run': ('op_irene_run', 96, (58, 92), 10), 'attack': ('op_irene_attack', 96, (44, 92), 12),
              'attack_retrial': ('op_irene_attack', 96, (44, 92), 12), 'finisher': ('op_irene_finisher', 96, (48, 92), 14),
              'skill': ('op_irene_skill', 96, (48, 92), 12), 'skill_s2': ('op_irene_skill', 96, (48, 92), 12), 'skill_s3_start': ('op_irene_skill', 96, (48, 92), 12)},
}


def stage(im, size):
    """任意画布 → 256 舞台，原点 (128,184)。"""
    s = Image.new('RGBA', (256, 256)); p = (256 - size) // 2; s.alpha_composite(im, (p, p)); return s


def old_frames(op, slot):
    o = OLD[op].get(slot)
    if not o: return None, None
    im = Image.open(ROOT / 'art/incoming' / f'{o[0]}@2x.png').convert('RGBA'); w = o[1]; ox, oy = o[2]
    out = []
    for i in range(im.width // w):
        s = Image.new('RGBA', (256, 256)); s.alpha_composite(im.crop((i * w, 0, i * w + w, w)), (128 - ox, 184 - oy)); out.append(s)
    return out, [1 / o[3]] * len(out)


def on_bg(im, box, k):
    c = im.crop(box); bg = Image.new('RGBA', c.size, BG); d = ImageDraw.Draw(bg)
    d.line([(0, 184 - box[1]), (c.width, 184 - box[1])], fill=(88, 104, 122, 255)); bg.alpha_composite(c)
    return bg.resize((c.width * k, c.height * k), Image.Resampling.NEAREST)


def union(frames, pad=4):
    b = None
    for f in frames:
        x = f.getchannel('A').getbbox()
        if x: b = x if b is None else (min(b[0], x[0]), min(b[1], x[1]), max(b[2], x[2]), max(b[3], x[3]))
    return (max(0, b[0] - pad), max(0, b[1] - pad), min(256, b[2] + pad), min(256, max(b[3], 185) + pad))


def gif(frames, durs, box, k, slow=1):
    seq = [on_bg(f, box, k).convert('RGB') for f in frames]
    buf = io.BytesIO()
    seq[0].save(buf, 'GIF', save_all=True, append_images=seq[1:], duration=[max(20, round(d * 1000 * slow)) for d in durs], loop=0, disposal=2)
    return buf.getvalue()


def png(im):
    buf = io.BytesIO(); im.convert('RGB').save(buf, 'PNG', optimize=True); return buf.getvalue()


def durations(spec):
    if 'frame_durations' in spec: return spec['frame_durations']
    return [1 / spec['fps']] * spec['frames']


def x8(frames, box, fire):
    tiles = [on_bg(f, box, 4) for f in frames]   # @2x × 4 = 1x × 8
    tw, th = tiles[0].size; cols = min(len(tiles), 6); rows = -(-len(tiles) // cols)
    sheet = Image.new('RGBA', (cols * (tw + 6) + 6, rows * (th + 20) + 6), (30, 36, 44, 255)); d = ImageDraw.Draw(sheet)
    for i, t in enumerate(tiles):
        g = ImageDraw.Draw(t)
        for gx in range(0, tw, 4): g.line([(gx, 0), (gx, th)], fill=(0, 0, 0, 24))
        for gy in range(0, th, 4): g.line([(0, gy), (tw, gy)], fill=(0, 0, 0, 24))
        x = 6 + (i % cols) * (tw + 6); y = 20 + (i // cols) * (th + 20)
        sheet.alpha_composite(t, (x, y)); d.text((x, y - 15), f'f{i}' + ('  hit' if fire is not None and i == fire else ''), fill=(255, 220, 120, 255) if i == fire else (220, 220, 220, 255))
    return sheet


def b64(data, mime):
    return f'data:{mime};base64,' + base64.b64encode(data).decode()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    html = []
    for op in NAMES:
        T = json.loads((SRC / op / 'timing.json').read_text(encoding='utf-8'))
        html.append(f'<h2>{NAMES[op]}</h2>')
        for slot, spec in T.items():
            folder = SRC / op / spec.get('same', slot)
            size = spec['size']
            frames = [stage(Image.open(p).convert('RGBA'), size) for p in sorted(folder.glob('f[0-9][0-9].png'))]
            durs = durations(spec)
            of, od = old_frames(op, slot)
            box = union(frames + (of or []))
            k = 2
            g1 = gif(frames, durs, box, k); g4 = gif(frames, durs, box, k, 4)
            sheet = x8(frames, union(frames), spec.get('fire'))
            name = f'{op}_{slot}'
            (OUT / f'{name}.gif').write_bytes(g1); (OUT / f'{name}_slow.gif').write_bytes(g4); sheet.convert('RGB').save(OUT / f'{name}_x8.png')
            og = gif(of, od, box, k) if of else None
            if og: (OUT / f'{name}_old.gif').write_bytes(og)
            total = sum(durs)
            note = SRC_NOTE.get((op, slot), '新做（Spine 原生骨骼 + 部件）' if spec['src'].startswith('spine') else '原作 ' + spec['src'].split(':')[1])
            t = f'{len(frames)} 帧 · 一遍 {total:.2f} 秒' + (f' · 出手 {spec["fire_time"]:.3f} 秒（与现版相同）' if 'fire_time' in spec else '') + f' · 画布 {size // 2}'
            html.append(f'<section><h3>{LABEL.get(slot, slot)}</h3><p class="m">{note} · {t}</p><div class="row">'
                        f'<figure><img src="{b64(g1, "image/gif")}"><figcaption>常速</figcaption></figure>'
                        f'<figure><img src="{b64(g4, "image/gif")}"><figcaption>慢放 ×4</figcaption></figure>'
                        + (f'<figure><img src="{b64(og, "image/gif")}"><figcaption>现版（旧 48）</figcaption></figure>' if og else '')
                        + f'</div><details><summary>8 倍逐帧</summary><img class="x8" src="{b64(png(sheet), "image/png")}"></details></section>')
    page = PAGE.replace('{{BODY}}', '\n'.join(html))
    (OUT / 'review.html').write_text(page, encoding='utf-8')
    print('ok', OUT / 'review.html', round(len(page) / 1e6, 2), 'MB')


PAGE = '''<!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>凯尔希流明艾丽妮候选</title>
<style>
:root{--bg:#f4f5f7;--fg:#1d232b;--mute:#5d6875;--card:#fff;--line:#d9dee5}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15191f;--fg:#e6e9ee;--mute:#9aa5b1;--card:#1e242c;--line:#2c343e}}
:root[data-theme="dark"]{--bg:#15191f;--fg:#e6e9ee;--mute:#9aa5b1;--card:#1e242c;--line:#2c343e}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;padding:16px;max-width:1100px;margin:auto}
h1{font-size:20px}h2{margin-top:32px;border-bottom:1px solid var(--line);padding-bottom:4px}h3{margin:0 0 2px;font-size:16px}
section{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px;margin:12px 0}
.m{color:var(--mute);margin:0 0 8px;font-size:13px}.row{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end}
figure{margin:0}figure img{image-rendering:pixelated;max-width:100%;display:block}figcaption{font-size:12px;color:var(--mute)}
img.x8{image-rendering:pixelated;max-width:100%;margin-top:8px}summary{cursor:pointer;color:var(--mute);font-size:13px;margin-top:8px}
.n{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 14px;font-size:14px}
</style></head><body>
<h1>凯尔希（本体）/ 流明 / 艾丽妮 动作候选</h1>
<div class="n">64 画布 @2x（超界的槽用 96 / 128 加边，人物尺寸不变）。常速按游戏内时序播；普攻 / 技能的出手时刻与现版相同。Mon3tr 不在本批。<br>
需要确认：① 流明原作骨架里的灯挂在提包上，手里拿的是带金色伞尖的长柄伞，所以“举灯瞄准”做成举伞尖瞄准（光弹从伞尖出）；如要手提灯，需 Codex 补「手持提灯」部件。② 艾丽妮 S3 持续段原作人物是透明的，这里强制显示原作姿势（空中转身连射）。③ 艾丽妮 S1 / S2 / S3 起手去掉了原作刀光（刀光由现有特效出）。</div>
{{BODY}}
</body></html>'''

if __name__ == '__main__':
    main()
