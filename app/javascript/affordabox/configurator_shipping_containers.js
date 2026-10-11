// The 3-D quote for shipping-containers (thank-you-quote-shipping-containers.astro in the redesign),
// as it was: a WebGL raymarched model that resizes with the choice, the live
// price and the hand-off to the online quote. Its settings (sizes, prices,
// the online quote's address, the decal) are the JSON in the block's
// data-config (website/shared/configurators).
const root = document.querySelector('[data-configurator="shipping-containers"]')
const cfg = root ? JSON.parse(root.dataset.config) : null
if (cfg) window.__QX_LOGO_URL = cfg.logoUrl

if (cfg) (() => {
  "use strict";
  const RM = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (id) => document.getElementById(id);
  const money = (n) => "$" + Number(n).toLocaleString("en-US");

  /* ---- WebGL corrugated shipping container — AffordABox charcoal livery ---- */
  const FRAG = `
  precision highp float;
  uniform vec2 u_res; uniform float u_time; uniform vec3 u_size; uniform vec2 u_mouse; uniform float u_amber; uniform sampler2D u_logo;
  #define I 110
  mat3 rotY(float a){float c=cos(a),s=sin(a);return mat3(c,0.,-s,0.,1.,0.,s,0.,c);}
  float sdBox(vec3 p, vec3 b){vec3 q=abs(p)-b;return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0);}
  float sdCap(vec3 p, vec3 a, vec3 b, float r){vec3 pa=p-a,ba=b-a;float h=clamp(dot(pa,ba)/dot(ba,ba),0.,1.);return length(pa-ba*h)-r;}
  float dBody(vec3 p, vec3 s){ return sdBox(p, s); }
  float dCorners(vec3 p, vec3 s){ vec3 c=vec3(s.x-0.09, s.y-0.09, s.z-0.09); return sdBox(abs(p)-c, vec3(0.115,0.115,0.115)); }
  float dRods(vec3 p, vec3 s){
    float x=s.x+0.015, r=0.028, y0=-s.y*0.85, y1=s.y*0.85;
    float z1=s.z*0.62, z2=s.z*0.20;
    float d=sdCap(p, vec3(x,y0, z1), vec3(x,y1, z1), r);
    d=min(d, sdCap(p, vec3(x,y0, z2), vec3(x,y1, z2), r));
    d=min(d, sdCap(p, vec3(x,y0,-z2), vec3(x,y1,-z2), r));
    d=min(d, sdCap(p, vec3(x,y0,-z1), vec3(x,y1,-z1), r));
    return d;
  }
  float mapObj(vec3 p){ return min(min(dBody(p,u_size), dCorners(p,u_size)), dRods(p,u_size)); }
  float map(vec3 p){ float g=p.y+u_size.y+0.002; return min(g, mapObj(p)); }
  vec3 nrm(vec3 p){vec2 e=vec2(0.0016,0.);return normalize(vec3(map(p+e.xyy)-map(p-e.xyy),map(p+e.yxy)-map(p-e.yxy),map(p+e.yyx)-map(p-e.yyx)));}
  float shadow(vec3 ro, vec3 rd){float r=1.0,t=0.03;for(int i=0;i<26;i++){float h=map(ro+rd*t);if(h<0.001)return 0.0;r=min(r,11.0*h/t);t+=clamp(h,0.03,0.5);if(t>16.0)break;}return clamp(r,0.0,1.0);}
  float ao(vec3 p, vec3 n){float o=0.,s=1.;for(int i=0;i<5;i++){float h=0.03+0.14*float(i);o+=(h-map(p+n*h))*s;s*=0.72;}return clamp(1.0-1.6*o,0.0,1.0);}
  vec3 sky(vec3 rd){float t=clamp(rd.y*0.5+0.5,0.0,1.0);vec3 c=mix(vec3(0.97,0.965,0.95),vec3(0.72,0.82,0.92),pow(t,0.8));c+=vec3(1.0,0.94,0.72)*pow(max(1.0-abs(rd.y),0.0),8.0)*0.05;return c;}
  vec3 mat(vec3 p, vec3 n){
    float body=dBody(p,u_size), corners=dCorners(p,u_size), rods=dRods(p,u_size);
    if(rods<body && rods<corners) return vec3(0.60,0.62,0.65);     // galvanized locking rods
    if(corners<body) return vec3(0.30,0.31,0.34);                  // corner castings
    vec3 base=vec3(0.165,0.185,0.215);                             // charcoal steel
    float side=step(0.6,abs(n.z));
    float front=step(0.6,n.x);                                     // door end (+x)
    // AffordABox white decal on the long sides
    float ASPECT=6.4;
    float W=min(u_size.y*0.6*ASPECT, u_size.x*1.5);
    float H=W/ASPECT;
    vec2 uv=vec2(p.x/W+0.5, (p.y+u_size.y*0.04)/H+0.5);
    uv.x=mix(uv.x, 1.0-uv.x, step(0.0,n.z));
    float inuv=step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
    vec4 logo=texture2D(u_logo, clamp(uv,0.0,1.0));
    base=mix(base, logo.rgb, logo.a*side*inuv);
    // cargo-door center seam on the front
    base=mix(base, base*0.55, smoothstep(0.035,0.0,abs(p.z))*front);
    return base;
  }
  void main(){
    vec2 uv=(gl_FragCoord.xy-0.5*u_res)/u_res.y;
    float ry=u_time*0.13 + u_mouse.x*0.5;
    float pit=0.32 - u_mouse.y*0.12;
    vec3 ro=vec3(0.0,0.0,9.7);
    ro=rotY(ry)*ro; ro.y=3.4*sin(pit);
    vec3 ta=vec3(0.0,-0.10,0.0);
    vec3 f=normalize(ta-ro), rgt=normalize(cross(vec3(0,1,0),f)), up=cross(f,rgt);
    vec3 rd=normalize(uv.x*rgt+uv.y*up+1.5*f);
    float t=0.0; float hit=-1.0;
    for(int i=0;i<I;i++){vec3 p=ro+rd*t;float d=map(p);if(d<0.001){hit=t;break;}t+=d;if(t>44.0)break;}
    vec3 col=sky(rd);
    if(hit>0.0){
      vec3 p=ro+rd*hit; vec3 n=nrm(p);
      bool isObj = mapObj(p) < 0.02;
      // corrugation: vertical ribs on the four walls (fake via normal bump)
      if(isObj){
        float sideZ=step(0.55,abs(n.z));
        float endX=step(0.55,abs(n.x));
        n.x += cos(p.x*9.5)*sideZ*0.46;
        n.z += cos(p.z*9.5)*endX*0.46;
        n=normalize(n);
      }
      vec3 alb = isObj ? mat(p,n) : vec3(0.80,0.79,0.77);
      vec3 L=normalize(vec3(-0.5,0.82,0.42));
      float sh=shadow(p+n*0.02,L);
      float dif=max(dot(n,L),0.0)*sh;
      float occ=ao(p,n);
      vec3 lit = alb*(vec3(0.50,0.53,0.58)*occ + dif*vec3(1.05,1.0,0.92));
      vec3 A=normalize(vec3(0.62,0.28,-0.7));
      lit += alb*max(dot(n,A),0.0)*vec3(0.85,1.0,0.85)*0.16*u_amber;
      vec3 h=normalize(L-rd);
      lit += pow(max(dot(n,h),0.0),42.0)*vec3(1.0,0.98,0.9)*sh*(isObj?0.55:0.12);
      float fr=pow(1.0-max(dot(n,-rd),0.0),3.5);
      lit += fr*vec3(0.80,0.87,0.95)*0.26;
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
    logoImg.src=(window.__QX_LOGO_URL)||"/affordabox-logo-decal-white.png";
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
      gl.uniform1f(u.time, RM?1.2:(now-state.t0)/1000);
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

  // [half-length, half-height, half-width]; 40' ~2x length, HC ~+height
  const sizeFor = (is40, isHC) => [ is40 ? 3.5 : 2.0, isHC ? 1.12 : 1.0, 0.92 ];
  const sizes = cfg.sizes;
  const byKey = (k) => sizes.find((x) => x.key === k) || sizes[0];

  const params = new URLSearchParams(location.search);
  const incZip = params.get("zip_code") || params.get("zip") || "";
  const incSize = params.get("size") || "";
  let startKey = cfg.defaultKey;
  if (incSize) { const m = sizes.find((s) => s.key === incSize || String(s.len) === String(incSize).replace(/\D/g, "")); if (m) startKey = m.key; }
  const state = { size: startKey, svc: "buy-used", zip: incZip };

  const d0 = byKey(state.size);
  const boxR = makeRenderer($("gl-box"), { size: sizeFor(d0.len === 40, d0.hc), amber: 0.7 });

  const si = document.querySelector(`input[name="size"][value="${state.size}"]`); if (si) si.checked = true;
  if (state.zip && $("zip")) $("zip").value = state.zip;

  function fuseUrl() {
    const s = byKey(state.size), v = cfg.svc[state.svc];
    const p = new URLSearchParams();
    p.set("product_type", v.fuse);
    if (state.zip) p.set("zip_code", state.zip);
    p.set("size", String(s.len)); // hint until Fuse product_ids are wired
    return cfg.fuseBase + "?" + p.toString();
  }

  let tweenId = 0;
  function tween(el, to) {
    const from = parseInt((el.textContent || "").replace(/[^0-9]/g, "")) || 0;
    if (RM) { el.textContent = money(to); return; }
    const id = ++tweenId, t0 = performance.now(), dur = 500;
    (function step(now) { if (id !== tweenId) return;
      const k = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - k, 3);
      el.textContent = money(Math.round(from + (to - from) * e));
      if (k < 1) requestAnimationFrame(step);
    })(performance.now());
  }

  function render() {
    const s = byKey(state.size), v = cfg.svc[state.svc];
    $("sku").textContent = `${s.label.replace("Standard", "STD").replace("High-Cube", "HC").toUpperCase()} · ${v.sku}`;
    $("svc-label").textContent = v.name;
    $("tag-h").textContent = s.height;
    $("tag-l").textContent = s.len + "'";
    $("tag-v").textContent = s.cuft.toLocaleString() + " ft³";
    $("capacity").textContent = "wind & water-tight";
    if (boxR) boxR.setSize(sizeFor(s.len === 40, s.hc));

    const rows = [];
    if (v.mode === "buy") {
      $("qh-lab").textContent = "Purchase — one-time";
      const price = v.cond === "new" ? s.priceNew : s.priceUsed;
      rows.push(`<div class="li"><div class="name">${s.label}<small>${v.cond === "new" ? "new · one-trip" : "used · cargo-worthy"} · ${s.cuft.toLocaleString()} ft³</small></div><div class="amt">${price != null ? money(price) : "Quoted by ZIP"}</div></div>`);
      rows.push(`<div class="li"><div class="name">Delivery<small>tilt-bed to your site</small></div><div class="amt">Quoted by ZIP</div></div>`);
      rows.push(`<div class="li"><div class="name">Wind &amp; water-tight<small>lockable cargo doors</small></div><div class="amt">Included</div></div>`);
      $("lines").innerHTML = rows.join("");
      if (price != null) { tween($("total"), price); $("per").textContent = "one-time"; }
      else { $("total").textContent = "Quoted"; $("per").textContent = "by ZIP"; }
    } else {
      $("qh-lab").textContent = "Monthly recurring";
      const rent = cfg.rentFrom;
      rows.push(`<div class="li"><div class="name">${s.label} rental<small>month-to-month · ${s.cuft.toLocaleString()} ft³</small></div><div class="amt">${rent != null ? money(rent) + "<em>/mo</em>" : "Quoted by ZIP"}</div></div>`);
      rows.push(`<div class="li"><div class="name">Delivery &amp; pickup<small>tilt-bed, both ways</small></div><div class="amt">Quoted by ZIP</div></div>`);
      $("lines").innerHTML = rows.join("");
      if (rent != null) { tween($("total"), rent); $("per").textContent = "/mo"; }
      else { $("total").textContent = "Quoted"; $("per").textContent = "by ZIP"; }
    }

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

