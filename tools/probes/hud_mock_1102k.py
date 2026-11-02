"""docs/222 §14：手机按键 · 编辑式（用户 11-02「先补手机按键稿」）。
位置 / 点击区沿用 touch_layout.default_center（手机）：冲刺、终结技（技能键位置）、瞄准、指挥、属性；暂停 / 倍速已在右上信息条，不再占按键列。
造型：暗底圆 + 1 像素发丝圈；中文字 + 极小字距英文（DASH / ULT / AIM / CMD / INFO）；
终结技外圈一道青色能量弧，充满时整颗反白成纸白（和倍速提醒同一个「反白 = 要你注意」）；冲刺的两格充能是圈下沿两颗点；按下时圈变青。
出：整屏（突击态）+ 按键状态放大。用法：python hud_mock_1102k.py <worktree> <输出目录>"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102h as E
import hud_mock_1102j as J
from hud_mock_1102 import M, C, TEXT, SUB, CYAN
from PIL import Image, ImageDraw

OUT = sys.argv[2]
BTN = 46.0
DARK = (10, 12, 14, 175)
RING = (255, 255, 255, 105)
INK = E.INK
PAPER = E.PAPER


def layout(W, Hh):
    """touch_layout.default_center 的手机分支（SQUAD_TOP_UP 196，瞄准键显示）"""
    dash = (W - 134.0, Hh - 196.0 - 14.0 - BTN * 0.7)
    return {
        'dash': (dash, BTN * 0.7),
        'ult': ((dash[0] - BTN * 1.85, dash[1] - BTN * 1.85), BTN * 0.85),
        'aim': ((dash[0] - BTN * 1.85, dash[1] - BTN * 0.05), BTN * 0.62),
        'cmd': ((W - 46.0 - 72.0, 160.0), BTN / 2),
        'info': ((W - 46.0, 160.0 + 86.0), BTN / 2),
    }


def ring(m, c, r, col=RING, w=1.0):
    m.d.ellipse(m.R(c[0] - r, c[1] - r, 2 * r, 2 * r), outline=col, width=max(1, m.P(w)))


def disc(m, c, r, fill):
    m.d.ellipse(m.R(c[0] - r, c[1] - r, 2 * r, 2 * r), fill=fill)


def arc(m, c, r, frac, col, w=2.5):
    if frac <= 0:
        return
    m.d.arc(m.R(c[0] - r, c[1] - r, 2 * r, 2 * r), -90, -90 + 360 * frac, fill=col, width=max(1, m.P(w)))


def label(m, c, cn, en, r, ink=TEXT, sub=SUB):
    sz = 13 if r > 34 else (12 if r > 26 else 10.5)
    m.text(c[0], c[1] + sz * 0.25, cn, sz, ink, anchor='ms', bold=True)
    E.cap(m, c[0], c[1] + sz * 0.25 + 10, en, 5.2, sub, 1.0, anchor='m')


def button(m, key, c, r, state=None):
    st = state or {}
    pressed = st.get('pressed', False)
    if key == 'ult':
        e = st.get('energy', 0.62)
        if e >= 1.0:
            disc(m, c, r, PAPER)
            ring(m, c, r + 4, (PAPER[0], PAPER[1], PAPER[2], 90), 1)
            label(m, c, '终结技', 'ULT · READY', r, INK, (80, 80, 80, 255))
            return
        disc(m, c, r, DARK)
        ring(m, c, r, RING)
        ring(m, c, r + 4, (255, 255, 255, 30), 2.5)
        arc(m, c, r + 4, e, CYAN, 2.5)
        label(m, c, '终结技', 'ULT  %d%%' % int(e * 100), r)
        return
    disc(m, c, r, (40, 60, 64, 200) if pressed else DARK)
    ring(m, c, r, CYAN if pressed else RING, 1.4 if pressed else 1.0)
    if key == 'dash':
        n = st.get('charges', 2)
        for k in range(2):
            a = math.radians(90 + (k - 0.5) * 22)
            p = (c[0] + math.cos(a) * (r - 6), c[1] + math.sin(a) * (r - 6))
            disc(m, p, 2.4, CYAN if k < n else (255, 255, 255, 45))
        if n < 2:
            arc(m, c, r + 3, st.get('cd', 0.4), (255, 255, 255, 120), 1.5)
        label(m, (c[0], c[1] - 3), '冲刺', 'DASH', r)
    elif key == 'aim':
        label(m, c, '瞄准', 'AIM', r)
    elif key == 'cmd':
        label(m, c, st.get('mode', '突击'), 'CMD', r, CYAN)
    elif key == 'info':
        label(m, c, '属性', 'INFO', r)


def phone_buttons(m, cmd='突击', speed=False, pause=False):
    # 真机手机界面按 1170×540 逻辑像素 1:1 画；效果稿画布是 ×1.25 的设计单位，所以位置 / 半径按屏幕像素算再除回去
    lay = layout(m.W * m.s, m.H * m.s)
    for k, (c, r) in lay.items():
        button(m, k, (c[0] / m.s, c[1] / m.s), r / m.s, {'mode': cmd})


H.phone_buttons = phone_buttons


def states():
    bg = H.PH_BG.crop((600, 60, 1170, 400)).resize((1710, 1020))
    m = M(bg, 3.0)
    m.rect(0, 0, m.W, m.H, C(0.01, 0.02, 0.03, 0.45))
    items = [('ult', 39, {'energy': 0.62}, '终结技 · 充能中（外圈青色能量弧）'),
             ('ult', 39, {'energy': 1.0}, '终结技 · 充满（整颗反白）'),
             ('dash', 32, {'charges': 2}, '冲刺 · 2 格'),
             ('dash', 32, {'charges': 1, 'cd': 0.4}, '冲刺 · 1 格 + 充能弧'),
             ('aim', 28.5, {'pressed': True}, '按住 · 圈变青'),
             ('cmd', 23, {'mode': '突击'}, '指挥 · 当前模式'),
             ('info', 23, {}, '属性')]
    for i, (k, r, st, cap_) in enumerate(items):
        cx = 70 + (i % 4) * 140
        cy = 90 + (i // 4) * 170
        button(m, k, (cx, cy), r, st)
        m.text(cx, cy + 66, cap_, 7.5, C(0.95, 0.93, 0.85), anchor='ms')
    return m.done(os.path.join(OUT, 'R12_buttons_states.png'), '手机按键 · 编辑式 · 状态放大（3 倍）')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    J.frame(True, 1, True, 'R12_phone_buttons.png')
    states()
    print('ok')
