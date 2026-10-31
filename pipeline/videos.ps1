# 도구별 유튜브 쇼츠 자동 수집 (API 키 없음: 유튜브 검색 결과 페이지를 읽는다)
# 결과: data/videos_auto.json  {id: [{url, by, title}]}  → build.ps1이 사람이 넣은 videos.json 뒤에 붙인다
# shortcut: 유튜브가 검색 페이지 구조를 바꾸면 깨진다, 그때 Data API(키 필요)로 바꾼다
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36"
$PerTool = 3

$seed = @(Get-Content (Join-Path $root "data\seed.json") -Raw -Encoding UTF8 | ConvertFrom-Json)
foreach ($extra in "seed_community.json", "seed_official.json", "seed_popular.json", "seed_skillssh.json", "seed_night.json") { $cp = Join-Path $root "data\$extra"; if (Test-Path $cp) { $seed += @(Get-Content $cp -Raw -Encoding UTF8 | ConvertFrom-Json) } }
$outPath = Join-Path $root "data\videos_auto.json"
$prev = @{}; if (Test-Path $outPath) { (Get-Content $outPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $prev[$_.Name] = $_.Value } }

function Search-Shorts($q) {
  # sp=EgIYAQ== : 4분 미만만.  결과 HTML 안의 ytInitialData에서 videoId만 순서대로 뽑는다
  $u = "https://www.youtube.com/results?search_query=" + [uri]::EscapeDataString($q) + "&sp=EgIYAQ%253D%253D"
  try { $html = (Invoke-WebRequest $u -UserAgent $UA -Headers @{ "Accept-Language" = "ko-KR,ko;q=0.9,en;q=0.5" } -TimeoutSec 30).Content } catch { return @() }
  $ids = [regex]::Matches($html, '"videoId":"([\w-]{11})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  return @($ids | Select-Object -First 12)
}
function Get-Meta($id) {
  try { return Invoke-RestMethod "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$id&format=json" -UserAgent $UA -TimeoutSec 20 } catch { return $null }
}

$out = [ordered]@{}
foreach ($it in $seed) {
  $key = ($it.en -replace '\s*(MCP|skill|connector|plugin)\s*$', '').Trim()   # "Notion MCP" → "Notion"
  $koName = ($it.name -replace '\s*\(.*\)$', '') -replace ' 연결$', ''         # "노션 연결" → "노션"
  $ids = @(Search-Shorts "$key claude code") + @(Search-Shorts "$koName 클로드 코드") | Select-Object -Unique
  $picked = @()
  foreach ($id in $ids) {
    if ($picked.Count -ge $PerTool) { break }
    $m = Get-Meta $id; if (-not $m) { continue }
    $title = "$($m.title)"
    # 제목에 도구 이름(영문 또는 한글)이 있어야 관련 영상으로 본다 (예: "ponytail" 검색에 머리 묶는 영상 제외)
    if ($title -notmatch [regex]::Escape($key) -and $title -notmatch [regex]::Escape($koName)) { continue }
    $picked += [ordered]@{ url = "https://www.youtube.com/shorts/$id"; by = "$($m.author_name)"; title = $title }
  }
  if ($picked.Count) { $out[$it.id] = $picked; Write-Host "$($it.id): $($picked.Count)개  ($($picked[0].by): $($picked[0].title))" }
  elseif ($prev[$it.id]) { $out[$it.id] = $prev[$it.id]; Write-Host "$($it.id): 새로 못 찾음, 지난 결과 유지" }
  else { Write-Host "$($it.id): 없음" }
  Start-Sleep -Milliseconds 800
}
$out | ConvertTo-Json -Depth 4 | Set-Content $outPath -Encoding UTF8
Write-Host "영상 있는 도구 $($out.Count)/$($seed.Count)"
