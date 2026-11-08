# PV 局外系统录像（11-08 分镜 v5 加：认知塑造 / 蚀刻章 / 图鉴）→ $MEDIA/UI_<名>.mp4（1920×1080、60 帧）
# Godot --write-movie 在云端锁 1280×720（项目基准分辨率），所以用游戏自带的逐帧截图开关存 PNG（按窗口实际分辨率），再 ffmpeg 合成。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name pvui --cmd 'bash tools/gcp/render_jobs/pv_ui.sh'
set +e
OUT="$(realpath -m "$OUT")"; MEDIA="$(realpath -m "$MEDIA")"
mkdir -p "$MEDIA" "$OUT/ui"
G="${GODOT:-godot}"
rec() {   # rec <名> <秒上限> <帧文件模式> <游戏参数…>
  name="$1"; secs="$2"; pat="$3"; shift 3
  d="$OUT/ui/$name"; mkdir -p "$d"
  timeout "$secs" "$G" --path game --audio-driver Dummy --fixed-fps 60 --resolution 1920x1080 --position 0,0 -- --shotdir="$d" "$@" > "$OUT/ui/$name.log" 2>&1
  n=$(ls "$d" | wc -l)
  ffmpeg -v error -y -framerate 60 -i "$d/$pat" -c:v libx264 -crf 15 -preset slow -pix_fmt yuv420p "$MEDIA/UI_$name.mp4"
  echo "$name: $n 帧" | tee -a "$OUT/runs.txt"
  cp "$OUT/ui/$name.log" "$MEDIA/UI_$name.log"
  rm -rf "$d"
}
rec meta 120 "rec_%04d.png" --metashot --metarec --metacells=99999 --metabuy=18
rec gallery 120 "shot_gallery_%02d.png" --galleryshot=0,0,0,1.5,150,0.0166 --galleryid=mizuki --galleryintro
rec medals 120 "shot_medals_%03d.png" --medalshot --medals=all --medalsel=cognition_complete --medalgif=120,0.0166
exit 0
