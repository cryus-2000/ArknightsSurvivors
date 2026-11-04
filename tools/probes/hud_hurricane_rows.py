"""手画马灯像素行（用户 11-05「灯的 AI 感有点强」→ 不用生图底图，按几何规则逐像素画，干净、少色、1 像素轮廓）。
输出 pixelfx 的 p.sprite 行：BODY（铁框 / 油壶 / 灯罩顶，玻璃处留空）、WIRE（压在玻璃上的护网）、GLASS（玻璃范围，运行时按灯火着色）。
字符：o 轮廓 d 暗铁 m 中铁 l 亮铁 h 高光 b 暗铜 B 铜 Y 亮铜 g 玻璃 w 护网。
用法：python hud_hurricane_rows.py > rows.js"""
import math

W, H = 25, 44
CX = 12
grid = [['.'] * W for _ in range(H)]
glass = [['.'] * W for _ in range(H)]
wire = [['.'] * W for _ in range(H)]


def put(g, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = c


def span(y, x0, x1, c, g=grid):
    for x in range(x0, x1 + 1):
        put(g, x, y, c)


G0, G1 = 17, 33          # 玻璃罩行


def hw(y):
    t = (y - G0) / (G1 - G0)
    return 2.6 + 5.8 * math.sin(math.pi * t) ** 0.7


# 提手：上半椭圆，左亮右暗
for a10 in range(0, 1800):
    a = math.pi + a10 / 1800 * math.pi
    x = CX + math.cos(a) * 11.2
    y = 11.5 + math.sin(a) * 9.5
    put(grid, round(x), round(y), 'l' if x < CX - 2 else ('m' if x < CX + 3 else 'd'))
for x, y in ((CX - 1, 0), (CX, 0), (CX + 1, 0)):
    put(grid, x, y, 'h' if x < CX else 'l')
# 灯罩顶（穹顶 + 通气口 + 铜圈）
cap = [(8, 2, 'o'), (9, 3, 'm'), (10, 5, 'm'), (11, 7, 'm'), (12, 8, 'm'), (13, 9, 'm'), (14, 10, 'm'), (15, 10, 'B'), (16, 7, 'd')]
for y, half, c in cap:
    span(y, CX - half, CX + half, c)
    if c not in 'oB':
        put(grid, CX - half, y, 'o'); put(grid, CX + half, y, 'o')
        for x in range(CX - half + 1, CX - half + 1 + max(1, half // 2)):
            put(grid, x, y, 'l')
        put(grid, CX - half + 1, y, 'h')
        put(grid, CX + half - 1, y, 'd')
span(15, CX - 9, CX - 6, 'Y')
span(9, CX - 2, CX + 2, 'd'); put(grid, CX, 8, 'd')
# 侧管：灯罩顶两侧落到油壶
for y in range(15, 35):
    inset = 1 if y < 18 else 0          # 顶上往里收一点，和穹顶接上
    for x, c in ((1 + inset, 'o'), (2 + inset, 'l'), (22 - inset, 'd'), (23 - inset, 'o')):
        put(grid, x, y, c)
# 玻璃罩
for y in range(G0, G1 + 1):
    h = hw(y)
    x0, x1 = round(CX - h), round(CX + h)
    for x in range(x0, x1 + 1):
        put(glass, x, y, 'g')
    put(grid, x0 - 1, y, 'o'); put(grid, x1 + 1, y, 'o')
# 玻璃上下两道颈圈
span(G0 - 1, CX - 4, CX + 4, 'd'); put(grid, CX - 4, G0 - 1, 'o'); put(grid, CX + 4, G0 - 1, 'o'); span(G0 - 1, CX - 3, CX - 2, 'l')
span(G1 + 1, CX - 5, CX + 5, 'd'); put(grid, CX - 5, G1 + 1, 'o'); put(grid, CX + 5, G1 + 1, 'o')
# 护网：两根竖丝随罩身外鼓 + 中腰一圈
for y in range(G0 + 1, G1):
    h = hw(y)
    for s in (-1, 1):
        put(wire, round(CX + s * h * 0.55), y, 'w')
for x in range(round(CX - hw(25)), round(CX + hw(25)) + 1):
    put(wire, x, 25, 'w')
# 油壶
tank = [(34, 9, 'B'), (35, 10, 'l'), (36, 11, 'm'), (37, 11, 'm'), (38, 11, 'm'), (39, 10, 'm'), (40, 9, 'd'), (41, 7, 'o')]
for y, half, c in tank:
    span(y, CX - half, CX + half, c)
    if c not in 'oB':
        put(grid, CX - half, y, 'o'); put(grid, CX + half, y, 'o')
        if c in 'lm':
            span(y, CX - half + 1, CX - half + 3, 'l' if c == 'm' else 'h')
            put(grid, CX + half - 1, y, 'd')
span(34, CX - 8, CX - 5, 'Y')
put(grid, CX - 9, 34, 'b'); put(grid, CX + 9, 34, 'b')
span(37, CX - 7, CX - 7, 'h')
# 调芯旋钮（铜）
for x, y, c in ((CX + 6, 38, 'Y'), (CX + 7, 38, 'B'), (CX + 6, 39, 'B'), (CX + 7, 39, 'b')):
    put(grid, x, y, c)
# 灯芯座
span(G1, CX - 1, CX + 1, 'd')


def rows(g):
    return ',\n  '.join('"%s"' % ''.join(r) for r in g)


print('export const BODY = [\n  %s,\n];' % rows(grid))
print('export const GLASS = [\n  %s,\n];' % rows(glass))
print('export const WIRE = [\n  %s,\n];' % rows(wire))
print('export const W = %d, H = %d, CX = %d, G0 = %d, G1 = %d;' % (W, H, CX, G0, G1))
