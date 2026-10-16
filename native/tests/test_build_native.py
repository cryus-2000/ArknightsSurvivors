import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_native as build
import check


class GodotBuildTests(unittest.TestCase):
    def test_uses_shared_runner_and_dummy_audio(self):
        with patch.object(build.GR, "find_godot", return_value="godot"), patch.object(build.GR, "run_godot", return_value=("OK", "", False)) as run:
            build.run_engine(["--import"], 20)
        run.assert_called_once_with(["godot", "--headless", "--audio-driver", "Dummy", "--import"], 20)

    def test_timeout_and_errors_fail_build(self):
        for result in [("", "", True), ("", "SCRIPT ERROR: broken", False), ("", "ERROR: cannot load extension", False)]:
            with self.subTest(result=result), patch.object(build.GR, "find_godot", return_value="godot"), patch.object(build.GR, "run_godot", return_value=result):
                with self.assertRaises(SystemExit):
                    build.run_engine(["--import"], 20)

    def test_load_probe_cannot_reuse_cached_success(self):
        with patch.object(check, "_cache_key", side_effect=AssertionError("must not cache")), patch.object(check.GR, "run_godot", return_value=("loaded", "", False)) as run:
            self.assertEqual(check._run(["godot"], 20, "native_load", cache=False), ("loaded", "", False, None))
        run.assert_called_once_with(["godot"], 20)


if __name__ == "__main__":
    unittest.main()
