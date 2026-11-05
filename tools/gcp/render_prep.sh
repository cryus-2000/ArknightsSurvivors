# GCP 出图任务的准备段（tools/gcp_render.py 拼在任务命令前面，经 metadata 下发；虚拟机仓库根目录、已 source tools/cloud/env.sh）。
# 不从被测提交里读：被测分支可能比这套工具老。做的事：
#   1. 装 xvfb + Mesa 软件 OpenGL + X11 运行库 + 中文字体 + ffmpeg（imageio-ffmpeg）
#   2. 生成不进 git 的本地文件：game/art/index.json（asset_index.py，录像 / 截图前必须有，否则新帧条静默回退旧画面）
#   3. GODOT 换成包装脚本：一律 --rendering-driver opengl3（虚拟机没有 GPU / Vulkan）；--headless 照旧可用
#   4. 设好 DISPLAY（Xvfb :99，1920×1080×24），之后的 Godot 窗口都画到这块虚拟屏上
# 变量：$OUT（结果目录）、$MEDIA = $OUT/media（PNG / MP4 放这里，才会被收回）、$CJK_FONT（中文字体路径，PIL 拼图用）
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq xvfb xauth libgl1 libgl1-mesa-dri libglx-mesa0 libegl1 libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 libxkbcommon0 \
    fonts-noto-cjk >/dev/null
python3 -m pip install -q imageio-ffmpeg numpy pillow 2>/dev/null || python3 -m pip install -q --break-system-packages imageio-ffmpeg numpy pillow
export CJK_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
test -f "$CJK_FONT" || export CJK_FONT="$(fc-list :lang=zh -f '%{file}\n' | head -1)"
if [ -f tools/asset_index.py ]; then python3 tools/asset_index.py >/dev/null && echo "index.json 已生成（$(python3 -c "import json;print(len(json.load(open('game/art/index.json'))))") 项）"; fi
cat > /usr/local/bin/godot-gl <<GEOF
#!/bin/bash
exec "$GODOT" --rendering-driver opengl3 "\$@"
GEOF
chmod +x /usr/local/bin/godot-gl
export GODOT=/usr/local/bin/godot-gl
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/work/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
export MEDIA="$OUT/media"
mkdir -p "$MEDIA"
# Windows 专用字体路径的脚本（如 pxplane_shots.py 的 C:/Windows/Fonts/msyh.ttc）：在仓库根建同名相对路径指到中文字体
mkdir -p "C:/Windows/Fonts" && ln -sf "$CJK_FONT" "C:/Windows/Fonts/msyh.ttc" && ln -sf "$CJK_FONT" "C:/Windows/Fonts/msyhbd.ttc"
echo "render_prep 完成：GODOT=$GODOT DISPLAY=$DISPLAY 字体=$CJK_FONT"
