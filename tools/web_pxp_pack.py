"""Pack transparent borders of Web export pixel FX; coordinates stay in original frame units."""
import json
from pathlib import Path

from PIL import Image

# Owners whose runtime metadata keys have a prefix added in fx_pxplane._meta().
PREFIX = {
    "angelina": "an", "eyjafjalla": "ey", "exusiai": "ex", "gladiia": "gl",
    "irene": "ir", "kaltsit": "ka", "logos": "lg", "lumen": "lm", "lappland": "lp",
    "saria": "sa", "skalter": "sk", "specter_unchained": "su", "suzuran": "sz",
    "ulpianus": "ul", "wisadel": "wd",
}
UNPREFIXED = {"hoshiguma", "mizuki", "siege", "skadi", "texas"}


def _arrange(length, margins):
    # Join pairs that share the widest transparent border. All windows stay
    # full-size. Their alpha is identical throughout each overlap.
    chains = [[i] for i in range(len(margins))]
    while len(chains) > 1:
        best = (-1, 0, 0)
        for i, a in enumerate(chains):
            for j, b in enumerate(chains):
                if i != j:
                    overlap = min(margins[a[-1]][1], margins[b[0]][0])
                    if overlap > best[0]:
                        best = (overlap, i, j)
        _, i, j = best
        chains[i].extend(chains[j])
        chains.pop(j)
    offsets = [0] * len(margins)
    end = 0
    previous = None
    for i in chains[0]:
        if previous is not None:
            end -= min(margins[previous][1], margins[i][0])
        offsets[i] = end
        end += length
        previous = i
    return end, offsets


def pack_strip(image, w, h, n):
    if image.size != (w * n, h) or image.width * h * 4 < 65536:
        return None
    unique = {}
    frames, ids, mx, my = [], [], [], []
    for i in range(n):
        frame = image.crop((i * w, 0, (i + 1) * w, h))
        pixels = frame.tobytes()
        if pixels not in unique:
            unique[pixels] = len(frames)
            frames.append(frame)
            box = frame.getchannel("A").getbbox()
            mx.append((box[0], w - box[2]) if box else (w, w))
            my.append((box[1], h - box[3]) if box else (h, h))
        ids.append(unique[pixels])
    width, xs = _arrange(w, mx)
    height, ys = _arrange(h, my)
    vertical = height <= max(4096, image.width, image.height) and w * height < width * h
    size, offsets = ((w, height), ys) if vertical else ((width, h), xs)
    if size[0] * size[1] > image.width * h * 0.9:
        return None
    atlas = Image.new("RGBA", size)
    for frame, pos in zip(frames, offsets):
        atlas.paste(frame, (0, pos) if vertical else (pos, 0))
    # A signed offset specifies either axis, including the shared origin.
    return atlas, [-offsets[i] if vertical else offsets[i] for i in ids]


def make(gamedir):
    root = Path(gamedir)
    count = saved = 0
    for owner in sorted(set(PREFIX) | UNPREFIXED):
        path = root / "data" / ("pxp_%s.json" % owner)
        if not path.exists():
            continue
        entries = json.loads(path.read_text(encoding="utf8"))
        changed = False
        for key, entry in entries.items():
            if not isinstance(entry, dict) or "w" not in entry or "frame_offsets" in entry:
                continue
            name = (PREFIX[owner] + "_" if owner in PREFIX else "") + key
            png = root / "art/fx/pxp" / ("pxp_%s.png" % name.replace("_d-", "_dm").lower())
            if not png.is_file():
                continue
            with Image.open(png) as src:
                if src.width * src.height * 4 < 65536:
                    continue
                image = src.convert("RGBA")
            result = pack_strip(image, entry["w"], entry["h"], entry["n"])
            if result:
                atlas, entry["frame_offsets"] = result
                atlas.save(png)
                saved += (image.width * image.height - atlas.width * atlas.height) * 4
                count += 1
                changed = True
        if changed:
            path.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")), encoding="utf8")
    return count, saved
