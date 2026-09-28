# Windows encrypted release (2026-09-28)

Approved design: compile a private Godot 4.7.2 Windows release template with a locally generated AES-256 key; stage all release PNGs into the PCK; encrypt the PCK files and directory; distribute only executable, encrypted PCK, launcher, instructions and manifest. Do not silently export plaintext when encryption prerequisites fail. Public and internal exports encrypt by default. Only explicit `--unencrypted` produces a local Diagnostic build; it cannot be labelled Public.

Implementation sequence:
1. Pin official source commit and portable compiler; create private key and isolated SCons; compile matching custom template.
2. Add fail-closed template/key checks and encrypted staging in `tools/export_build.py`.
3. Verify a tiny project loads encrypted scene, script, JSON and texture with the custom template; verify the standard template rejects that PCK.
4. Export the approved committed game revision, inspect ZIP membership and run packaged game smoke checks.

## Preparation

From the repository root:

```powershell
python tools/prepare_encrypted_template.py --jobs 6
python tools/test_encrypted_release.py
python tools/verify_encrypted_template.py
python tools/prepare_encrypted_template.py --verification-template --jobs 6
python tools/export_build.py --encrypted --ref HEAD
# Internal-only EA build:
python tools/export_build.py --encrypted --ea --ref HEAD
```

Source: official `4.7.2-stable`, commit `ed1daf0bf001b61586d9930840f2f1394092c079`, downloaded from GitHub codeload by exact commit. Portable compiler: official LLVM-MinGW `20260922` UCRT x64; archive SHA256 `e3ad77d117a4bea19a7a3b333341824d79a5a371004a10e25b8504e7b3047666`. SCons 4.9.1 is installed into a private directory, not the system Python environment. Compiler PATH is scoped to the build child process. Current game renderer is OpenGL compatibility, so template disables D3D12 and AccessKit dependencies. Build uses six jobs by command above, no LTO and no debug symbols.

`C:/Users/colafax/.codex/private/ArknightsSurvivors` holds the key, downloaded source/compiler, generated compilation source, template and compile log. It is outside Git and distribution staging. Windows ACL inheritance is disabled, granting current user and SYSTEM. Do not copy or print `encryption.key`, generated encryption source, or key-bearing environment contents. The key is generated locally with `secrets.token_hex(32)` and passed only in child process environments. Private `template.json` records source/compiler/version and executable checksum, without the encryption key.

## Packaging behavior

Encryption is the default and `--encrypted` may make it explicit. `--unencrypted` is diagnostic only. Prerequisites are checked before deleting/rebuilding staging. The source remains a `git archive` of `--ref`, so uncommitted files are excluded. The original `game/export_presets.cfg` is not changed. Only the staging preset receives the custom template, `packed_release` feature, `encrypt_pck=true`, `encrypt_directory=true`, encryption include `*` and empty encryption exclusions. Game tests and editor addons are excluded.

Filtered `art/incoming/*.png` files are copied inside staging `game/art/incoming` before import. The staging-only art loader suppresses external PNG overrides under `packed_release`; its existing ResourceLoader fallback loads imported packed textures, including aliases and @2x variants. Audio already uses `res://audio` and ResourceLoader. Development and Web loading are unchanged.

The resulting encrypted ZIP has `_Public_Encrypted` in its filename (or `_Internal_EA_Encrypted` with `--ea`). Its allowlist is `game/ArknightsSurvivors.exe`, `game/ArknightsSurvivors.pck`, `开始游戏.bat`, `说明.txt`, `release_manifest.json`. The manifest contains engine/PCK metadata, source commit, explicit public/internal audience, packed PNG count and file hashes; no secrets or private build paths. Validation rejects unknown loose files and an unencrypted PCK directory. PCK encryption raises resource extraction cost; the shipped executable necessarily contains a decryption key and cannot guarantee resistance to determined reverse engineering.

## Verification evidence

The public encrypted template compiled successfully (2,431 translation units, SCons exit 0). The independent encrypted scene/script/JSON/texture boot test passed. The ordinary template produced a decryption failure; Windows may remain in startup error handling, so negative tests terminate it after 20-30 seconds and record that fact. Timeout alone is never accepted as rejection evidence: an explicit ERR_FILE_CORRUPT or MD5/decryption failure is required. Six focused Python contract tests and syntax checks pass. Private diagnostic template compilation and the final full-game resource/ZIP checks remain pending; no final game export has been performed by this task yet.

Official references:
- https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_with_script_encryption_key.html
- https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_windows.html

`data/build.json` always receives an explicit audience and encrypted flag. Public builds clear any inherited EA channel; internal EA builds set channel to EA. Diagnostic packages are labelled `_Diagnostic` and their instructions say they must not be publicly released.

The public template keeps path overrides disabled. A separate private `diagnostic_verifier.exe` may enable `--main-pack` / `--script` to inspect the encrypted game PCK; it is never selected by the exporter or copied into the release. Public template and diagnostic verifier have independent stable filenames and SHA256 fields. `verify_encrypted_game.py --package <export-folder> --zip <release.zip>` uses that verifier to load every staged PNG through ResourceLoader and Art.tex, checks readable pixel data, @2x density, aliases, audio, JSON, fresh progress, Public gallery locks and release feature gates. Every game probe and title smoke runs with fresh temporary APPDATA/LOCALAPPDATA and restores the parent environment. The real distributed public exe also gets its own title boot test. Ordinary-template decryption rejection is tested using a temporary ordinary exe with a same-named copy of the encrypted PCK, because normal Godot 4.7 release templates intentionally disallow path overrides.
