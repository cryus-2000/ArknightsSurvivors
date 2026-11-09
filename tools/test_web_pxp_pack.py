"""Verify actual battle FX keep the same visible texels after Web atlas packing."""
from pathlib import Path
import json

import numpy as np
from PIL import Image

from web_pxp_pack import pack_strip


def main():
    game = Path(__file__).resolve().parents[1] / "game"
    metadata = json.loads((game / "data/pxp_skadi.json").read_text(encoding="utf8"))
    for key, vertical in (("backwash_up", False), ("s1_e1_gd_d0", True)):
        entry = metadata[key]
        w, h, n = (entry[k] for k in ("w", "h", "n"))
        with Image.open(game / "art/fx/pxp" / ("pxp_%s.png" % key)) as src:
            original = src.convert("RGBA")
        atlas, offsets = pack_strip(original, w, h, n)
        assert len(offsets) == n and any(p < 0 for p in offsets) == vertical
        for i, pos in enumerate(offsets):
            x, y = max(pos, 0), max(-pos, 0)
            expected = np.asarray(original.crop((i * w, 0, (i + 1) * w, h)))
            actual = np.asarray(atlas.crop((x, y, x + w, y + h)))
            assert np.array_equal(expected[..., 3], actual[..., 3])
            visible = expected[..., 3] != 0
            assert np.array_equal(expected[visible], actual[visible])
    print("Web PXP horizontal and vertical full-frame regions verified")


if __name__ == "__main__":
    main()
