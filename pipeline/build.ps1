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

@{ generated_at = (Get-Date).ToUniversalTime().ToString("o"); count = $catalog.Count; pending = $pending; rejected = $rejected; items = $catalog } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $site "catalog.json") -Encoding UTF8
$newsJson = if ($allNews) { ConvertTo-Json -InputObject @($allNews) -Depth 4 } else { "[]" }   # 0건이어도 빈 배열 파일을 남긴다
Set-Content -Path $newsPath -Value $newsJson -Encoding UTF8
Write-Host "카탈로그: 진열 $($catalog.Count)개 (시드 $($seed.Count) + 자동 $i), 검수 대기 $pending, 보류 $rejected, 새 소식 $($news.Count)건"
