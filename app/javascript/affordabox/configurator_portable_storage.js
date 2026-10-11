// The 3-D quote for portable-storage (thank-you-quote-portable-storage.astro in the redesign),
// as it was: a WebGL raymarched model that resizes with the choice, the live
// price and the hand-off to the online quote. Its settings (sizes, prices,
// the online quote's address, the decal) are the JSON in the block's
// data-config (website/shared/configurators).
const root = document.querySelector('[data-configurator="portable-storage"]')
const cfg = root ? JSON.parse(root.dataset.config) : null
if (cfg) window.__QX_LOGO_URL = cfg.logoUrl

if (cfg) (() => {
  "use strict";
  const RM = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (id) => document.getElementById(id);
  const money = (n) => "$" + Number(n).toLocaleString("en-US");

  /* ---- WebGL raymarched container — AffordABox white box, GREEN door ---- */
  const FRAG = `
  precision highp float;
  uniform vec2 u_res; uniform float u_time; uniform vec3 u_size; uniform vec2 u_mouse; uniform float u_amber; uniform sampler2D u_logo;
  #define I 100
  mat3 rotY(float a){float c=cos(a),s=sin(a);return mat3(c,0.,-s,0.,1.,0.,s,0.,c);}
  float sdBox(vec3 p, vec3 b, float r){vec3 q=abs(p)-b+vec3(r);return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0)-r;}
  float mapBox(vec3 p){return sdBox(p,u_size,0.06);}
  float map(vec3 p){float g=p.y+u_size.y+0.002;return min(g, mapBox(p));}
  vec3 nrm(vec3 p){vec2 e=vec2(0.0016,0.);return normalize(vec3(map(p+e.xyy)-map(p-e.xyy),map(p+e.yxy)-map(p-e.yxy),map(p+e.yyx)-map(p-e.yyx)));}
  float shadow(vec3 ro, vec3 rd){float r=1.0,t=0.03;for(int i=0;i<26;i++){float h=map(ro+rd*t);if(h<0.001)return 0.0;r=min(r,11.0*h/t);t+=clamp(h,0.03,0.5);if(t>16.0)break;}return clamp(r,0.0,1.0);}
  float ao(vec3 p, vec3 n){float o=0.,s=1.;for(int i=0;i<5;i++){float h=0.03+0.14*float(i);o+=(h-map(p+n*h))*s;s*=0.72;}return clamp(1.0-1.6*o,0.0,1.0);}
  vec3 sky(vec3 rd){float t=clamp(rd.y*0.5+0.5,0.0,1.0);vec3 c=mix(vec3(0.97,0.965,0.95),vec3(0.72,0.82,0.92),pow(t,0.8));c+=vec3(1.0,0.94,0.72)*pow(max(1.0-abs(rd.y),0.0),8.0)*0.05;return c;}
  vec3 mat(vec3 p, vec3 n){
    // AffordABox livery: smooth white body, logo decal on the long sides,
    // GREEN roll-up door on the end face
    vec3 base=vec3(0.93,0.925,0.915);
    base*= (abs(n.y)<0.6)? 0.975 : 0.99;
    float side=step(0.6,abs(n.z));
    float ASPECT=5.6;                                   // AffordABox wordmark ~5.6:1
    float W=min(u_size.y*0.66*ASPECT, u_size.x*1.72);
    float H=W/ASPECT;
    vec2 uv=vec2(p.x/W+0.5, (p.y-u_size.y*0.12)/H+0.5);
    uv.x=mix(uv.x, 1.0-uv.x, step(0.0,n.z));
    float inuv=step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
    vec4 logo=texture2D(u_logo, clamp(uv,0.0,1.0));
    base=mix(base, logo.rgb, logo.a*side*inuv);
    // GREEN roll-up door on the +x end: horizontal slats inside a white frame
    float end=step(0.6,n.x);
    float doorz=step(abs(p.z),u_size.z*0.84);
    float doory=step(abs(p.y+u_size.y*0.05),u_size.y*0.86);
    float door=end*doorz*doory;
    float slat=0.90+0.10*cos(p.y*46.0);
    base=mix(base, vec3(0.20,0.615,0.259)*slat*1.15, door);   // AffordABox green #339D42
    return base;
  }
  void main(){
    vec2 uv=(gl_FragCoord.xy-0.5*u_res)/u_res.y;
    float ry=u_time*0.14 + u_mouse.x*0.5;
    float pit=0.34 - u_mouse.y*0.12;
    vec3 ro=vec3(0.0,0.0,8.8);
    ro=rotY(ry)*ro; ro.y=3.2*sin(pit);
    vec3 ta=vec3(0.0,-0.2,0.0);
    vec3 f=normalize(ta-ro), rgt=normalize(cross(vec3(0,1,0),f)), up=cross(f,rgt);
    vec3 rd=normalize(uv.x*rgt+uv.y*up+1.5*f);
    float t=0.0; float hit=-1.0;
    for(int i=0;i<I;i++){vec3 p=ro+rd*t;float d=map(p);if(d<0.001){hit=t;break;}t+=d;if(t>40.0)break;}
    vec3 col=sky(rd);
    if(hit>0.0){
      vec3 p=ro+rd*hit; vec3 n=nrm(p);
      bool isBox = mapBox(p) < 0.02;
      vec3 alb = isBox ? mat(p,n) : vec3(0.80,0.79,0.77);
      vec3 L=normalize(vec3(-0.5,0.82,0.42));
      float sh=shadow(p+n*0.02,L);
      float dif=max(dot(n,L),0.0)*sh;
      float occ=ao(p,n);
      vec3 lit = alb*(vec3(0.52,0.55,0.60)*occ + dif*vec3(1.05,1.0,0.92));
      vec3 A=normalize(vec3(0.62,0.28,-0.7));
      lit += alb*max(dot(n,A),0.0)*vec3(0.85,1.0,0.85)*0.20*u_amber;
      vec3 h=normalize(L-rd);
      lit += pow(max(dot(n,h),0.0),46.0)*vec3(1.0,0.95,0.8)*sh*(isBox?0.6:0.12);
      float fr=pow(1.0-max(dot(n,-rd),0.0),3.5);
      lit += fr*vec3(0.80,0.87,0.95)*0.28;
      float fog=1.0-exp(-hit*hit*0.0016);
      col=mix(lit, sky(rd)*0.85, fog);
    }
    col += vec3(1.0,0.98,0.92)*pow(max(1.0-length(uv+vec2(0.35,0.1)),0.0),2.4)*0.05;
    float g=fract(sin(dot(gl_FragCoord.xy,vec2(12.99,78.23)))*43758.5)-0.5;
    col+=g*0.012;
    gl_FragColor=vec4(clamp(col,0.0,1.0),1.0);
  }`;
  const VERT = "attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}";

  function makeRenderer(canvas, opts){
    if(!canvas) return null;
    const gl = canvas.getContext("webgl", {antialias:false, alpha:false, powerPreference:"high-performance"});
    if(!gl) return null;
    const sh=(t,s)=>{const o=gl.createShader(t);gl.shaderSource(o,s);gl.compileShader(o);
      if(!gl.getShaderParameter(o,gl.COMPILE_STATUS)) console.warn(gl.getShaderInfoLog(o)); return o;};
    const prog=gl.createProgram();
    gl.attachShader(prog,sh(gl.VERTEX_SHADER,VERT));
    gl.attachShader(prog,sh(gl.FRAGMENT_SHADER,FRAG));
    gl.linkProgram(prog);
    if(!gl.getProgramParameter(prog,gl.LINK_STATUS)){console.warn(gl.getProgramInfoLog(prog));return null;}
    gl.useProgram(prog);
    const buf=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buf);
    gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
    const loc=gl.getAttribLocation(prog,"p");gl.enableVertexAttribArray(loc);gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);
    const U=n=>gl.getUniformLocation(prog,n);
    const tex=gl.createTexture();
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D,tex);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,1,1,0,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array([0,0,0,0]));
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    const logoImg=new Image();
    logoImg.crossOrigin="anonymous";
    logoImg.onload=()=>{gl.bindTexture(gl.TEXTURE_2D,tex);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL,false);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,logoImg);};
    logoImg.src=(window.__QX_LOGO_URL)||"/affordabox-logo-decal.png";
    gl.uniform1i(U("u_logo"),0);
    const u={res:U("u_res"),time:U("u_time"),size:U("u_size"),mouse:U("u_mouse"),amber:U("u_amber")};
    const state={size:opts.size.slice(),tsize:opts.size.slice(),mouse:[0,0],tmouse:[0,0],amber:opts.amber||1,vis:true,t0:performance.now()};
    const dpr=()=>Math.min(devicePixelRatio||1, 1.9);
    function resize(){const r=canvas.getBoundingClientRect();const w=Math.max(1,r.width*dpr()),h=Math.max(1,r.height*dpr());
      if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;gl.viewport(0,0,w,h);}}
    function frame(now){
      if(!state.vis){requestAnimationFrame(frame);return;}
      resize();
      for(let i=0;i<3;i++) state.size[i]+=(state.tsize[i]-state.size[i])*0.12;
      for(let i=0;i<2;i++) state.mouse[i]+=(state.tmouse[i]-state.mouse[i])*0.06;
      gl.uniform2f(u.res,canvas.width,canvas.height);
      gl.uniform1f(u.time, RM?1.4:(now-state.t0)/1000);
      gl.uniform3f(u.size,state.size[0],state.size[1],state.size[2]);
      gl.uniform2f(u.mouse,state.mouse[0],state.mouse[1]);
      gl.uniform1f(u.amber,state.amber);
      gl.drawArrays(gl.TRIANGLES,0,3);
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
    new IntersectionObserver(es=>{state.vis=es[0].isIntersecting;},{threshold:0.02}).observe(canvas);
    canvas.closest(".viz")?.addEventListener("pointermove",(e)=>{
      const r=canvas.getBoundingClientRect();
      state.tmouse=[((e.clientX-r.left)/r.width-0.5)*2,((e.clientY-r.top)/r.height-0.5)*2];
    });
    return { setSize:(s)=>state.tsize=s.slice() };
  }

  const sizeFor = (ft) => [ (ft/8)*1.25, 1.25, 1.25 ];
  const sizes = cfg.sizes;
  const bySlug = (s) => sizes.find((x) => x.slug === s) || sizes[0];
  const boxR = makeRenderer($("gl-box"), { size: sizeFor(bySlug(cfg.defaultSlug).lengthFt), amber: 0.75 });

  /* ---------------- pricing + Fuse sync ---------------- */
  const params = new URLSearchParams(location.search);
  const incZip = params.get("zip_code") || params.get("zip") || "";
  const incSize = params.get("size") || "";
  let startSlug = cfg.defaultSlug;
  if (incSize) { const m = sizes.find((s) => s.slug === incSize || String(s.lengthFt) === String(incSize).replace(/\D/g, "")); if (m) startSlug = m.slug; }
  const state = { size: startSlug, svc: "keep", zip: incZip };

  const si = document.querySelector(`input[name="size"][value="${state.size}"]`); if (si) si.checked = true;
  if (state.zip && $("zip")) $("zip").value = state.zip;

  function fuseUrl() {
    const s = bySlug(state.size), v = cfg.svc[state.svc];
    const p = new URLSearchParams();
    p.set("product_type", cfg.productType);
    if (v && v.fuse) p.set("service_type", v.fuse);
    if (state.zip) p.set("zip_code", state.zip);
    p.set("size", String(s.lengthFt)); // hint until Fuse product_ids are wired
    return cfg.fuseBase + "?" + p.toString();
  }

  let tweenId = 0;
  function tween(el, to) {
    const from = parseInt((el.textContent || "").replace(/[^0-9]/g, "")) || 0;
    if (RM) { el.textContent = to.toLocaleString("en-US"); return; }
    const id = ++tweenId, t0 = performance.now(), dur = 500;
    (function step(now) { if (id !== tweenId) return;
      const k = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - k, 3);
      el.textContent = Math.round(from + (to - from) * e).toLocaleString("en-US");
      if (k < 1) requestAnimationFrame(step);
    })(performance.now());
  }

  function render() {
    const s = bySlug(state.size), v = cfg.svc[state.svc];
    $("svc-label").textContent = v.name;
    $("sku").textContent = `${s.tag} · ${v.sku}`;
    $("capacity").textContent = `holds ≈ ${s.holds}`;
    $("tag-h").textContent = "8'";
    $("tag-l").textContent = s.lengthFt + "'";
    $("tag-v").textContent = s.cuft.toLocaleString() + " ft³";
    if (boxR) boxR.setSize(sizeFor(s.lengthFt));

    // Monthly recurring: the box rent (always) + any storage facility fee.
    $("qh-lab").textContent = "Monthly recurring";
    $("per").textContent = "/mo";
    let lines = `<div class="li"><div class="name">${s.label} white box<small>${s.dims} · ${s.cuft.toLocaleString()} ft³</small></div><div class="amt">${money(s.monthly)}<em>/mo</em></div></div>`;
    if (v.storage) {
      lines += `<div class="li"><div class="name">${v.storage[0]}<small>${v.storage[1]}</small></div><div class="amt">Quoted by ZIP</div></div>`;
    }
    $("lines").innerHTML = lines;

    // Transportation: one-time legs, always shown. $79 flat where known,
    // relocation / facility transfers quoted per job.
    $("transit-sec").style.display = "";
    $("transit-lines").innerHTML = v.legs
      .map(([name, note, amt]) => {
        const val = amt != null ? money(amt) : "Quoted by ZIP";
        return `<div class="li"><div class="name">${name}<small>${note}</small></div><div class="amt">${val}</div></div>`;
      })
      .join("");

    tween($("total"), s.monthly);

    const url = fuseUrl();
    if ($("fuse-cta")) $("fuse-cta").href = url;
    if ($("fuse-cta-2")) $("fuse-cta-2").href = url;
  }

  document.querySelectorAll('input[name="size"]').forEach((i) => i.addEventListener("change", (e) => { state.size = e.target.value; render(); }));
  document.querySelectorAll('input[name="svc"]').forEach((i) => i.addEventListener("change", (e) => { state.svc = e.target.value; render(); }));
  const zipEl = $("zip");
  if (zipEl) zipEl.addEventListener("input", (e) => { state.zip = e.target.value.replace(/\D/g, "").slice(0, 5); e.target.value = state.zip; render(); });

  render();
})();

