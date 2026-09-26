#!/usr/bin/env bash
# 云端批跑环境初始化（Linux x86_64；docs/36 §7「云端批跑」）。在仓库根目录或任意位置运行：
#   bash tools/cloud/setup_linux.sh
# 做的事：装依赖 → 下载 Godot（官方 release）并核对 SHA512 → 大小写检查 → 导入项目 → 写 tools/cloud/env.sh
# 可调：GODOT_VER（缺省 4.7.2）、GODOT_DIR（缺省 ~/.local/godot-<版本>）
set -euo pipefail

GODOT_VER="${GODOT_VER:-4.7.2}"
GODOT_DIR="${GODOT_DIR:-$HOME/.local/godot-$GODOT_VER}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VER}-stable"
BIN="Godot_v${GODOT_VER}-stable_linux.x86_64"
ZIP="${BIN}.zip"

echo "== 1/5 依赖"
if command -v apt-get >/dev/null 2>&1; then
    SUDO=""
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi
    $SUDO apt-get update -qq
    # libfontconfig1：Godot 无界面模式也要用它加载字体；其余为下载 / 解压 / 测试脚本所需
    $SUDO apt-get install -y -qq wget unzip python3 ca-certificates libfontconfig1 >/dev/null
else
    echo "不是 apt 系发行版：请自行安装 wget unzip python3 fontconfig"
fi
python3 --version

echo "== 2/5 Godot ${GODOT_VER}（官方 release + SHA512 校验）"
mkdir -p "$GODOT_DIR"
if [ ! -x "$GODOT_DIR/godot" ]; then
    ( cd "$GODOT_DIR"
      wget -q "$BASE/$ZIP" -O "$ZIP"
      wget -q "$BASE/SHA512-SUMS.txt" -O SHA512-SUMS.txt
      if ! grep " ${ZIP}\$" SHA512-SUMS.txt | sha512sum -c - ; then
          echo "SHA512 校验失败，删除下载并退出"; rm -f "$ZIP"; exit 1
      fi
      unzip -q -o "$ZIP"
      mv -f "$BIN" godot
      chmod +x godot
      rm -f "$ZIP" )
fi
GODOT="$GODOT_DIR/godot"
"$GODOT" --version

echo "== 3/5 大小写检查（Windows 不分大小写、Linux 分）"
cd "$REPO"
python3 tools/cloud/case_check.py

echo "== 4/5 导入项目（生成 game/.godot 缓存，首次约 1–3 分钟）"
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
test -d game/.godot/imported || { echo "导入失败：game/.godot/imported 不存在"; exit 1; }
# .uid / .import 旁路文件应当都已入库（.gitignore 第 1 行的约定）。导入后冒出未跟踪的，说明有人新增脚本 / 资源时漏提交了，
# 云端生成的是随机 UID，不要提交它，回到本机补交原来的那份（docs/36 §7.1）
NEW_SIDE="$(git status --porcelain --untracked-files=all 2>/dev/null | grep -E '^\?\? .*\.(uid|import)$' || true)"
if [ -n "$NEW_SIDE" ]; then
    echo "注意：导入后出现未入库的 .uid / .import（$(echo "$NEW_SIDE" | wc -l) 个），不影响测试，但请在本机补交：" 
    echo "$NEW_SIDE" | head -10
fi

echo "== 5/5 写 tools/cloud/env.sh"
cat > tools/cloud/env.sh <<EOF
# 由 setup_linux.sh 生成；run_cloud.sh 会 source 它
export GODOT="$GODOT"
export GODOT_MAX_PROCS="\${GODOT_MAX_PROCS:-\$(nproc)}"
EOF
echo "完成。下一步：bash tools/cloud/run_cloud.sh"
