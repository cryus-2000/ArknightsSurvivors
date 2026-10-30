## 干员积木（docs/61）：数据干员（data_operator.gd）的积木编译、校验与共享执行器。
## 只走 op_api / character.gd 的公开方法与 g 的公共状态，不碰 game.gd 内部（下划线函数）、enemies.gd、combat.gd。
## 确定性（docs/36 §3）：本文件不用任何随机数；画面只往干员自己的 pfx 里加粒子（不碰 g.rng）。
## 本文件也被 -s 测试脚本（tests/test_core.gd，经 character.gd 的 validate_operator）加载：不许引用 Sfx 等自动加载。
## B6 ①（docs/101 §7.3，10-15）：本文件只剩门面。内容按段拆到 scripts/characters/blocks/，继承链 ob_core → ob_check → ob_fx → ob_vortex → ob_summon → ob_elite → ob_hw → seg_hoshiguma → seg_angelina → seg_texas → seg_exusiai → seg_skadi → seg_eyjafjalla → seg_logos → seg_ulpianus → seg_irene → seg_specter → seg_lumen → seg_mizuki → seg_siege → seg_suzuran → seg_wisadel → seg_saria → seg_skalter → seg_lappland → seg_gladiia；
## 外部照旧 preload 本文件、调 OB.<函数> / 读 OB.<常量>（沿继承链解析）。改积木请改 blocks/ 下对应的段文件。
extends "res://scripts/characters/blocks/seg_gladiia.gd"
