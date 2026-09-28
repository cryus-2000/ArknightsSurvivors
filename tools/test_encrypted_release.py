import unittest, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import encrypted_release as enc

class EncryptionContracts(unittest.TestCase):
    def test_missing_key_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(FileNotFoundError): enc.load_key(Path(d)/'absent')
    def test_invalid_key_rejected_without_echo(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'key'; p.write_text('private-invalid-value')
            with self.assertRaisesRegex(ValueError, '^Encryption key must be 64 hexadecimal characters$'): enc.load_key(p)
    def test_only_windows_preset_is_changed(self):
        original='[preset.0]\nname="Windows Desktop"\nencrypt_pck=false\nexclude_filter="addons/*, art/incoming/*"\n[preset.0.options]\ncustom_template/release=""\n[preset.1]\nname="Web"\nencrypt_pck=false\n'
        result=enc.encrypted_preset(original, Path('C:/private/template.exe'))
        self.assertIn('encrypt_pck=true', result.split('[preset.1]')[0])
        self.assertIn('exclude_filter="addons/*,tests/*"', result)
        self.assertEqual(result.split('[preset.1]')[1], original.split('[preset.1]')[1])
        self.assertIn('encryption_include_filters="*"', result)
        self.assertIn('encrypt_directory=true', result)
    def test_plain_pck_is_rejected(self):
        import struct
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'x.pck'; p.write_bytes(b'GDPC'+struct.pack('<IIIII',3,4,7,2,0))
            with self.assertRaisesRegex(ValueError, 'directory is not encrypted'): enc.check_encrypted_pck(p)

    def test_default_and_ea_require_encryption_before_staging(self):
        from unittest.mock import patch
        import export_build
        for arguments in ([], ['--ea'], ['--encrypted']):
            with self.subTest(arguments=arguments), patch.object(sys,'argv',['export_build.py']+arguments), patch.object(enc,'template_and_key',side_effect=RuntimeError('prerequisite check')) as prerequisites, patch.object(export_build,'run') as run:
                with self.assertRaisesRegex(RuntimeError,'prerequisite check'): export_build.main()
                prerequisites.assert_called_once()
                run.assert_not_called()

    def test_unknown_loose_resource_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/'sprite.png').write_bytes(b'not-distributable')
            with self.assertRaisesRegex(ValueError,'Unexpected loose files'): enc.check_distribution(Path(d))

if __name__=='__main__': unittest.main()
