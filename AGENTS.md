# Shared agent collaboration rules

Read docs/06_git_collaboration.md before making changes.

- User owns product decisions. Codex owns character and monster art (player, allies, NPCs, enemies, bosses: idle / move / attack / feign strips and their portraits). Claude owns gameplay code, integration, builds, and all other art: attack and hit effects (fx_*), projectiles (proj_*), warnings, drone / weapon / evo / skill / relic / growth icons, terrain, props, pickups and UI.
- Claude uses E:\ArknightsSurvivors on main. Codex uses E:\ArknightsSurvivors\.worktrees\codex-art on codex/art.
- Worktree convention: .worktrees/ (ignored by Git). Do not change branches in the other agent's directory.
- Codex art scope: character and monster files in art/incoming/ (player_*, ally_*, e_*, boss*, bosses/, doctor, merchant, mizuki_*) and their handoff documentation. Claude scope: game/, implementation documentation, and every other file in art/incoming/ (fx_*, proj_*, evo_*, weapon_*, skill_*, relic_*, growth_*, terrain_*, prop_*, tiles, gem_*, chest, oil, jelly, slash, tentacle, drone_*, light). Coordinate before modifying the other's files.
- Commit only explicitly selected files belonging to your work; never sweep another agent's changes into a commit.
- Do not discard changes, force-push, reset --hard, or clean the other agent's work.
- Deliver art with a commit hash and affected paths. Claude reviews then cherry-picks the art commit into main from a clean working tree. If conflicts occur, resolve deliberately; do not overwrite either side wholesale.
- Art under incoming is authoritative delivery. Refer to docs/05_art_handoff.md for filenames, dimensions and import rules.
- Do not commit .godot/, build outputs, node_modules, credentials or local art backups.
- Automated runs must be silent: any launch with a `--xxx` user argument (autotest, balance, screenshots, gallery shots) mutes the Master bus in sfx.gd. Never remove that mute, and never add a test mode that bypasses it — the user works while tests run. Prefer `--headless` for anything that does not need a screenshot.
- Git is local version control, not an automatic agent messaging service. No remote is configured by this setup.
