"""商人局内截图（10-21 坎诺特重绘接入的改前改后对照）。

用法：python -X utf8 tools/probes/merchant_shots.py <游戏工作树根> <输出目录>
--vfxdemo 局：18 秒灯标、20 秒点燃、34 秒商人出现在主控左上；--fixed-fps 60 下按帧连拍（商人 2 fps：相隔 30 帧换一帧）。
另拍商店界面（--motionshot=shop）。窗口在屏幕外、静音。
"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

root, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
game = os.path.join(root, 'game')
gr.ensure_imported(game)
godot = gr.find_godot()
base = [godot, '--path', game, '--resolution', '1280x720', '--position', '-4000,0', '--fixed-fps', '60', '--']
runs = {
    'world': ['--balance', '--seed=1', '--op=mizuki', '--vfxdemo', '--nodeath', '--realtime', '--maxt=38', '--shots=2088,2118,2148,2178,2208'],
    'shop': ['--autotest', '--motionshot=shop,0.6,1.2'],
}
for k, args in runs.items():
    d = os.path.join(out, k)
    os.makedirs(d, exist_ok=True)
    gr.run_godot(base + ['--shotdir=' + d] + args, 240)
    print(k, sorted(os.listdir(d)), flush=True)
