/* Continuous scene flow, nearest texture sampling, rendered on a 2x motion grid. */
(() => {
  const canvas = document.getElementById('scene');
  const source = document.getElementById('source');
  const play = document.getElementById('play');
  const still = document.getElementById('still');
  const status = document.getElementById('motion-status');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const gl = canvas.getContext('webgl', {alpha:false, antialias:false, preserveDrawingBuffer:true});
  let running = !reduce.matches, staticView = reduce.matches, seconds = 0, last = 0;
  let lastDraw = -1, frameRequest = 0;

  function fail(error) {
    canvas.hidden = true;
    status.textContent = '动态预览不可用，显示静态图。';
    play.disabled = still.disabled = true;
    window.sceneMotion = {ready:false, error:String(error)};
    console.error(error);
  }
  if (!gl) { fail('WebGL unavailable'); return; }
  const vertex = `
    attribute vec2 position;
    varying vec2 uv;
    void main() {
      uv = (position * vec2(1.0, -1.0) + 1.0) * .5;
      gl_Position = vec4(position, 0.0, 1.0);
    }`;
  const fragment = `
    precision highp float;
    varying vec2 uv;
    uniform sampler2D image;
    uniform float time;
    uniform float staticView;
    const vec2 size = vec2(640.0, 360.0);
    const float TAU = 6.28318530718;
    float ellipse(vec2 p, vec2 c, vec2 radius) {
      return 1.0-smoothstep(.8,1.35,length((p-c)/radius));
    }
    float hash(float x) {return fract(sin(x*43.132+5.31)*213.41);}
    void main() {
      vec2 p = uv*size;
      if (staticView > .5) { gl_FragColor=texture2D(image,p/size); return; }
      float phase = TAU*mod(time,12.0)/12.0;
      vec2 q = p;

      // One broad envelope covers the fine filaments as well as the bell.
      // All parts share the same drift and bend; there is no bell/tail seam.
      vec2 mainLocal=p-vec2(386.0,175.0);
      vec2 alongAxis=vec2(-.56,.82849),acrossAxis=vec2(.82849,.56);
      float across=dot(mainLocal,acrossAxis),along=dot(mainLocal,alongAxis);
      float mainWeight=1.0-smoothstep(1.05,1.70,length(vec2(across/64.0,along/111.0)));
      mainWeight*=smoothstep(294.0,338.0,p.x+.45*(p.y-160.0));
      mainWeight*=1.0-smoothstep(264.0,296.0,p.y);
      float bend=smoothstep(-70.0,110.0,along);
      vec2 drift=vec2(1.65*sin(phase),-2.15*sin(phase));
      vec2 flex=acrossAxis*(1.25*bend*bend*sin(phase*2.0-bend*2.4));
      vec2 stroke=acrossAxis*(across*.012*sin(phase*3.0)*(1.0-bend));
      q-=(drift+flex+stroke)*mainWeight;

      float nearJelly = ellipse(p,vec2(274,223),vec2(20,27));
      q -= vec2(1.4*sin(phase+1.3),2.1*sin(phase+.4))*nearJelly;
      q.x += sin(phase*2.0-(p.y-209.0)*.13)*nearJelly*clamp((p.y-211.0)/28.0,0.0,1.0);
      float farJelly = ellipse(p,vec2(520,109),vec2(12,20));
      q -= vec2(.9*sin(phase+2.1),1.4*sin(phase+1.7))*farJelly;

      // Move the existing light pattern gently; never pulse the entire image.
      float upperWater = smoothstep(337.0,398.0,p.x)*(1.0-smoothstep(540.0,577.0,p.x))
                         *(1.0-smoothstep(65.0,84.0,p.y));
      q.x += 1.7*sin(phase)*upperWater;
      // Surface ripples and the hanging growth move on separate, slower rhythms.
      float surface=smoothstep(320.0,376.0,p.x)*(1.0-smoothstep(555.0,587.0,p.x))
                    *(1.0-smoothstep(23.0,45.0,p.y));
      q.x+=1.4*sin(p.y*.17-phase*2.0)*surface;
      q.y+=.55*sin(p.x*.055-phase*2.0)*surface;
      float ropes=ellipse(p,vec2(294,72),vec2(36,54));
      float ropeTip=smoothstep(30.0,119.0,p.y);
      q.x+=.8*sin(phase*2.0)*ropeTip*ropeTip*ropes;
      q=clamp(q,vec2(.25),size-.25);
      vec3 color = texture2D(image,q/size).rgb;

      // Moving light bands in the water, not a whole-screen brightness pulse.
      float water=smoothstep(310.0,365.0,p.x)*(1.0-smoothstep(555.0,590.0,p.x))
                  *(1.0-smoothstep(180.0,266.0,p.y));
      float light=.012*sin(p.x*.065+p.y*.037-phase)+.007*sin(p.x*.12+p.y*.046-phase*2.0);
      color+=vec3(.45,.78,1.0)*light*water*(1.0-.75*mainWeight);

      // Foreground weed silhouettes grow from the existing dark seabed.
      for(int j=0;j<5;j++) {
        float id=float(j);
        float rootX=550.0+id*13.0;
        float height=28.0+hash(id+80.0)*29.0;
        float h=(353.0-p.y)/height;
        float safeH=clamp(h,0.0,1.0);
        float center=rootX-6.0*safeH+3.4*safeH*safeH*sin(phase+id*.6);
        float width=mix(1.8,.45,safeH);
        float stem=(1.0-step(width,abs(p.x-center)))*step(0.0,h)*(1.0-step(1.0,h));
        float leafY=fract(safeH*4.0);
        float leafX=center+sin(floor(safeH*4.0)*2.3)*5.0*(1.0-leafY);
        float leaf=(1.0-step(1.1,abs(p.x-leafX)))*step(.1,leafY)*(1.0-step(.66,leafY))*step(.12,h)*(1.0-step(.88,h));
        color=mix(color,vec3(.021,.045,.057),max(stem,leaf));
      }

      // A small school crosses the middle distance; silhouettes stay subordinate.
      float schoolAge=fract(time/12.0+.25);
      float schoolFade=smoothstep(0.0,.18,schoolAge)*(1.0-smoothstep(.78,1.0,schoolAge));
      for(int k=0;k<6;k++) {
        float id=float(k);
        vec2 fish=vec2(420.0+id*8.0+70.0*schoolAge,181.0+mod(id,3.0)*4.0+1.7*sin(phase*2.0+id));
        vec2 f=p-fish;
        float body=1.0-step(1.0,length(f/vec2(2.1,.8)));
        float tail=step(-4.0,f.x)*(1.0-step(-1.9,f.x))*(1.0-step((-f.x-1.8)*.55,abs(f.y)));
        color=mix(color,vec3(.035,.085,.111),max(body,tail)*.65*schoolFade);
      }

      // A sparse, seeded set of native-pixel bubbles drifts through open water.
      for (int i=0;i<20;i++) {
        float id=float(i);
        float age=fract(time/12.0+hash(id+4.0));
        vec2 b=vec2(346.0+hash(id+17.0)*196.0,
                    188.0+hash(id+29.0)*61.0-age*96.0);
        b.x+=2.5*sin(phase+id*1.7);
        vec2 delta=abs(floor(p)+.5-(floor(b)+.5));
        float dotPixel=1.0-step(.6,max(delta.x,delta.y));
        float fade=smoothstep(0.0,.15,age)*(1.0-smoothstep(.75,1.0,age));
        color=mix(color,vec3(.43,.67,.77),dotPixel*fade*.5);
      }
      gl_FragColor=vec4(color,1.0);
    }`;

  function shader(type, text) {
    const s=gl.createShader(type); gl.shaderSource(s,text); gl.compileShader(s);
    if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));
    return s;
  }
  let program;
  try {
    program=gl.createProgram();
    gl.attachShader(program,shader(gl.VERTEX_SHADER,vertex));
    gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fragment));
    gl.linkProgram(program);
    if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program));
    gl.useProgram(program);
    const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
    gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,1,1]),gl.STATIC_DRAW);
    const position=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
    gl.viewport(0,0,canvas.width,canvas.height);
  } catch(error) { fail(error); return; }
  const t=gl.getUniformLocation(program,'time');
  const s=gl.getUniformLocation(program,'staticView');
  function renderAt(value,original=false) {
    gl.uniform1f(t,((value%12)+12)%12);gl.uniform1f(s,original?1:0);
    gl.drawArrays(gl.TRIANGLE_STRIP,0,4);
  }
  function labels() {
    play.textContent=running?'暂停动态':'播放动态';
    play.setAttribute('aria-pressed',String(running));
    still.setAttribute('aria-pressed',String(staticView));
    status.textContent=staticView?'静帧对照':running?'动态预览':'已暂停';
  }
  function tick(now) {
    if(running&&!document.hidden) {
      seconds+=(last?Math.min((now-last)/1000,.1):0);
      if(now-lastDraw>=1000/60-1){renderAt(seconds);lastDraw=now;}
    }
    last=now;
    if(running)frameRequest=requestAnimationFrame(tick);
  }
  function setRunning(value) {
    cancelAnimationFrame(frameRequest);running=value;staticView=false;last=0;
    renderAt(seconds);labels();
    if(running)frameRequest=requestAnimationFrame(tick);
  }
  function showStill(value) {
    cancelAnimationFrame(frameRequest);running=false;staticView=value;
    renderAt(seconds,staticView);labels();
  }
  async function start() {
    try {
      await source.decode();
      const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);
      for(const param of [gl.TEXTURE_MIN_FILTER,gl.TEXTURE_MAG_FILTER])gl.texParameteri(gl.TEXTURE_2D,param,gl.NEAREST);
      for(const param of [gl.TEXTURE_WRAP_S,gl.TEXTURE_WRAP_T])gl.texParameteri(gl.TEXTURE_2D,param,gl.CLAMP_TO_EDGE);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,source);
      gl.uniform1i(gl.getUniformLocation(program,'image'),0);
      renderAt(0,staticView);labels();
      play.addEventListener('click',()=>setRunning(!running));
      still.addEventListener('click',()=>showStill(!staticView));
      reduce.addEventListener('change',e=>{if(e.matches)showStill(true);});
      canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();cancelAnimationFrame(frameRequest);fail('WebGL context lost');});
      window.sceneMotion={ready:true,renderAt,setRunning,showStill,canvas,
        get running(){return running;},get seconds(){return seconds;}};
      if(running)frameRequest=requestAnimationFrame(tick);
    } catch(error){fail(error);}
  }
  start();
})();
