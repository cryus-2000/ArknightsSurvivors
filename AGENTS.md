# Shared agent collaboration rules

Read docs/06_git_collaboration.md before making changes.

- User owns product decisions. Codex owns art; Claude owns gameplay code, integration and builds.
- Claude uses E:\ArknightsSurvivors on main. Codex uses E:\ArknightsSurvivors\.worktrees\codex-art on codex/art.
- Worktree convention: .worktrees/ (ignored by Git). Do not change branches in the other agent's directory.
- Codex art scope: art/incoming/ and art handoff documentation. Claude code scope: game/ and implementation documentation. Coordinate before modifying the other's files.
- Commit only explicitly selected files belonging to your work; never sweep another agent's changes into a commit.
- Do not discard changes, force-push, reset --hard, or clean the other agent's work.
- Deliver art with a commit hash and affected paths. Claude reviews then cherry-picks the art commit into main from a clean working tree. If conflicts occur, resolve deliberately; do not overwrite either side wholesale.
- Art under incoming is authoritative delivery. Refer to docs/05_art_handoff.md for filenames, dimensions and import rules.
- Do not commit .godot/, build outputs, node_modules, credentials or local art backups.
- Git is local version control, not an automatic agent messaging service. No remote is configured by this setup.
