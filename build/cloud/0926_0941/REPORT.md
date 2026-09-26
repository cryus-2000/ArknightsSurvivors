# 云端快检报告 0926_0941

- 提交：90d84c9（origin/main）
- 机器：4 核 / 15 GB 内存，并发上限 4；Python 3.11.15；Godot 4.7.2.stable.official.ed1daf0bf（SHA512 OK）
- 安装+导入（setup_linux.sh 全程）：28 秒；apt 两个 PPA（deadsnakes、ondrej/php）被代理 403，已忽略，无影响
- 快检：35 秒，19 项全过，失败 0 项（核心契约测试 989 checks, 0 failed）
- 待协调人决定：导入后生成大量未跟踪 `*.gd.uid`（仓库未提交），提交进仓库还是加进 .gitignore
- 本分支只含 .md / .json；env.txt 与日志未推送

## check.log 最后 20 行

```
通过 冒烟 · eyjafjalla  t=120  · 6s
通过 冒烟 · irene  t=113 胜 · 7s
通过 冒烟 · kaltsit  t=120  · 5s
通过 冒烟 · logos  t=120  · 5s
通过 冒烟 · lumen  t=108 胜 · 5s
通过 冒烟 · mizuki  t=120  · 6s
通过 冒烟 · saria  t=120  · 6s
通过 冒烟 · siege  t=120  · 6s
通过 冒烟 · skadi  t=120  · 5s
通过 冒烟 · specter_unchained  t=120  · 6s
通过 冒烟 · suzuran  t=120  · 6s
通过 冒烟 · ulpianus  t=112 胜 · 5s
通过 冒烟 · wisadel  t=120  · 5s
通过 自然流程 · 高手  t=150  · 6s
通过 自然流程 · 普通  t=150  · 6s
通过 成长节点当场生效  13 名干员 × 6 节点
通过 主控保护  83 checks, 0 failed
通过 同 seed 复现  4:00 游戏时间逐字段相同

快检通过：19 项，失败 0 项，耗时 35 秒
```
