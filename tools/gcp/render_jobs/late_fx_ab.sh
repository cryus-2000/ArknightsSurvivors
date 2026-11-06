# 后期特效控制（docs/293）开 / 关对照截图：同 late_fx_diag.sh 的四人精二满节点局（种子 11、--slot4），只拍完整画面。
# 用法（每条一台）：python tools/gcp_render.py --branch <提交> --job custom --split --name lfxab \
#   --cmd 'LU=A VARS="off A" bash tools/gcp/render_jobs/late_fx_ab.sh' --cmd 'LU=B VARS="off A" bash ...' ...
# VARS：off = 缺省；A = 不降亮版（队长不被压 + 填充变薄 + 队友发光点 / 颗粒减量 + 立起层接降噪，队友整体透明度不动）；
#       B = A + 队友整体透明度 × 0.55；M = 手机档数值（桌面上模拟：队友 0.4、颗粒 0.35、填充 0.4、发光点 0.3）
# 结果：$MEDIA/<阵容>_<变体>/shot_<帧>.png
set +e
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
SPF=0.0659
FR=$(python3 -c "print(','.join(str(int(round(t/$SPF))) for t in (${TIMES:-470,500,590})))")
case "$LU" in
    A) SQ="--op=logos --squad=texas,suzuran,eyjafjalla" ;;
    B) SQ="--op=mizuki --squad=skadi,wisadel,exusiai" ;;
esac
ON="--bal=render/late_fx=1"
run() {
    case "$1" in
        off) b="" ;;
        A) b="$ON --bal=render/late_fx_mate=1" ;;
        B) b="$ON" ;;
        M) b="$ON --bal=render/late_fx_mate=0.4 --bal=render/late_fx_grains=0.35 --bal=render/late_fx_fill=0.4 --bal=render/late_fx_emit=0.3" ;;
    esac
    d="$(realpath -m "$MEDIA/${LU}_$1")"; mkdir -p "$d"   # 绝对路径：--path game 会改工作目录
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 7000 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 60 --path game -- \
        --balance --nodeath --seed=11 --slot4 $SQ --quality=high --prog=20 --maxt=${MAXT:-600} --shots=$FR --shotdir="$d" $b > "$OUT/${LU}_$1.log" 2>&1
    echo "${LU} $1 rc=$? $(ls $d/shot_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $OUT/${LU}_$1.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
for v in ${VARS:-off A}; do run $v & done
wait
exit 0
