# 메인 시안 A/B/C 생성: klik.html(=index.html)을 복사해 바꾼다. 공개 페이지는 건드리지 않음.
#   공통: 제목 위계 복구, 히어로 버튼, 상세 창 "작동 예시"(자동 생성), 썸네일 타이포 타일
#   A: 공통만   B: A + 순위 칸 5개 → 탭 하나   C: A + 전체 도구를 위로, 썸네일 없는 컴팩트 카드, 순위는 탭으로 아래
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Get-Content (Join-Path $here "..\index.html") -Raw -Encoding UTF8
function Must($s, $old, $new, $label) { if (-not $s.Contains($old)) { throw "못 찾음: $label" }; return $s.Replace($old, $new) }

# ---- 공통 ----
$s = $src
$s = Must $s 'fetch("catalog.json"' 'fetch("../catalog.json"' "catalog"
$s = Must $s 'src="community-config.js?t=' 'src="../community-config.js?t=' "config"
$s = $s.Replace('"media/', '"../media/')
$s = Must $s '<div class="step">② 작동 화면 보기</div>' '<div class="step">② 한글 설명·작동 예시 보기</div>' "step2"
$s = Must $s '        <div class="step">③ 설치 버튼 딸깍</div>
      </div>' '        <div class="step">③ 설치 버튼 딸깍</div>
      </div>
      <div class="hero-cta"><button class="install" data-open="pptx">⚡ 첫 도구 딸깍해 보기 — 파워포인트 자동 제작</button><span class="hero-sub">처음 한 번만 도우미(30초)를 받습니다 · 그다음부턴 버튼 하나</span></div>' "hero-cta"
# 썸네일: 가짜 창 대신 영문 이름 타이포 타일
$s = Must $s '${win(it.color)}' '${win(it.color, false, it.en)}' "win-call"
$s = Must $s 'function win(color, big) {
  return `<div class="thumb" style="background:${color}">' 'function win(color, big, en) {
  return `<div class="thumb" style="background:${color}" data-t="${esc((en||"").split(/[ (]/)[0])}">' "win-def"
# 상세 창: 설치 칸 다음에 "작동 예시" 칸
$demo = @'
        <section class="zone zone-demo">
          <h3>작동 예시</h3>
          <div class="dm" style="--c:${it.color}">
            <div class="dm-row you"><span class="dm-av">나</span><div class="dm-bub">${esc(tryPrompt(it)||checkPrompt(it))}</div></div>
            <div class="dm-row ai"><span class="dm-av ai">C</span><div class="dm-bub"><b>${esc(it.name)}</b>${esc(it.one)}</div></div>
            <div class="dm-out">✓ ${it.kind==="mcp"?"서비스가 연결돼 Claude가 직접 다룹니다":it.kind==="skill"?"결과물이 바로 나옵니다":"Claude에 이 기능이 더해집니다"}</div>
          </div>
          ${(()=>{ const r=Array.isArray(it.readme_ko)?it.readme_ko:[]; const pick=r.find(x=>/달라|특징|기능|왜|장점|할 수|하는 일|무엇/.test(x.h))||r.find(x=>String(x.p).length>80&&!/이란|란\?|소개|설치|시작/.test(x.h))||r[0]; if(!pick) return ""; const p=String(pick.p); return `<div class="dm-more"><b>${esc(pick.h)}</b><p>${esc(p.length>240?p.slice(0,240)+"…":p)}</p>${p.length>240?`<button class="dm-link" data-open-readme>원문 한글판에서 더 보기 ▾</button>`:""}</div>`; })()}
          <p class="dm-cap"><b>이런 분께</b> ${esc(it.when)}</p>
        </section>
        <section class="zone">
          <h3>알아보기</h3>
'@
$s = Must $s '        <section class="zone">
          <h3>알아보기</h3>
' $demo "demo-zone"
# 원문 더 보기 버튼 → 아래 details 펼치기
$s = Must $s 'if (t.dataset.copy !== undefined' 'if (t.hasAttribute("data-open-readme")) { const d = document.querySelector("#modal details.readme"); if (d) { d.open = true; d.scrollIntoView({ block: "start", behavior: "smooth" }); } return; }
  if (t.dataset.copy !== undefined' "readme-link"

$commonCss = @'
<style id="siann-common">
.hero-main h1 { font-size: clamp(28px, 3.4vw, 46px) !important; line-height: 1.1 !important; }
.sec-head h2 { font-size: 26px !important; }
.stat b { font-size: 44px !important; }
.hero-cta { display:flex; align-items:center; gap:14px; flex-wrap:wrap; margin-top:18px; }
.hero-cta .install { padding:14px 22px; font-size:16px; border-radius:980px; }
.hero-sub { font-size:13px; color:var(--muted); }
.thumb .win { display:none; }
.thumb { aspect-ratio: 16/6; display:grid; place-items:center; }
.thumb::after { content: attr(data-t); font-size: 30px; font-weight: 800; letter-spacing: -.03em; color: rgba(0,0,0,.5); padding: 0 16px; max-width:100%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.zone-demo .dm { background: color-mix(in srgb, var(--c) 55%, #fff); border-radius:16px; padding:16px; display:flex; flex-direction:column; gap:10px; }
.dm-row { display:flex; gap:10px; align-items:flex-start; }
.dm-row.ai { flex-direction:row; }
.dm-av { flex:none; width:28px; height:28px; border-radius:50%; background:#fff; color:var(--fg); font-size:12px; font-weight:700; display:grid; place-items:center; box-shadow:0 1px 3px rgba(0,0,0,.12); }
.dm-av.ai { background:var(--accent); color:#fff; }
.dm-bub { background:#fff; border-radius:14px; padding:10px 14px; font-size:14px; line-height:1.5; max-width:92%; box-shadow:0 1px 3px rgba(0,0,0,.06); }
.dm-row.you .dm-bub { background:var(--accent); color:#fff; }
.dm-bub b { display:block; font-size:12px; color:var(--accent); margin-bottom:3px; }
.dm-out { align-self:flex-end; font-size:12.5px; font-weight:700; color:#15803d; background:#ecfdf3; border-radius:980px; padding:5px 12px; }
.dm-more { margin-top:12px; background:var(--bg); border-radius:12px; padding:12px 14px; }
.dm-more b { display:block; font-size:13px; margin-bottom:4px; }
.dm-more p { margin:0; font-size:13.5px; line-height:1.6; color:var(--fg); }
.dm-link { margin-top:6px; border:0; background:transparent; color:var(--accent); font-weight:700; font-size:13px; padding:0; }
.dm-cap { margin:10px 0 0; font-size:13px; color:var(--muted); } .dm-cap b { color:var(--accent); margin-right:6px; }
</style>
</head>
'@
$s = Must $s '</head>' $commonCss "head"

# ---- 탭 스크립트 (B·C 공용) ----
function TabScript($keys, $anchorExpr, $after) {
  $keysJs = ($keys | ForEach-Object { "['$($_.Split('|')[0])','$($_.Split('|')[1])']" }) -join ","
  return @"
<script>
(function(){
  const SECS=[$keysJs];
  const anchor=$anchorExpr; if(!anchor) return;
  const wrap=document.createElement('section'); wrap.id='rank-tabs';
  wrap.innerHTML='<div class="sec-head"><div><h2 id="rt-h2"></h2><p id="rt-p"></p></div><div class="seg" id="rankseg" role="group" aria-label="순위 종류"></div></div><div id="rt-body"></div>';
  $(if ($after) { "anchor.parentNode.insertBefore(wrap, anchor.nextSibling);" } else { "anchor.parentNode.insertBefore(wrap, anchor);" })
  const seg=wrap.querySelector('#rankseg'), body=wrap.querySelector('#rt-body');
  const items=SECS.map(([k,label])=>{ const s=document.querySelector('section[data-sec="'+k+'"]'); if(!s) return null; const h=s.querySelector('.sec-head h2'), p=s.querySelector('.sec-head p'), rank=s.querySelector('.rank'); return {k,label,s,h:h?h.textContent:'',p:p?p.textContent:'',sub:p&&p.id==='rank-sub'?p:null,rank}; }).filter(Boolean);
  items.forEach(it=>{ it.s.style.display='none'; body.appendChild(it.rank); it.rank.dataset.sec=it.k; const b=document.createElement('button'); b.textContent=it.label; b.dataset.rt=it.k; seg.appendChild(b); });
  function show(k){ const it=items.find(x=>x.k===k); if(!it) return; items.forEach(x=>{ x.rank.hidden=x.k!==k; }); seg.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed', b.dataset.rt===k)); wrap.querySelector('#rt-h2').textContent=it.h; wrap.querySelector('#rt-p').textContent=it.sub?it.sub.textContent:it.p; }
  seg.addEventListener('click',e=>{ const b=e.target.closest('button[data-rt]'); if(b) show(b.dataset.rt); });
  const sync=()=>{ items.forEach(it=>{ const btn=seg.querySelector('[data-rt="'+it.k+'"]'); btn.hidden=!it.rank.children.length; }); };
  const obs=new MutationObserver(sync); items.forEach(it=>obs.observe(it.rank,{childList:true})); sync();
  show(SECS[0][0]);
})();
</script>
</body>
"@
}

# ---- A ----
$a = $s
Set-Content (Join-Path $here "main-a.html") $a -Encoding UTF8

# ---- B: 순위 5개 → 탭, 전체 도구를 질문 광장 앞으로 ----
$b = $s
$tabB = TabScript @("md|편집팀 필수","gh|깃허브 별","sh|실제 설치","hot|이달 상승","week|이번 주") 'document.querySelector(''section[data-sec="md"]'')' $false
$b = Must $b '</body>' ($tabB + '<script>(function(){ const g=document.getElementById("grid").closest("section"), p=document.getElementById("cm-plaza"); if(g&&p) p.parentNode.insertBefore(g, p); })();</script>
</body>') "body-b"
Set-Content (Join-Path $here "main-b.html") $b -Encoding UTF8

# ---- C: 필수 10개 → 전체 도구(컴팩트) → 순위 탭 → 소식 → 질문 광장 ----
$c = $s
$tabC = TabScript @("gh|깃허브 별","sh|실제 설치","hot|이달 상승","week|이번 주") 'document.getElementById("grid").closest("section")' $true
$c = Must $c '</body>' ($tabC + '<script>(function(){ const md=document.querySelector(''section[data-sec="md"]''), g=document.getElementById("grid").closest("section"), p=document.getElementById("cm-plaza"), n=document.querySelector(''section[data-sec="new"]''); if(md&&g) md.parentNode.insertBefore(g, md.nextSibling); if(p&&n) n.parentNode.insertBefore(p, n.nextSibling); })();</script>
<style>
.thumb { display:none; }
.badge-row { position:static !important; display:flex; gap:6px; padding:16px 18px 0; }
.badge-row:empty { display:none; }
.card .fav { top:12px; right:12px; }
.cbody { padding-top:14px; }
.grid { grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); }
</style>
</body>') "body-c"
Set-Content (Join-Path $here "main-c.html") $c -Encoding UTF8
Write-Host "생성: main-a.html main-b.html main-c.html"

