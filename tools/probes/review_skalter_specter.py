"""浊心斯卡蒂 / 归溟幽灵鲨候选审阅图：每槽常速 GIF、4 倍慢放 GIF、8 倍逐帧（带网格与原点）、新旧对照总览。

读 build/op_skalter_specter/（package_skalter_specter.py 产物）与 art/incoming 旧条；输出 build/op_skalter_specter/review/。
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'build/op_skalter_specter'
OUT = SRC / 'review'
INC = ROOT / 'art/incoming'
BG = (48, 61, 77, 255)
FONT = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 14)
NAMES = {'idle': '待机', 'run': '移动', 'attack': '普攻', 'skill': '技能（S1）', 'skill_s2': 'S2', 'skill_s3': 'S3', 'death': '阵亡', 'fall': '倒下（S2 替身）',
         'doll_appear': '替身现身', 'doll_spin': '替身连斩', 'doll_vanish': '替身消散', 'idle_s3': 'S3 期间待机', 'attack_s3': 'S3 重锯环斩'}
OLD = {'skill_s2': 'skill', 'skill_s3': 'skill', 'death': None, 'doll_appear': None, 'doll_vanish': None, 'idle_s3': None, 'attack_s3': None}


def frames(path, size):
    s = Image.open(path).convert('RGBA')
    return [s.crop((i * size, 0, i * size + size, size)) for i in range(s.width // size)]


def on_stage(f, size, stage=192, origin=(96, 152), foot=None):
    """帧按原点贴到统一舞台（192，原点 96,152），新旧同尺度对照。"""
    foot = foot or ((64, 120) if size == 128 else (96, 152))
    c = Image.new('RGBA', (stage, stage), BG)
    c.alpha_composite(f, (origin[0] - foot[0], origin[1] - foot[1]))
    return c


def gif(fs, ms, path):
    fs[0].save(path, save_all=True, append_images=fs[1:], duration=ms, loop=0, disposal=2)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = json.loads((SRC / 'meta.json').read_text(encoding='utf-8'))
    old_def = {op: json.loads((ROOT / f'game/data/characters/{op}.json').read_text(encoding='utf-8'))['sprites'] for op in ('skalter', 'specter_unchained')}
    rows = []
    for key, m in meta.items():
        op, slot = key.split('.')
        size = m['canvas'] * 2
        fs = frames(SRC / f"{m['tex']}@2x.png", size)
        ms = [int(round(m['clip'] / len(fs) * 1000))] * len(fs) if m.get('clip') else [int(round(d * 1000)) for d in m.get('frame_durations', [1 / m['fps']] * len(fs))]
        ms = [max(20, x) for x in ms]
        st = [on_stage(f, size) for f in fs]
        gif(st, ms, OUT / f'{op}_{slot}.gif')
        gif(st, [x * 4 for x in ms], OUT / f'{op}_{slot}_slow.gif')
        # 8 倍逐帧：1x 逻辑像素 8 倍 = @2x 像素 4 倍；网格按 @2x 像素，红点 = 原点
        z = 4
        sheet = Image.new('RGBA', (len(fs) * (size * z + 8), size * z + 24), (30, 36, 44, 255))
        d = ImageDraw.Draw(sheet)
        for i, f in enumerate(fs):
            x0 = i * (size * z + 8)
            c = Image.new('RGBA', (size, size), BG); c.alpha_composite(f)
            sheet.paste(c.resize((size * z, size * z), Image.NEAREST), (x0, 20))
            ox, oy = (64, 120) if size == 128 else (96, 152)
            d.line([(x0, 20 + oy * z), (x0 + size * z, 20 + oy * z)], fill=(120, 140, 160, 255))
            d.rectangle([x0 + ox * z - 3, 20 + oy * z - 3, x0 + ox * z + 3, 20 + oy * z + 3], outline=(255, 60, 60, 255))
            fire = m.get('fire')
            d.text((x0 + 2, 2), f'f{i} {ms[i]}ms' + (' 出手' if fire == i else ''), fill=(255, 230, 120, 255), font=FONT)
        sheet.save(OUT / f'{op}_{slot}_x8.png')
        # 旧条
        os_ = OLD.get(slot, slot)
        oldf = []
        if os_ and os_ in old_def[op] and (INC / f"{old_def[op][os_]['tex']}@2x.png").exists():
            sp = old_def[op][os_]
            im = Image.open(INC / f"{sp['tex']}@2x.png")
            n = sp['frames']; s = im.width // n
            ft = sp.get('foot', [24, 46])
            oldf = [on_stage(fr, s, foot=(int(ft[0] * s / 48), int(ft[1] * s / 48))) for fr in frames(INC / f"{sp['tex']}@2x.png", s)]
        rows.append((key, st, oldf, ms))
    # 总览：每槽一行，左旧右新（舞台同尺度）
    W = max((len(r[1]) + len(r[2])) for r in rows) * 192 + 40
    H = len(rows) * 212
    ov = Image.new('RGBA', (W, H), (30, 36, 44, 255)); d = ImageDraw.Draw(ov)
    for j, (key, st, oldf, ms) in enumerate(rows):
        y = j * 212
        d.text((4, y + 2), f'{key}（{NAMES.get(key.split(".")[1], "")}）  旧 {len(oldf)} 帧 | 新 {len(st)} 帧 {sum(ms)}ms', fill=(255, 230, 120, 255), font=FONT)
        x = 0
        for f in oldf:
            ov.paste(f, (x, y + 18)); x += 192
        x += 40 if oldf else 0
        for f in st:
            ov.paste(f, (x, y + 18)); x += 192
    for op in ('skalter', 'specter_unchained'):
        part = [i for i, r in enumerate(rows) if r[0].startswith(op + '.')]
        ov.crop((0, part[0] * 212, W, (part[-1] + 1) * 212)).save(OUT / f'{op}_overview.png')
    for op in ('skalter', 'specter_unchained'):
        rs = [r for r in rows if r[0].startswith(op + '.')]
        cols = 4
        for tag, speed, span in (('board', 1.0, 3.0), ('board_slow', 0.25, 3.0)):
            ims = []
            step = 0.04
            for k in range(int(span / step)):
                t = k * step
                W = cols * 192; H = ((len(rs) + cols - 1) // cols) * 214
                im = Image.new('RGBA', (W, H), (30, 36, 44, 255)); dd = ImageDraw.Draw(im)
                for j, (key, st, oldf, ms) in enumerate(rs):
                    x, y = (j % cols) * 192, (j // cols) * 214
                    tot = sum(ms) / 1000.0; a = (t % tot) * 1000.0; fi = 0
                    for fi, d_ in enumerate(ms):
                        if a < d_:
                            break
                        a -= d_
                    im.paste(st[fi], (x, y + 22))
                    dd.text((x + 4, y + 2), NAMES.get(key.split('.')[1], key), fill=(255, 230, 120, 255), font=FONT)
                ims.append(im.convert('P', palette=Image.ADAPTIVE, colors=255))
            ims[0].save(OUT / f'{op}_{tag}.gif', save_all=True, append_images=ims[1:], duration=int(step * 1000 / speed), loop=0)
    print('ok', OUT)


if __name__ == '__main__':
    main()
