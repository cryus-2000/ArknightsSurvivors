"""Build a file:// compatible editor: inline SVG and script, no fetch/server."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parent
data=json.loads((ROOT/'packed_layout_v16.json').read_text(encoding='utf-8'))
names=json.loads((ROOT/'achievement_set.json').read_text(encoding='utf-8'))['medals']
svg=(ROOT/'packed_layout_v16.svg').read_text(encoding='utf-8').replace('href="','href="../')
script=(ROOT/'layout_editor.js').read_text(encoding='utf-8')
options=''.join(f'<option value="{m["id"]}">{m["name"]}</option>' for m in names)
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>深蓝之下 · 排版调整</title>
<style>*{box-sizing:border-box}body{margin:0;background:#040b15;color:#cad6e5;font:13px 'Microsoft YaHei',sans-serif}header{display:flex;align-items:center;flex-wrap:wrap;gap:10px;padding:12px 18px;background:#101b2b}button,select,input,.upload{font:inherit;color:#dae6f4;background:#1a2b40;border:1px solid #41556d;border-radius:3px;padding:6px 9px}button,.upload{cursor:pointer}button:disabled{opacity:.4;cursor:default}input[type=number]{width:82px}input[type=file]{display:none}main{height:calc(100vh - 112px);min-height:300px;display:flex;justify-content:center;align-items:center}main>svg{display:block;width:100%;height:100%;touch-action:none;user-select:none}.medal{cursor:grab}.medal:active{cursor:grabbing}.medal.selected>polygon:last-child{stroke:#78d9f5;stroke-width:2.5}.clean .medal.selected>polygon:last-child{stroke:#6d7d8e;stroke-width:1}footer{padding:8px 18px;color:#9bb0c8;font-size:12px}label{white-space:nowrap}</style>
<header><strong>排版调整</strong><select id="chosen" aria-label="选中的蚀刻章">OPTIONS</select><label>X <input id="x" type="number" step="1" min="0" max="1672"></label><label>Y <input id="y" type="number" step="1" min="0" max="941"></label><label>大小 <input id="radius" type="number" step="1" min="35" max="220"></label><button id="undo">撤销</button><button id="clean">显示 / 隐藏选中框</button><button id="motion">暂停背景</button><button id="reset">恢复初始排版</button><button id="export">导出布局</button><label class="upload">导入布局<input id="import" type="file" accept=".json,application/json"></label></header><main>SVG</main><footer><span id="status"></span>　六边形碰撞已开启，移动和放大均不能重叠。大小数值为章的半径。</footer><script id="initial-layout" type="application/json">DATA</script><script>SCRIPT</script></html>'''
page=page.replace('OPTIONS',options).replace('SVG',svg).replace('DATA',json.dumps({'styleRevision':2,'canvas':[1672,941],'medals':data['medals']})).replace('SCRIPT',script)
(ROOT/'composition_review.html').write_text(page,encoding='utf-8')
(ROOT/'variants/index.html').write_text(page,encoding='utf-8')
print('Editor built: 9 draggable medals; inline assets and script; no fetch.')
