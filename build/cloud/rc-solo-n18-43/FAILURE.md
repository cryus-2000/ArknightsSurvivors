# rc-solo-n18-43: run blocked, no battles completed

commit 0d09939dab4ac025ea3d84b9a6e2c049b3cee4d2 (branch ci/0d09939da) does not
run headless at all. Every balance_run.py invocation (P=0, seeds=2; retried as
seeds=1/seed0=43) hung with zero output until killed — no `BALANCE {...}` line,
no battle completed, in >40 minutes.

Root cause (reproduced with a single direct Godot invocation, see
`repro_parse_error.log`):

```
SCRIPT ERROR: Parse Error: Identifier "L" not declared in the current scope.
          at: GDScript::reload (res://scripts/screens/choice_panel.gd:1052)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
          at: GDScript::reload (res://scripts/game.gd:0)
...
ERROR: Failed to load script "res://scripts/title.gd" with error "Compilation failed".
```

`game/scripts/screens/choice_panel.gd:1052` reads:

```gdscript
var dc := Color(0.86, 0.9, 0.93, ta) if card.has_meta("brief") and L.touch else Color(0.655, 0.69, 0.725, ta)   # 电脑：各类卡说明同字号同色（用户 10-30）
```

`L` is used elsewhere in this file (lines 223, 340, 630, 665, 681, 696, 719)
as a parameter of other functions, but the enclosing function here,
`draw_card(card: Button, o: Dictionary, i: int) -> void:` (line 979), has no
`L` parameter — so `L` is genuinely out of scope at line 1052. The inline
comment ("用户 10-30") marks this as a same-day edit.

Because `choice_panel.gd` fails to compile, `game.gd` (which depends on it)
fails to compile too, `title.gd` fails to load, and `game.gd`'s `pick`,
`perf_rep`, etc. end up Nil. The game then runs forever logging
`Invalid call. Nonexistent function 'update' in base 'Nil'.` every frame in
`_process` (game.gd:1448, `pick.update(delta)`) instead of ever reaching a
win/lose state — so no `--balance` run can ever finish on this commit.

This blocks ALL headless testing (balance_run.py and presumably check.py),
not just this batch. No placebo variant (P=0/1/2) would behave differently,
since this is a parse-time error independent of --placebos/--tier/etc., so
P1 and P2 were not attempted.

No battles, no win rates, no script_errors counts to report — 0 of 3
scheduled runs produced any data.
