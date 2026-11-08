# PV 局外系统录像（11-08 分镜 v5 加：认知塑造 / 蚀刻章 / 图鉴）：Godot --write-movie 1080p60 → $MEDIA/UI_<名>.mp4
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name pvui --cmd 'bash tools/gcp/render_jobs/pv_ui.sh'
set +e
OUT="$(realpath -m "$OUT")"; MEDIA="$(realpath -m "$MEDIA")"
mkdir -p "$MEDIA" "$OUT/ui"
G="${GODOT:-godot}"
rec() {   # rec <名> <秒上限> <游戏参数…>
  name="$1"; secs="$2"; shift 2
  d="$OUT/ui/$name"; mkdir -p "$d"
  timeout $((secs + 60)) "$G" --path game --audio-driver Dummy --fixed-fps 60 --resolution 1920x1080 --position 0,0 \
    --write-movie "$d/m.avi" -- "$@" > "$OUT/ui/$name.log" 2>&1
  ffmpeg -v error -y -i "$d/m.avi" -c:v libx264 -crf 15 -preset slow -pix_fmt yuv420p "$MEDIA/UI_$name.mp4"
  ls -la "$MEDIA/UI_$name.mp4" | tee -a "$OUT/runs.txt"
  cp "$OUT/ui/$name.log" "$MEDIA/UI_$name.log"
  rm -rf "$d"
}
rec meta 10 --metademo --metacells=99999 --metabuy=18
rec medals 15 --medalvideo --medals=all
rec gallery 8 --galleryshot=0,0,0,7 --galleryid=mizuki --galleryintro
exit 0
