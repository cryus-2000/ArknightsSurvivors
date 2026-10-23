"""Focused regressions for 1x canvas preservation and legacy iris registration."""
import tempfile
import unittest
import json
from unittest.mock import patch
import make_op_1x as exporter
from pathlib import Path
from PIL import Image
from make_op_1x import compose, skalter_fallback_eyes


class FaceExportTests(unittest.TestCase):
    def test_native_failure_does_not_replace_approved_asset(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "test").mkdir()
            (root / "test" / "test_info.json").write_text("{}")
            (root / "test.json").write_text(json.dumps({"sprites": {"run": {"tex": "op_test_run", "frames": 8}}}))
            Image.new("RGBA", (1024, 128)).save(root / "op_test_run@2x.png")
            target = root / "op_test_run@1x.png"
            target.write_bytes(b"approved asset sentinel")
            with patch.multiple(exporter, CHARS=tmp, CFG=tmp, REF=tmp, INC=tmp), patch.object(exporter, "info", return_value={"Run": {"dur": 1}}), patch.object(exporter, "write_cfg", return_value="unused"), patch.object(exporter, "run_node", side_effect=ValueError("left/top overflow")):
                with self.assertRaisesRegex(RuntimeError, "existing assets preserved"):
                    exporter.build_op("test")
            self.assertEqual(target.read_bytes(), b"approved asset sentinel")

    def test_overflow_preserves_pixels_without_moving_foot(self):
        with tempfile.TemporaryDirectory() as tmp:
            frame = Image.new("RGBA", (96, 96))
            frame.putpixel((70, 64), (100, 150, 200, 255))
            frame.save(Path(tmp) / "f00.png")
            out = compose(tmp, 1, 64, 64, [32, 60], [32, 60])
            self.assertEqual(out.size, (72, 66))
            self.assertEqual(out.getpixel((70, 64)), (100, 150, 200, 255))
            self.assertEqual(sum(a > 0 for a in out.getchannel("A").getdata()), 1)

    def test_left_clip_requires_anchor_review(self):
        with tempfile.TemporaryDirectory() as tmp:
            frame = Image.new("RGBA", (96, 96))
            frame.putpixel((0, 40), (100, 150, 200, 255))
            frame.save(Path(tmp) / "f00.png")
            with self.assertRaises(ValueError):
                compose(tmp, 1, 64, 64, [32, 60], [48, 60])

    def test_legacy_iris_keeps_occlusion_and_costume(self):
        im = Image.new("RGBA", (512, 64))
        im.putpixel((32, 32), (146, 28, 34, 255))
        im.putpixel((36, 32), (30, 30, 30, 255))  # dark occluder
        im.putpixel((32, 38), (146, 28, 34, 255))  # same red in scarf
        out = skalter_fallback_eyes(im, "run")
        self.assertEqual(out.getpixel((32, 32)), (203, 53, 70, 255))
        self.assertEqual(out.getpixel((36, 32)), im.getpixel((36, 32)))
        self.assertEqual(out.getpixel((32, 38)), im.getpixel((32, 38)))
        self.assertEqual(out.getchannel("A").tobytes(), im.getchannel("A").tobytes())


if __name__ == "__main__":
    unittest.main()
