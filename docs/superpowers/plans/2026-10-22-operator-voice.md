# Operator voice implementation plan

> **For agentic workers:** Use the approved task brief at commit `845744b9`, plus this conversation's approved 20 command lines. Execute the steps below with focused regression checks, then request code review.

**Goal:** Add the two missing operators' voices, play the approved response on successful assault commands, and expose a once-per-join entry-start hook.

**Architecture:** Keep the current Sfx channel, interruption rules, queue and cooldowns. Squad selects one eligible speaker in deterministic leader-first rotation; `command` replaces `battle` only for assault. Recall keeps `entry`. Character owns the entry-start notification, currently called immediately because no deployment Start animation is wired. No animation, balance, gameplay RNG or recruitment-reveal changes.

**Tech stack:** Godot GDScript, existing Vorbis encoder, PCM16 masters, Python asset QA.

## 1. Regression first

- [x] Create `game/tests/voice_command_cases.gd` with a voice-request spy and real Squad / Character objects. Cover approved event, leader-first rotation, exclusion of non-roaming followers and downed members, command throttle, repeated / rejected state changes, demo suppression, entry hook deduplication, and unchanged RNG.
- [x] Add scene runner `game/tests/voice_command_test.gd` / `.tscn` and register `voice_command` in `tools/check.py`. Squad needs project autoload globals, so use the existing scene-regression pattern rather than core's standalone script mode.
- [x] Run the standalone runner through `tools/godot_runner.py`, headless / Dummy / `--voice-test`; confirm expected assertions fail before implementation.

## 2. Runtime voices and requests

- [x] Copy only the 30 approved OGGs and 30 WAV masters from `art/archive/incoming_1028/voice_batch6_1022` into `game/audio/voice`; merge manifest by operator/event, preserving the original91 entries. Check121 entries and20 operators.
- [x] Change `squad.gd` assault requests to `command`, retain recall `entry`, filter speakers with existing `cmd_roam()` and downed status. Preserve6-second command throttle, leader-first rotation, and original channel cooldowns.
- [x] Add `command` to Sfx event metadata without changing existing3-second team gap,15-second operator gap, interruption or queue rules.
- [x] Add `Character.entry_started()` with once-per-instance request guard; move Squad's current immediate entry request to that hook. No deployed Start track exists yet, so preserve immediate fallback timing.
- [x] Measure the two new operators' PCM RMS against the existing voice target; adjust trim within4dB only if needed. Do not re-encode existing voices.

## 3. Documentation and delivery

- [x] Update `game/audio/voice/README.md`, docs/114 §8.3 and the batch handoff with final implemented behavior, approved lines,121-entry coverage and limits. Preserve task brief's no-voice recruitment reveal.
- [x] Concatenate the two new operators' ten standard clips into a clearly ordered WAV under main `build/voice_1022` for optional listening; automated tests remain silent.
- [x] Run the focused regression green, import resources through the runner, then `python tools/check.py --auto --jobs 3`. Compare same-seed TRACE against frozen base `aa4aec6f`, including explicit command transitions. Do not run local balance batches or change golden snapshots.
- [x] Request a review against the brief and this conversation; fix material findings, commit selected files on `codex/voice`, and package the committed audio. Report commit, trigger list, checks, compressed size and separate SFX research candidates.

## Execution evidence

- Focused regression before implementation:65 checks,59 expected failures; after implementation:77 checks,0 failures.
- Runtime import completed without script errors. Core contracts:3240 checks,0 failures.
- Frozen baseline aa4aec6f, seed3, Skadi with Lappland/Gladiia,60seconds, commands at5/20/35:61 TRACE lines identical. BALANCE includes runtime profiling differences and is not an exact-match assertion in trace_base.
- Read-only implementation review found no material runtime issues. Automatic check:111 groups,110 passed; the only non-green group is the14 stale golden hashes. All14 produced TRACE and normalized BALANCE outputs were additionally compared with the existing goldens and match exactly. Per docs/36 section1.3, the coordinator rerecords goldens after merging. No golden files or checks were changed.

- Final summary used137/137 identical-input cached Godot results after adding the missing fontTools dependency locally. This is not a claim that the automatic check returned zero failures.
