import html,json

def page(rows):
    cards=[]
    for a in rows:
        ident=a['id'];action=a['action'];link=f'{ident}/{action}_contact.png'
        cards.append(f'<section data-id="{ident}" data-action="{action}"><h3>{html.escape(a["name"])} · {action}</h3><canvas data-key="{ident}/{action}"></canvas><p>{a["frames"]} 帧 · 预览 {a["duration_seconds"]:.2f}s</p><a href="{link}">逐帧对照</a></section>')
    data=json.dumps(rows,ensure_ascii=False)
    return '''<!doctype html><meta charset="utf-8"><title>怪物完整动作候选</title>
<style>body{background:#171e26;color:#d8e2e8;font:16px sans-serif;margin:24px}nav{position:sticky;top:0;background:#171e26;padding:10px;z-index:2}main{display:flex;flex-wrap:wrap;gap:16px}section{background:#25313d;padding:16px;min-width:210px}canvas{image-rendering:pixelated;background:#111a20}a{color:#9bc9d7}button{padding:8px;margin:4px;cursor:pointer}section[hidden]{display:none}</style>
<h1>怪物动作补齐候选</h1><p>2px 网格 · 独立发光层 · 固定体型与原点。素材预览，未接入游戏。</p>
<p>受击按「待机 → 受击 0.12 秒 → 待机」展示；此时长仅用于审稿。原生动作按源时长，自定义动作按审稿时长，均不替代游戏逻辑时序。</p>
<nav><button onclick="filter('all')">全部</button><button onclick="filter('wound')">全部受击</button><button onclick="filter('knight_boss')">骑乘骑士</button><button onclick="filter('death')">死亡</button><button onclick="filter('custom')">补画与专用动作</button><br><button onclick="speed=1">原速</button><button onclick="speed=.5">半速</button><button onclick="speed=0">暂停</button></nav><main>'''+''.join(cards)+'''</main><script>
const rows='''+data+''';let speed=1,clock=0,last=performance.now();
function load(src){let im=new Image();im.src=src;return im}
const all=rows.map(a=>{let c=document.querySelector('[data-key="'+a.id+'/'+a.action+'"]');c.width=a.size[0];c.height=a.size[1];return {a,c,visible:false,im:load(a.strip),e:load(a.emit),idle:load(a.id+'/e_'+a.id+'_idle@2x.png'),idleE:load(a.id+'/e_'+a.id+'_idle_emit@2x.png')}});
const byCanvas=new Map(all.map(v=>[v.c,v]));const observer=new IntersectionObserver(es=>{for(const e of es)byCanvas.get(e.target).visible=e.isIntersecting},{rootMargin:'200px'});all.forEach(v=>observer.observe(v.c));
function filter(mode){for(const v of all){let a=v.a;v.c.parentElement.hidden=!(mode==='all'||a.action===mode||a.id===mode||(mode==='custom'&&a.construction&&a.construction!=='original Spine animation'))}}
function draw(x,im,i,c){if(im.complete&&im.naturalWidth)x.drawImage(im,i*c.width,0,c.width,c.height,0,0,c.width,c.height)}
function tick(t){clock+=(t-last)/1000*speed;last=t;for(const {a,c,im,e,idle,idleE,visible} of all){if(c.parentElement.hidden||!visible)continue;let phase=clock%(a.duration_seconds+(a.loop?0:.45)),i=0;for(let n=0;n<a.sample_times.length;n++)if(phase>=a.sample_times[n])i=n;let x=c.getContext('2d');x.imageSmoothingEnabled=false;x.clearRect(0,0,c.width,c.height);if(a.action==='wound'&&(clock%1.4<.5||clock%1.4>=.62)){draw(x,idle,0,c);draw(x,idleE,0,c)}else{draw(x,im,i,c);draw(x,e,i,c)}}requestAnimationFrame(tick)}requestAnimationFrame(tick);
</script>'''
