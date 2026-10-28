"""Focused export regressions; run with python -m unittest discover -s tools -p test_web_audio.py."""
from pathlib import Path
import tempfile
import unittest

import numpy as np
import soundfile as sf

import web_audio
from web import engine_patch


class WebAudioTests(unittest.TestCase):
    def test_export_preserves_stereo_duration_and_layer_alignment(self):
        with tempfile.TemporaryDirectory() as tmp:
            music = Path(tmp) / 'audio/music'
            music.mkdir(parents=True)
            rate, frames = 32000, 96007
            t = np.arange(frames) / rate
            x = np.column_stack((0.3 * np.sin(t * 440 * 2 * np.pi),
                                 0.2 * np.sin(t * 700 * 2 * np.pi))).astype('float32')
            for layer in ('base', 'pulse', 'drive'):
                (music / f'suno_battle1_{layer}.ogg').write_bytes(web_audio.encode(x, rate, 0.1))
            before = sum(p.stat().st_size for p in music.iterdir())
            stat = web_audio.shrink(tmp, 'B')
            infos = [sf.info(p) for p in music.iterdir()]
            self.assertEqual({i.samplerate for i in infos}, {24000})
            self.assertEqual({i.channels for i in infos}, {2})
            self.assertEqual(len({i.frames for i in infos}), 1)
            self.assertTrue(all(abs(i.duration - frames / rate) <= 1 / 24000 for i in infos))
            self.assertLess(stat['music'][1], before)

    def test_engine_patch_is_idempotent_and_shares_samples(self):
        source = engine_patch.ANCHOR + 'getAudioBuffer(){return this._duplicateAudioBuffer()}'
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'index.js'
            p.write_text(source)
            engine_patch.patch_index_js(str(p))
            once = p.read_text()
            self.assertIn('getAudioBuffer(){return this._audioBuffer}', once)
            engine_patch.patch_index_js(str(p))
            self.assertEqual(p.read_text(), once)

    def test_unknown_engine_fails_without_partial_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'index.js'
            p.write_text(engine_patch.ANCHOR)
            with self.assertRaises(SystemExit):
                engine_patch.patch_index_js(str(p))
            self.assertEqual(p.read_text(), engine_patch.ANCHOR)

    def test_existing_export_upgrades_without_duplicate_hooks(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'index.js'
            p.write_text(engine_patch.ANCHOR + engine_patch.LEGACY_INJECT + engine_patch.COPY)
            engine_patch.patch_index_js(str(p))
            self.assertEqual(p.read_text().count('window.__syAudioFree=function'), 1)
            self.assertIn(engine_patch.SHARE, p.read_text())
            self.assertNotIn(engine_patch.LEGACY_INJECT, p.read_text())

    def test_all_release_presets_include_layer_metadata(self):
        from encrypted_release import encrypted_preset
        source = (Path(__file__).resolve().parents[1] / 'game/export_presets.cfg').read_text(encoding='utf-8')
        for text in (source, encrypted_preset(source, 'test-template.exe')):
            filters = [line for line in text.splitlines() if line.startswith('include_filter=')]
            self.assertTrue(filters)
            self.assertTrue(all('audio/music/*.json' in line for line in filters))
            self.assertTrue(all('art/index.json' in line for line in filters))   # 运行时贴图索引（docs/189 §6.1）


if __name__ == '__main__':
    unittest.main()
