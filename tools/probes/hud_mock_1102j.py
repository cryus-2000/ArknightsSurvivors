"""docs/222 §12.3：队友生命回到左上（用户 11-02「为什么不跟之前一样把队友生命放在左上角，或者等他们突击的时候才显示在左上角」）。
左上队长读数下面三行：名字 + 细条 + 数字；突击时常显，随行 / 部署 / 集火时只在有人受伤（<100%）或倒地时显示，满血自动收起。
编队卡只留全身立绘 + 名牌。出：突击态电脑 / 手机、随行态电脑（左上收起）、左上两态对照放大。
用法：python hud_mock_1102j.py <worktree> <输出目录>"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hud_mock_1102 as H
import hud_mock_1102h as E
import hud_mock_1102i as Q
from hud_mock_1102 import M, C, TEXT, SUB, CYAN, GOLD, OPS
from PIL import Image, ImageDraw

OUT = sys.argv[2]
HPN = Q.HPN


def mates_hp(m, x, y, phone=False):
    """左上：队友三行（名字 / 细条 / 数字），左边一根竖线连着队长块"""
    w = 150 if not phone else 120
    E.hair(m, (x + 30, y - 6), (x + 30, y + 3 * 15 - 4), E.LINE2)
    for k, (nm, cls, hp) in enumerate(OPS[1:]):
        yy = y + k * 15
        col = (70, 225, 240, 255) if hp > 0.5 else (GOLD if hp > 0.25 else (255, 61, 139, 255))
        m.rect(x + 36, yy - 7, 2, 8, H.CLS[cls])
        m.text(x + 42, yy, nm[:4], 9, (225, 228, 228, 240))
        E.line_bar(m, x + 92, yy - 4, w - 52, hp, col, h=2)
        m.text(x + 92 + w - 46, yy, str(HPN[k + 1]), 8.5, col, bold=True)
    return 3 * 15


def squad_cards_only(m, x, y, mode, phone=False):
    """编队区：四格指挥 + 全身立绘 + 名牌（不再画生命）"""
    k = 1.0 if not phone else 0.75     # 手机立绘框放大 1.5 倍（docs/222 §15.1，用户「人物的框有点小」）
    cw = 80 * k / m.s + (14 if not phone else 4)
    ch = 92 * k / m.s
    gap = 6
    W = 4 * cw + 3 * gap
    nh = 15 if not phone else 6
    E.shade(m, x - 10, y - 10, W + 20, ch + nh + 50, 0.36)
    E.cap(m, x, y + 6, 'COMMAND' + ('  ·  F' if not phone else ''), 6.5)
    E.cap(m, x + W, y + 6, 'SQUAD 4/4', 6.5, anchor='r')
    E.cap(m, x + W - E.cap(m, -999, -999, 'SQUAD 4/4', 6.5) - 12, y + 6, 'BOND 2', 6.5, GOLD, anchor='r')
    Q.segmented(m, x, y + 10, W, mode, ['随行', '突击', '部署', '集火'], phone)
    oy = y + (40 if not phone else 36)
    for i, (nm, cls, hp) in enumerate(OPS):
        cx0 = x + i * (cw + gap)
        m.rect(cx0, oy, cw, ch, (10, 12, 14, 205))
        Q.body(m, cx0, oy, cw, ch, i, k)
        m.rect(cx0, oy, cw, 1.5, H.CLS[cls])
        if i in (1, 2):
            H.M.diamond(m, cx0 + cw - 5, oy + 6, 2.6, GOLD)
        lead = i == 0
        E.plate(m, cx0, oy + ch, cw, nh, E.PAPER if lead else E.INK, 0.95)
        if not phone:
            m.text(cx0 + cw / 2, oy + ch + 11, nm[:4], 9, (14, 16, 18, 255) if lead else TEXT, anchor='ms', bold=True)
        if lead:
            E.plate(m, cx0, oy - 10, 34, 10, E.INK)
            E.cap(m, cx0 + 3, oy - 2.5, 'LEADER', 5, TEXT, 0.8)


def frame(phone, mode, show_mates, name):
    m = M(H.PH_BG if phone else H.DESK_BG, 1.25 if phone else 1.5)
    W, Hh = m.W, m.H
    lx, ly = (14, 10) if phone else (20, 14)
    E.leader(m, lx, ly, phone=phone)
    sy = ly + 82
    if show_mates:
        sy += mates_hp(m, lx, ly + 98, phone) + 18
        cw_ = E.cap(m, lx + 36, ly + 84, 'SQUAD HP', 5.5, CYAN if mode == 1 else E.SUB)
        if mode == 1:
            m.text(lx + 36 + cw_ + 6, ly + 84.5, '突击中', 8, CYAN)
        sy += 8
    E.status(m, lx, sy + 14, phone=phone)
    E.top_bar(m, 6 if phone else 10, compact=phone)
    E.info(m, phone=phone)
    if phone:
        H.phone_buttons(m, ['随行', '突击', '部署', '集火'][mode], speed=False, pause=False)
        cw = 60 / 1.25 + 4
        squad_cards_only(m, W - 16 - (4 * cw + 18), Hh - 12 - (36 + 69 / 1.25 + 6), mode, phone=True)
        H.minimap(m, 10, Hh - 10 - 84, 84)
    else:
        cw = 80 / 1.5 + 14
        squad_cards_only(m, W - 24 - (4 * cw + 18), Hh - 24 - (40 + 92 / 1.5 + 15), mode)
        H.minimap(m, 16, Hh - 16 - 130, 130)
        H.key_hints(m)
    title = '队友生命回到左上 · %s（%s）' % (['随行', '突击', '部署', '集火'][mode] + ('：队友生命显示' if show_mates else '：满血收起'), '手机横屏' if phone else '电脑 1920×1080')
    return m.done(os.path.join(OUT, name), title)


if __name__ == '__main__':
    a = frame(False, 1, True, 'R10_assault_desktop.png')
    b = frame(True, 1, True, 'R10_assault_phone.png')
    c = frame(False, 0, False, 'R10_follow_desktop.png')
    # 左上两态对照（2 倍）
    A = a.convert('RGB').crop((0, 48, 640, 48 + 330)).resize((1280, 660), Image.NEAREST)
    C_ = c.convert('RGB').crop((0, 48, 640, 48 + 330)).resize((1280, 660), Image.NEAREST)
    out = Image.new('RGB', (1280 * 2 + 16, 660 + 50), (12, 14, 18))
    out.paste(C_, (0, 50))
    out.paste(A, (1296, 50))
    d = ImageDraw.Draw(out)
    d.text((16, 25), '随行（队友满血）：左上只有队长', font=H.FBF(24), fill=(255, 236, 170), anchor='lm')
    d.text((1312, 25), '突击（或有人受伤 / 倒地）：队长下面多三行队友生命', font=H.FBF(24), fill=(255, 236, 170), anchor='lm')
    out.save(os.path.join(OUT, 'R10_topleft_compare.png'))
    print('ok')
