# skills.sh(Vercel 스킬 레지스트리) 설치 수 수집.
#   data/skillssh_raw.json        : 전체 순위 원본 (약 1만 개 스킬)
#   data/skillssh.json            : 딸깍 도구 id → { installs, week, skill, skills_n, source }  (build.ps1이 읽음)
#   data/skillssh_candidates.json : 딸깍에 없는 저장소 중 설치 10만 회 이상 (신규 등록 후보)
# 설치 수는 저장소 안에서 가장 많이 깐 스킬 기준(저장소 하나를 깔면 스킬마다 1씩 세기 때문에 합산은 과장됨).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$MIN = 100000

$all = @(); $page = 0
$H = @{ "User-Agent" = "klik-pipeline (+https://yongwoolee512-stack.github.io/klik-site/)"; "Accept" = "application/json" }
while ($true) {
  $r = $null
  foreach ($wait in 0, 10, 30, 60) {   # 429(요청 과다)면 기다렸다 다시
    if ($wait) { Start-Sleep -Seconds $wait }
    try { $r = Invoke-RestMethod "https://www.skills.sh/api/skills/all-time/$page" -Headers $H -TimeoutSec 60; break } catch { if ($wait -eq 60) { throw }; Write-Host "  $page쪽 실패, $($wait+10)초 뒤 재시도: $($_.Exception.Message)" }
  }
  $all += @($r.skills)
  if (-not $r.hasMore) { break }
  if ($r.skills.Count -and [int]$r.skills[-1].installs -lt 500) { break }   # 설치 500회 미만은 쓸 일 없음 (약 10쪽에서 끝)
  $page++; Start-Sleep -Milliseconds 800
}
$all | ConvertTo-Json -Depth 4 -Compress | Set-Content (Join-Path $root "data\skillssh_raw.json") -Encoding UTF8
Write-Host "skills.sh: 스킬 $($all.Count)개 ($($page+1)쪽)"

# 저장소별 묶기
$byRepo = @{}
foreach ($s in $all) { $k = $s.source.ToLower(); if (-not $byRepo[$k]) { $byRepo[$k] = @() }; $byRepo[$k] += $s }

function Week($s) { $w = @($s.weeklyInstalls); if ($w.Count -ge 2) { [int]$w[$w.Count - 2] } else { 0 } }   # 마지막 칸은 진행 중인 주 → 직전 주 사용

$seed = @()
foreach ($f in "seed.json", "seed_community.json", "seed_official.json", "seed_popular.json", "seed_skillssh.json") { $p = Join-Path $root "data\$f"; if (Test-Path $p) { $seed += @(Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } }

# 시드에 sh_source(owner/repo)를 적으면 그 출처로 찾는다. 단, 카드가 설치하는 것과 다른 저장소(예: 노션 MCP 카드 ↔ 노션 스킬 저장소)를 이어 붙이면 안 된다 — 숫자가 거짓말이 된다.
# 그런 회사 공식 스킬 저장소(supabase/agent-skills, cloudflare/skills, stripe/ai …)는 별도 도구로 등록할 것.
$out = [ordered]@{}; $used = @{}
foreach ($it in $seed) {
  $repo = $it.sh_source
  if (-not $repo) { $repo = $it.full_name }
  if (-not $repo -and $it.repo -match 'github\.com/([^/]+/[^/#?]+)') { $repo = $Matches[1] }
  if (-not $repo) { continue }
  $k = $repo.ToLower().TrimEnd('/') -replace '\.git$', ''
  $list = $byRepo[$k]; if (-not $list) { continue }
  $used[$k] = $true
  # 같은 저장소를 여러 도구가 나눠 쓰면(anthropics/skills의 pptx·xlsx…) 이름이 맞는 스킬을, 아니면 가장 많이 깐 스킬을
  $pick = $list | Where-Object { $_.skillId -eq $it.id -or $_.skillId -eq $it.en -or $_.skillId -like "$($it.id)*" } | Sort-Object installs -Descending | Select-Object -First 1
  if (-not $pick) { $pick = $list | Sort-Object installs -Descending | Select-Object -First 1 }
  $out[$it.id] = @{ installs = [int]$pick.installs; week = (Week $pick); skill = $pick.skillId; skills_n = $list.Count; source = $pick.source }
}
$out | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $root "data\skillssh.json") -Encoding UTF8
Write-Host "딸깍 도구와 연결: $($out.Count)개"

# 신규 후보: 딸깍에 없는 저장소, 최다 스킬 설치 $MIN 이상
$cand = @()
foreach ($k in $byRepo.Keys) {
  if ($used[$k]) { continue }
  $top = $byRepo[$k] | Sort-Object installs -Descending | Select-Object -First 1
  if ([int]$top.installs -lt $MIN) { continue }
  $cand += [pscustomobject]@{ source = $top.source; installs = [int]$top.installs; week = (Week $top); top_skill = $top.skillId; skills_n = $byRepo[$k].Count; official = [bool]$top.isOfficial; skills = @($byRepo[$k] | Sort-Object installs -Descending | Select-Object -First 8 | ForEach-Object { $_.skillId }) }
}
$cand = @($cand | Sort-Object installs -Descending)
ConvertTo-Json -InputObject $cand -Depth 4 | Set-Content (Join-Path $root "data\skillssh_candidates.json") -Encoding UTF8
Write-Host "신규 후보(설치 $MIN+): 저장소 $($cand.Count)개"
