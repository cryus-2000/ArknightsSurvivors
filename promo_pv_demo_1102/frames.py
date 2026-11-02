# 关键帧拼图：每镜一帧（终结技镜头取冲击帧后 4 帧，其余取中间），5×3，每格 640×360 + 时间码
import sys
from PIL import Image, ImageDraw
import pv
from fx import font
pick = {"open": 1.644 + 0.13, "ult_tx": 21.372 + 0.13, "ult_mz": 27.126 + 0.13, "squad": None}
sh = Image.new("RGB", (640 * 5, 390 * 3), (0, 0, 0))
d = ImageDraw.Draw(sh)
for j, (a, b, kind, arg) in enumerate(pv.TL):
    t = pick.get(arg) or (a + b) / 2
    if arg == "title": t = b - 1.2
    if arg == "squad" and kind == "card": t = b - 0.3
    im = pv.Image.fromarray(pv.render(pv.fr(t))).resize((640, 360))
    x, y = (j % 5) * 640, (j // 5) * 390
    sh.paste(im, (x, y + 30))
    d.text((x + 8, y + 4), "%d  %.2f–%.2f s  %s" % (j + 1, a, b, arg or kind), font=font(20), fill=(230, 236, 240))
sh.save(sys.argv[1])
