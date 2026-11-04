"""指挥台第六稿 · 四种小队指令对照（随行 / 突击 / 部署 / 集火）。用法同 hud_console_1105r6.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_console_1105r6 as R6
import hud_console_1105r5 as R5
import hud_console_1105 as H
import json
from PIL import Image, ImageDraw, ImageFont

BASE = sys.argv[2]
cfg = json.load(open(os.path.join(BASE, 'crops.json'), encoding='utf-8'))
H.CARD_BOXES.update({k: tuple(v) for k, v in cfg['cards'].items()})
H.BADGE_BOX = tuple(cfg['badge'])
H.EXTRA.update(cfg.get('extra', {}))
H.BASE = BASE
assets = H.load_assets()
pc = Image.open(os.path.join(BASE, 'pc.png'))
H.LEADER['lamp'] = 82
labs = ['随行：不扣作战时限，队友不受伤', '突击：出击加成 + 作战时限', '部署：同一份出击加成 + 作战时限', '集火：同一份出击加成 + 牌子上方写目标与剩余生命']
tiles = []
for i in range(4):
    H.MODE_I = i
    im, _ = R5.R4.render(pc, 1.5, 'normal', False, assets)
    tiles.append(im.crop((1240, 950, 1920, 1080)).resize((1020, 195), Image.LANCZOS))
H.MODE_I = 1
tw, th = tiles[0].size
sheet = Image.new('RGB', (tw, (th + 34) * 4), (16, 18, 22))
d = ImageDraw.Draw(sheet)
f = ImageFont.truetype(os.path.join(H.FONTS, 'ui.ttf'), 22)
for i, t in enumerate(tiles):
    d.text((14, i * (th + 34) + 4), labs[i], font=f, fill=(255, 220, 120))
    sheet.paste(t, (0, i * (th + 34) + 32))
sheet.save(os.path.join(R5.OUT, 'R6_modes.png'))
print('ok')
