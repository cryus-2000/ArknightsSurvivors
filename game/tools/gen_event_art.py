from PIL import Image, ImageDraw
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "px")
OUTLINE = (8, 14, 24, 255)

def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def outline(im, col=OUTLINE):
    w, h = im.size
    src = im.load()
    out = im.copy()
    o = out.load()
    for x in range(w):
        for y in range(h):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                        o[x, y] = col
                        break
    return out

def silhouette(im):
    w, h = im.size
    out = new(w, h)
    s, o = im.load(), out.load()
    for x in range(w):
        for y in range(h):
            if s[x, y][3] > 0:
                o[x, y] = (255, 255, 255, 255)
    return out

def strip(frames):
    w, h = frames[0].size
    s = new(w * len(frames), h)
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s

def save_enemy(name, frames):
    frames = [outline(f) for f in frames]
    strip(frames).save(f"{OUT}/{name}.png")
    strip([silhouette(f) for f in frames]).save(f"{OUT}/{name}_white.png")

def e_event(f):
    im = new(26, 30); d = ImageDraw.Draw(im)
    # 石座
    d.polygon([(2, 29), (5, 18), (20, 18), (23, 29)], fill=(38, 44, 70)); d.rectangle((6, 16, 19, 19), fill=(58, 66, 100))
    d.line((4, 26, 21, 26), fill=(26, 30, 50)); d.line((8, 22, 17, 22), fill=(26, 30, 50))
    # 珊瑚与触须装饰
    for x, h in ((3, 6), (22, 5)):
        d.line((x, 18, x - (1 if x < 13 else -1), 18 - h), fill=(120, 60, 150)); d.point((x - (1 if x < 13 else -1), 18 - h - 1), fill=(200, 120, 240))
    # 悬浮的深蓝之心（f 控制上下浮动与光芒）
    cy = 8 - f
    d.ellipse((8, cy - 3, 17, cy + 6), fill=(40, 90, 200)); d.ellipse((10, cy - 1, 15, cy + 4), fill=(120, 190, 255)); d.ellipse((11, cy, 13, cy + 2), fill=(230, 250, 255))
    for dx, dy in ((-6, 1), (6, 1), (0, -6), (0, 8)):
        d.point((12 + dx + (dx // 6) * f, cy + 1 + dy), fill=(180, 220, 255))
    return im


if __name__ == "__main__":
    save_enemy("e_event", [e_event(0), e_event(1)])
    print("event altar ok")
