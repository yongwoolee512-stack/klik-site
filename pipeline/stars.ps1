# 깃허브 신호 수집: 별 수(실시간)·마지막 업데이트·이달 별 증가
# 결과: data/gh_signals.json {id: {stars, pushed_at, stars30, days}}  +  data/stars_history.json (날짜별 별 수, 증가 계산용)
# 토큰: Git에 저장된 깃허브 로그인(git credential fill)을 쓴다. 없으면 로그인 없이(시간당 60회) 돈다.
# shortcut: 별 증가는 우리가 매일 찍은 기록으로만 계산한다(깃허브는 별 4만 개까지만 날짜를 줌), 기록이 하루 미만이면 표시 안 함
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$today = (Get-Date).ToString("yyyy-MM-dd")

$seed = @(Get-Content (Join-Path $root "data\seed.json") -Raw -Encoding UTF8 | ConvertFrom-Json)
foreach ($extra in "seed_community.json", "seed_official.json", "seed_popular.json", "seed_skillssh.json", "seed_night.json") { $cp = Join-Path $root "data\$extra"; if (Test-Path $cp) { $seed += @(Get-Content $cp -Raw -Encoding UTF8 | ConvertFrom-Json) } }

$headers = @{ "Accept" = "application/vnd.github+json"; "User-Agent" = "klik-pipeline" }
if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }   # GitHub Actions
else { try { $cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null; $tok = ($cred | Where-Object { $_ -like "password=*" }) -replace '^password=', ''; if ($tok) { $headers["Authorization"] = "Bearer $tok" } } catch {} }

$histPath = Join-Path $root "data\stars_history.json"
$hist = @{}
if (Test-Path $histPath) { (Get-Content $histPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h = @{}; $_.Value.PSObject.Properties | ForEach-Object { $h[$_.Name] = [int]$_.Value }; $hist[$_.Name] = $h } }

$out = [ordered]@{}
foreach ($it in $seed) {
  if ($it.repo -notmatch '^https://github\.com/([^/]+)/([^/#?]+)') { continue }
  $full = "$($Matches[1])/$($Matches[2])"
  try { $r = Invoke-RestMethod "https://api.github.com/repos/$full" -Headers $headers -TimeoutSec 30 } catch { Write-Host "$($it.id): 실패 ($($_.Exception.Message))"; continue }
  if (-not $hist[$it.id]) { $hist[$it.id] = @{} }
  $hist[$it.id][$today] = [int]$r.stargazers_count
  # 30일 안의 가장 오래된 기록과 비교
  $cut = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
  $old = $hist[$it.id].Keys | Where-Object { $_ -ge $cut -and $_ -lt $today } | Sort-Object | Select-Object -First 1
  $pushed = ([datetime]$r.pushed_at).ToUniversalTime().ToString("o")   # Invoke-RestMethod가 날짜를 DateTime으로 바꿔 놓으므로 다시 문자열로
  $entry = [ordered]@{ stars = [int]$r.stargazers_count; pushed_at = $pushed; open_issues = [int]$r.open_issues_count }
  if ($old) { $entry.stars30 = [int]$r.stargazers_count - $hist[$it.id][$old]; $entry.days = ([datetime]$today - [datetime]$old).Days }
  $out[$it.id] = $entry
  Write-Host ("$($it.id): ★ $($r.stargazers_count)  업데이트 $($pushed.Substring(0,10))" + $(if ($old) { "  +$($entry.stars30) / $($entry.days)일" } else { "" }))
}
$out | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $root "data\gh_signals.json") -Encoding UTF8
$hist | ConvertTo-Json -Depth 3 | Set-Content $histPath -Encoding UTF8
Write-Host "깃허브 신호 $($out.Count)개 저장"
