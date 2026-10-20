# Summon visual alignment

User approved: preserve current damage/cooldown/movement timers; use a separate visual clock to align native release to the existing hit, allow visual-only recovery, interrupt on the next action. Movement uses idle loops plus world translation. Source main: 6b697796.

Existing frames/fps/fire are gameplay inputs: Mon3tr baseline hit=(2+.5)/14, action=4/14; sea cast hit=(2+.5)/10, action=4/10; sea spawn lock=6/12. Keep these unchanged. Existing lunge/leap and doll flash have custom gameplay/poses; retain them as explicit legacy fallbacks until matching body actions exist. Native skill labels alone do not establish game-skill equivalence.

Add one small visual sampler and opt-in visual metadata on existing sprite specs pointing at native-only extra sprite slots. Source sample times, source event, duration, frames and foot stay separate from gameplay specs. No RNG or gameplay branch reads visual state. Record visual attack start and actual hit timestamps; native source event is reached at the actual hit, recovery follows source time and can continue after gameplay act ends. A new attack/dash interrupts the previous recovery. Body movement remains existing controller logic. No gameplay timers are lengthened to play artwork.

Map Mon3tr idle and movement to native Idle, default attack to native Attack. Align sea cast to native Skill, sea spawn to native Start while retaining the old spawn lock. Map doll passive body to native Idle_B at revised scale/mouth; retain doll_spin and its independent hit_at. Map soul passive body to new 40x56 Idle; retain current timed fire effect pending a matching new overlay. Do not replace live attacks with a static native timeline.

Retain original Mon3tr sustained melt sequence and lunge/leap as explicit fallback if new native counterparts are not semantically established. Report these as remaining art gaps, not finished native migration. Produce FX review/brief for claw, melt slash, side blades and landing ring; no unsolicited asset overwrite.

Validation: meaningful failing regression for display/event and recovery/interrupt behavior, existing summon/elite regressions, same-seed TRACE at identical commit, full check.py --auto --jobs 3. No main merge/push/release. Deliver branch/hash and integration/fallback matrix.
