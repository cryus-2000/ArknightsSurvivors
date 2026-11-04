"""指挥台第六稿：第五稿 + 马灯换成手画像素版（用户 11-05「灯的 AI 感有点强」）。
马灯：hud_hurricane_rows.py 逐像素画铁框 / 玻璃罩 / 护网 / 油壶，pixelfx fire/hud-hurricane 点火（四档），--sheet 帧条按 2 倍最近邻贴。
其余同 hud_console_1105r5.py。用法：python hud_console_1105r6.py <worktree> <底图目录> <输出目录> <pixelfx 帧条目录（sheet_<lv>.png/json）>"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
import hud_console_1105r5 as R5

SHEETS = sys.argv[4]
_cache = {}


def paste_lantern(m, x, y, level, px=1, i=5):
    lv = 90 if level >= 70 else (50 if level >= 30 else (18 if level > 0 else 0))
    if lv not in _cache:
        _cache[lv] = (Image.open(os.path.join(SHEETS, 'sheet_%d.png' % lv)).convert('RGBA'),
                      json.load(open(os.path.join(SHEETS, 'sheet_%d.json' % lv)))['meta']['pixelfx'])
    im, meta = _cache[lv]
    fw, fh = meta['frameSize']
    c = meta['columns']
    i %= meta['frames']
    fr = im.crop(((i % c) * fw, (i // c) * fh, (i % c + 1) * fw, (i // c + 1) * fh))
    px = 4 if px >= 3 else (2 if px >= 1.5 else 1)   # 只用整数倍：指挥台 2 倍，档位图 4 倍
    fr = fr.resize((fw * px, fh * px), Image.NEAREST)
    pv = meta['pivot']
    m.ov.alpha_composite(fr, (int(m.P(x) - pv[0] * px), int(m.P(y) - pv[1] * px)))


R5.paste_lantern = paste_lantern
if __name__ == '__main__':
    import builtins
    R5.main()
    out = R5.OUT
    for a, b in (('R5_pc.png', 'R6_pc.png'), ('R5_phone.png', 'R6_phone.png'), ('R5_states.png', 'R6_states.png'), ('R5_lamp.png', 'R6_lamp.png')):
        os.replace(os.path.join(out, a), os.path.join(out, b))
