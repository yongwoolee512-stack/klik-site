# 4단계 카탈로그 생성: 편집팀 시드(seed.json) + 자동 수집 결과를 합쳐 사이트가 읽는 두 파일을 만든다.
#   site/catalog.json : 진열할 도구 (published만)   site/news.json : 신상 소식 (신규·업데이트·보류)
# 지난 실행 결과(data/state.json)와 비교해 "새로 올라온 것 / 바뀐 것"을 뉴스로 만든다.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$site = Join-Path $root "site"; New-Item -ItemType Directory -Force $site | Out-Null
$today = (Get-Date).ToString("yyyy-MM-dd")

$seed = @(Get-Content (Join-Path $root "data\seed.json") -Raw -Encoding UTF8 | ConvertFrom-Json)
# 편집팀이 고른 커뮤니티 도구(공식 Claude 앱 목록에 없는 것): 등급(trust)을 항목마다 직접 적는다
foreach ($extra in "seed_community.json", "seed_official.json", "seed_popular.json", "seed_skillssh.json") { $p = Join-Path $root "data\$extra"; if (Test-Path $p) { $seed += @(Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } }
$auto = Get-Content (Join-Path $root "data\summarized.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$statePath = Join-Path $root "data\state.json"
$prev = @{}
if (Test-Path $statePath) { (Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $prev[$_.Name] = $_.Value } }

$COLORS = @("#f3d9c4","#cfe6d6","#d6dcf0","#f0e0d6","#e0d6f0","#f5d8e4","#d6ecf5","#dcdcdc","#d6f0e8","#f0ead6")
function Install-Spec($it) {
  # 딸깍 링크에 필요한 설치 정보 (helper.ps1이 검증할 수 있는 형태만)
  if ($it.remote -and $it.remote.url) { return @{ kind = "mcp"; transport = $it.remote.transport; url = $it.remote.url } }
  if ($it.npm_pkg) { return @{ kind = "mcp"; pkg = $it.npm_pkg } }
  if ($it.kind -eq "plugin" -or $it.kind -eq "skill") { return @{ kind = "plugin"; name = $it.name; market = $it.full_name } }
  return $null
}

$catalog = @(); $news = @(); $pending = 0; $rejected = 0
# 1) 편집팀 시드: 그대로 진열 (한글 설명은 사람이 쓴 것)
# 편집팀 한글 번역본(readme_ko.json): 값이 문자열이면 다른 항목의 번역을 그대로 쓴다는 뜻 (예: "xlsx": "pptx")
$rk = @{}
$rkPath = Join-Path $root "data\readme_ko.json"
foreach ($f in $rkPath, (Join-Path $root "data\readme_ko_community.json"), (Join-Path $root "data\readme_ko_official.json"), (Join-Path $root "data\readme_ko_popular.json"), (Join-Path $root "data\readme_ko_skillssh.json")) {
  if (Test-Path $f) { (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Name -ne "_doc" } | ForEach-Object { $rk[$_.Name] = $_.Value } }
}
# 짧은 영상 링크(videos.json): 사용자가 토스한 유튜브·인스타·틱톡 주소
$vids = @{}
$vidPath = Join-Path $root "data\videos.json"
if (Test-Path $vidPath) { (Get-Content $vidPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Name -ne "_doc" -and $_.Value.Count -gt 0 } | ForEach-Object { $vids[$_.Name] = @($_.Value) } }
# 자동 수집한 쇼츠(videos.ps1)는 사람이 넣은 것 뒤에, 같은 주소는 한 번만
$autoPath = Join-Path $root "data\videos_auto.json"
if (Test-Path $autoPath) { (Get-Content $autoPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $have = @($vids[$_.Name] | ForEach-Object { $_.url }); $vids[$_.Name] = @($vids[$_.Name] | Where-Object { $_ }) + @($_.Value | Where-Object { $have -notcontains $_.url }) } }
# 깃허브 신호(stars.ps1): 실시간 별 수로 덮어쓰고, 마지막 업데이트·이달 증가를 붙인다
$gh = @{}
$ghPath = Join-Path $root "data\gh_signals.json"
if (Test-Path $ghPath) { (Get-Content $ghPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $gh[$_.Name] = $_.Value } }
# skills.sh 설치 수(skillssh.ps1): id → { installs, week }
$sh = @{}; $shPath = Join-Path $root "data\skillssh.json"; if (Test-Path $shPath) { (Get-Content $shPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | % { $sh[$_.Name] = $_.Value } }
# MD 추천: data/picks.json {id: 한 줄 이유}
$picks = @{}; $pkPath = Join-Path $root "data\picks.json"; if (Test-Path $pkPath) { (Get-Content $pkPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ? { $_.Name -ne "_doc" } | % { $picks[$_.Name] = $_.Value } }
foreach ($s in $seed) {
  $s | Add-Member status "published" -Force
  if ($vids[$s.id]) { $s | Add-Member videos $vids[$s.id] -Force }
  $g = $gh[$s.id]
  if ($g) { $s | Add-Member stars ([int]$g.stars) -Force; $s | Add-Member pushed_at $g.pushed_at -Force; if ($g.PSObject.Properties["stars30"]) { $s | Add-Member stars30 ([int]$g.stars30) -Force; $s | Add-Member stars30_days ([int]$g.days) -Force } }
  if (-not $s.trust) { $s | Add-Member trust @{ grade = "verified"; reasons = @("편집팀 검수") } -Force }
  if ($picks[$s.id]) { $s | Add-Member pick $picks[$s.id] -Force }   # MD 추천(편집팀 픽) 이유
  if ($sh[$s.id]) { $s | Add-Member sh_installs ([int]$sh[$s.id].installs) -Force; $s | Add-Member sh_week ([int]$sh[$s.id].week) -Force
    # skills.sh 에서 가져온 도구(sh_source 있음)는 원문 페이지도 skills.sh 로 — 깃허브가 아니라 그 사이트가 출처
    if ($s.sh_source) { $s | Add-Member sh_url "https://skills.sh/$($sh[$s.id].source)/$($sh[$s.id].skill)" -Force } }
  # 시드에 빠진 기본값 (사이트가 .map/.installs 를 그대로 쓰므로 비어 있으면 상세 창이 안 열린다)
  if (-not $s.plat) { $s | Add-Member plat @("claude-code") -Force }
  if ($null -eq $s.installs) { $s | Add-Member installs 0 -Force }
  if ($null -eq $s.stars) { $s | Add-Member stars 0 -Force }
  if (-not $s.tips) { $s | Add-Member tips @() -Force }
  $r = $rk[$s.id]; if ($r -is [string]) { $r = $rk[$r] }
  if ($r) { $s | Add-Member readme_ko $r -Force }
  # 등록일(added)이 적힌 항목은 그날 "등록" 소식을 낸다 (같은 제목이 이미 있으면 건너뜀)
  if ($s.added) { $news += @{ date = $s.added; type = "new"; title = "$($s.name) 등록"; sub = $s.one; ref = $s.id } }
  $catalog += $s
}
$seedIds = @($seed | ForEach-Object { $_.id })

# 2) 자동 수집
$i = 0
foreach ($it in $auto.items) {
  $slug = ($it.full_name -replace '[^A-Za-z0-9]+','-').ToLower().Trim('-')
  if ($seedIds -contains $slug) { continue }
  $p = $prev[$it.id]
  # 보류 항목은 뉴스로 내보내지 않는다(위험 신호가 있는 것은 더더욱). 검수 대기 중 별 100개 이상만 "새로 발견"으로 예고.
  if ($it.status -eq "rejected") { $rejected++; continue }
  if ($it.status -eq "pending") { $pending++; if (-not $p -and [int]$it.stars -ge 100) { $news += @{ date = $today; type = "found"; title = "새로 발견: $($it.name)"; sub = "검수·한글 요약 대기 중 (★ $($it.stars))"; ref = $null } }; continue }
  $ko = $it.ko
  $entry = @{
    id = $slug; kind = $it.kind; cat = $ko.category; name = $ko.name_ko; en = $it.name; one = $ko.one; when = $ko.when; tips = @($ko.tips); note = $ko.note
    level = $ko.level; stars = [int]$it.stars; installs = 0; plat = @("claude-code"); color = $COLORS[$i % $COLORS.Count]; repo = $it.url
    install = (Install-Spec $it); trust = $it.trust; status = "published"; isNew = (-not $p); updated_at = $it.updated_at
  }
  $catalog += $entry; $i++
  if (-not $p) { $news += @{ date = $today; type = "new"; title = "$($ko.name_ko) 등록"; sub = $ko.one; ref = $slug } }
  elseif ($p.updated_at -ne $it.updated_at) { $news += @{ date = $today; type = "upd"; title = "$($ko.name_ko) 업데이트"; sub = "저장소가 갱신됐습니다"; ref = $slug } }
}

# 3) 상태 저장 (다음 실행 때 비교용)
$state = @{}
foreach ($it in $auto.items) { $state[$it.id] = @{ updated_at = $it.updated_at; status = $it.status; seen = $today } }
$state | ConvertTo-Json -Depth 4 | Set-Content $statePath -Encoding UTF8

# 4) 뉴스는 기존 뉴스에 누적 (최근 60건)
$newsPath = Join-Path $site "news.json"
$oldNews = if (Test-Path $newsPath) { @(Get-Content $newsPath -Raw -Encoding UTF8 | ConvertFrom-Json) } else { @() }
$oldTitles = @($oldNews | ForEach-Object { "$($_.date)|$($_.title)" })
$news = @($news | Where-Object { $oldTitles -notcontains "$($_.date)|$($_.title)" })
$allNews = @($news) + @($oldNews) | Select-Object -First 60

$generatedAt = (Get-Date).ToUniversalTime()
@{ generated_at = $generatedAt.ToString("o"); count = $catalog.Count; pending = $pending; rejected = $rejected; items = $catalog } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $site "catalog.json") -Encoding UTF8
$newsJson = if ($allNews) { ConvertTo-Json -InputObject @($allNews) -Depth 4 } else { "[]" }   # 0건이어도 빈 배열 파일을 남긴다
Set-Content -Path $newsPath -Value $newsJson -Encoding UTF8
Write-Host "카탈로그: 진열 $($catalog.Count)개 (시드 $($seed.Count) + 자동 $i), 검수 대기 $pending, 보류 $rejected, 새 소식 $($news.Count)건"

# 5) 도구별 정적 페이지(tools/<id>.html) + sitemap.xml — 검색엔진이 168개 한글 설명을 각각 색인하도록.
#    상세 창(?open=<id>)은 JS 모달이라 검색에 안 잡힌다. 페이지는 빌드마다 전부 지우고 다시 만든다.
$siteRoot = (Resolve-Path (Join-Path $root "..")).Path
$BASE = "https://yongwoolee512-stack.github.io/klik-site"
$toolsDir = Join-Path $siteRoot "tools"
if (Test-Path $toolsDir) { Remove-Item $toolsDir -Recurse -Force }
New-Item -ItemType Directory -Force $toolsDir | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$CAT_KO = @{ design = "디자인"; dev = "개발"; docs = "문서·글쓰기"; data = "데이터·엑셀"; marketing = "마케팅·SNS"; web = "웹사이트·호스팅"; work = "업무 연결"; auto = "자동화·생산성" }
$KIND_KO = @{ skill = "스킬"; plugin = "플러그인"; mcp = "MCP" }
function esc($s) { if ($null -eq $s) { return "" }; return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function escNl($s) { return ((esc $s) -replace "`r?`n", "<br>") }   # readme 본문의 줄바꿈(• 목록)은 <br>
$PAGE_CSS = @"
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}body{margin:0;background:#fff;color:#1d1d1f;font:16px/1.65 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Malgun Gothic","Segoe UI",Roboto,sans-serif;word-break:keep-all}
main{max-width:720px;margin:0 auto;padding:28px 16px 64px}header.top{max-width:720px;margin:0 auto;padding:14px 16px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #e5e5ea}
a{color:#0b2a6f}.brand{font-weight:800;text-decoration:none;color:#0b2a6f;letter-spacing:-.02em}.meta{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 14px}
.tag{display:inline-block;padding:3px 10px;border-radius:999px;background:#f2f4f8;color:#0b2a6f;font-size:13px;font-weight:600}
h1{font-size:30px;line-height:1.25;letter-spacing:-.02em;margin:6px 0 4px}.en{color:#6e6e73;font-size:16px;margin:0 0 14px}.one{font-size:19px;margin:0 0 22px}
h2{font-size:19px;margin:30px 0 8px;letter-spacing:-.01em}h3{font-size:16px;margin:18px 0 4px}p{margin:0 0 10px}ul{margin:0;padding-left:20px}li{margin:4px 0}
.cta{display:inline-block;padding:14px 26px;border-radius:999px;background:#0b2a6f;color:#fff;font-weight:700;font-size:17px;text-decoration:none;box-shadow:0 6px 18px rgba(11,42,111,.22)}
.cta:hover{background:#0a2459}.ctabox{margin:26px 0 8px;padding:20px;border-radius:16px;background:#f5f6fa;text-align:center}.ctabox p{margin:10px 0 0;color:#6e6e73;font-size:14px}
.stats{display:flex;flex-wrap:wrap;gap:10px 22px;color:#6e6e73;font-size:14px;margin:0 0 4px}.stats b{color:#1d1d1f}
footer{max-width:720px;margin:0 auto;padding:18px 16px 40px;color:#6e6e73;font-size:13px;border-top:1px solid #e5e5ea}footer a{margin-right:14px}
@media (max-width:480px){h1{font-size:26px}.one{font-size:17px}.cta{display:block}}
"@
$urls = [System.Collections.Generic.List[string]]::new()
$lastmod = $generatedAt.ToString("yyyy-MM-ddTHH:mm:ssZ")
foreach ($t in $catalog) {
  $id = [string]$t.id
  if ($id -notmatch '^[A-Za-z0-9._-]+$') { Write-Warning "건너뜀: 파일 이름으로 쓸 수 없는 id '$id'"; continue }
  $name = [string]$t.name; $en = [string]$t.en; $one = [string]$t.one
  $url = "$BASE/tools/$id.html"
  $src = if ($t.sh_url) { [string]$t.sh_url } else { [string]$t.repo }
  $srcLabel = if ($t.sh_url) { "skills.sh에서 원문 보기" } else { "GitHub 저장소 원문 보기" }
  $catKo = $CAT_KO[[string]$t.cat]; if (-not $catKo) { $catKo = [string]$t.cat }
  $kindKo = $KIND_KO[[string]$t.kind]; if (-not $kindKo) { $kindKo = [string]$t.kind }
  $ld = [ordered]@{ "@context" = "https://schema.org"; "@type" = "SoftwareApplication"; name = $name; alternateName = $en; description = $one; url = [string]$t.repo
    applicationCategory = $catKo; operatingSystem = "Claude Code"; offers = [ordered]@{ "@type" = "Offer"; price = "0"; priceCurrency = "USD" } }
  $ldJson = ($ld | ConvertTo-Json -Compress -Depth 4) -replace '</', '<\/'
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.Append("<!doctype html>`n<html lang=`"ko`">`n<head>`n<meta charset=`"utf-8`">`n<meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">`n")
  [void]$sb.Append("<title>$(esc $name) ($(esc $en)) 설치법·한글 설명 | 딸깍</title>`n")
  [void]$sb.Append("<meta name=`"description`" content=`"$(esc $one)`">`n<link rel=`"canonical`" href=`"$url`">`n")
  [void]$sb.Append("<meta property=`"og:type`" content=`"article`">`n<meta property=`"og:site_name`" content=`"딸깍`">`n<meta property=`"og:title`" content=`"$(esc $name) ($(esc $en)) 설치법·한글 설명`">`n")
  [void]$sb.Append("<meta property=`"og:description`" content=`"$(esc $one)`">`n<meta property=`"og:url`" content=`"$url`">`n<meta property=`"og:image`" content=`"$BASE/media/og.png`">`n<meta name=`"twitter:card`" content=`"summary_large_image`">`n")
  [void]$sb.Append("<link rel=`"icon`" href=`"../media/favicon.svg`" type=`"image/svg+xml`">`n")
  [void]$sb.Append("<script type=`"application/ld+json`">$ldJson</script>`n<style>$PAGE_CSS</style>`n</head>`n<body>`n")
  [void]$sb.Append("<header class=`"top`"><a class=`"brand`" href=`"../`">딸깍</a><a href=`"../`">전체 도구 보기</a></header>`n<main>`n")
  [void]$sb.Append("<div class=`"meta`"><span class=`"tag`">$(esc $kindKo)</span><span class=`"tag`">$(esc $catKo)</span></div>`n")
  [void]$sb.Append("<h1>$(esc $name)</h1>`n<p class=`"en`">$(esc $en)</p>`n<p class=`"one`">$(esc $one)</p>`n")
  $stats = @()
  if ([int]$t.stars -gt 0) { $stats += "<span>GitHub ★ <b>$(('{0:N0}' -f [int]$t.stars))</b></span>" }
  if ($t.sh_installs -and [int]$t.sh_installs -gt 0) { $stats += "<span>skills.sh 설치 <b>$(('{0:N0}' -f [int]$t.sh_installs))</b>회</span>" }
  if ($stats.Count) { [void]$sb.Append("<div class=`"stats`">$($stats -join '')</div>`n") }
  [void]$sb.Append("<div class=`"ctabox`"><a class=`"cta`" href=`"../?open=$id`">딸깍에서 한 번에 설치하기</a><p>설치 명령을 복사·실행하는 과정을 딸깍 홈에서 안내합니다.</p></div>`n")
  if ($t.when) { [void]$sb.Append("<h2>이런 분께</h2>`n<p>$(esc $t.when)</p>`n") }
  $tips = @($t.tips | Where-Object { $_ })
  if ($tips.Count) { [void]$sb.Append("<h2>사용 예시</h2>`n<ul>`n"); foreach ($tip in $tips) { [void]$sb.Append("<li>$(esc $tip)</li>`n") }; [void]$sb.Append("</ul>`n") }
  $rk = @($t.readme_ko | Where-Object { $_ })
  if ($rk.Count) {
    [void]$sb.Append("<h2>원문 설명 한글판</h2>`n")
    foreach ($sec in $rk) { if ($sec.h) { [void]$sb.Append("<h3>$(esc $sec.h)</h3>`n") }; if ($sec.p) { [void]$sb.Append("<p>$(escNl $sec.p)</p>`n") } }
  }
  [void]$sb.Append("<h2>출처</h2>`n<p><a href=`"$(esc $src)`" rel=`"noopener`" target=`"_blank`">$srcLabel</a></p>`n")
  [void]$sb.Append("<p style=`"margin-top:28px`"><a class=`"cta`" href=`"../?open=$id`">딸깍에서 한 번에 설치하기</a></p>`n</main>`n")
  [void]$sb.Append("<footer><a href=`"../`">딸깍 홈</a><a href=`"../terms.html`">이용약관</a><a href=`"../privacy.html`">개인정보</a><span>한글 설명은 딸깍 편집팀이 옮긴 것이며, 도구의 권리는 원저작자에게 있습니다.</span></footer>`n</body>`n</html>`n")
  [IO.File]::WriteAllText((Join-Path $toolsDir "$id.html"), $sb.ToString(), $utf8)
  $urls.Add("  <url><loc>$url</loc><lastmod>$lastmod</lastmod><changefreq>weekly</changefreq><priority>0.7</priority></url>")
}
$sitemap = @("<?xml version=`"1.0`" encoding=`"UTF-8`"?>", "<urlset xmlns=`"http://www.sitemaps.org/schemas/sitemap/0.9`">",
  "  <url><loc>$BASE/</loc><lastmod>$lastmod</lastmod><changefreq>daily</changefreq><priority>1.0</priority></url>",
  "  <url><loc>$BASE/terms.html</loc><lastmod>$lastmod</lastmod><changefreq>yearly</changefreq><priority>0.2</priority></url>",
  "  <url><loc>$BASE/privacy.html</loc><lastmod>$lastmod</lastmod><changefreq>yearly</changefreq><priority>0.2</priority></url>") + @($urls) + @("</urlset>")
[IO.File]::WriteAllText((Join-Path $siteRoot "sitemap.xml"), (($sitemap -join "`n") + "`n"), $utf8)
Write-Host "도구 페이지: tools/ $($urls.Count)개, sitemap.xml $($urls.Count + 3)개 URL"
