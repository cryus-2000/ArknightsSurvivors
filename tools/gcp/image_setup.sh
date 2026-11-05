#!/bin/bash
# 预装渲染 / 批跑镜像（tools/gcp/build_image.py 开一台临时机跑它，跑完关机、做成镜像 family arkr-render，docs/256 §7）。以 root 运行。
# 装好：apt 包（git、Xvfb、Mesa 软件 OpenGL、X11 运行库、中文字体）、pip 包（numpy、pillow、fonttools、imageio-ffmpeg）、Godot 4.7.2（官方 release + SHA512）；
# 预热：浅拉 claude/integ-1105 导入一遍，把 game/.godot 留在 /opt/arkr/godot_cache（开机后拷进检出目录，只增量导入改过的素材）。
set -uo pipefail
MDA=http://metadata.google.internal/computeMetadata/v1/instance
md() { curl -sf -H Metadata-Flavor:Google "$MDA/$1"; }
GS="$(md attributes/image-gs)"
REF="$(md attributes/image-ref || echo claude/integ-1105)"
exec > >(tee -a /var/log/arkr_image.log) 2>&1
fail() { echo "fail $1" | gcloud storage cp - "$GS/done" -q; exit 1; }
export DEBIAN_FRONTEND=noninteractive HOME=/root
apt-get update -qq || fail apt-update
apt-get install -y -qq git python3-pip wget unzip ca-certificates curl libfontconfig1 xvfb xauth libgl1 libgl1-mesa-dri libglx-mesa0 libegl1 \
    libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 libxkbcommon0 fonts-noto-cjk >/dev/null || fail apt
python3 -m pip install -q --break-system-packages numpy pillow fonttools imageio-ffmpeg || fail pip
python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())" || fail ffmpeg
V=4.7.2
mkdir -p /opt/arkr/godot && cd /opt/arkr/godot || fail dir
BASE="https://github.com/godotengine/godot-builds/releases/download/${V}-stable"
ZIP="Godot_v${V}-stable_linux.x86_64.zip"
wget -q "$BASE/$ZIP" -O "$ZIP" && wget -q "$BASE/SHA512-SUMS.txt" -O SHA512-SUMS.txt || fail godot-dl
grep " ${ZIP}\$" SHA512-SUMS.txt | sha512sum -c - || fail godot-sha
unzip -q -o "$ZIP" && mv -f "Godot_v${V}-stable_linux.x86_64" godot && chmod +x godot && rm -f "$ZIP"
./godot --version || fail godot-run
# 导入缓存预热
git clone -q --depth 1 --branch "$REF" https://github.com/cryus-2000/ArknightsSurvivors.git /opt/arkr/repo || fail clone
cd /opt/arkr/repo && python3 tools/asset_index.py >/dev/null 2>&1
/opt/arkr/godot/godot --headless --path game --import >/dev/null 2>&1 || true
test -d game/.godot/imported || fail import
rm -rf /opt/arkr/godot_cache && mv game/.godot /opt/arkr/godot_cache
cd / && rm -rf /opt/arkr/repo
echo "godot $V; cache from $REF $(date -u)" > /opt/arkr/ready
apt-get clean
echo 0 | gcloud storage cp - "$GS/done" -q
sync
shutdown -h now
