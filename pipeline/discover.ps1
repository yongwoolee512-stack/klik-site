# 신규 후보 발견: 깃허브 검색 8종을 돌려 data/src2/gh_q1..8.json 을 갱신하고 candidates.ps1 로 넘긴다.
# 기준(사용자 결정 2026-10-30): Claude Code 도구 ★1,000+, MCP 서버 ★5,000+.  skills.sh 쪽 후보는 skillssh.ps1 이 따로 만든다.
# 결과: data/candidates.json(전체) + data/candidates_seen.json(처음 본 날짜) → 실행 로그에 "새로 기준을 넘긴 저장소"가 찍힌다.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dir = Join-Path $root "data\src2"; New-Item -ItemType Directory -Force $dir | Out-Null
$H = @{ "Accept" = "application/vnd.github+json"; "User-Agent" = "klik-pipeline" }
if ($env:GITHUB_TOKEN) { $H["Authorization"] = "Bearer $env:GITHUB_TOKEN" }
else { try { $cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null; $tok = ($cred | ? { $_ -like "password=*" }) -replace '^password=', ''; if ($tok) { $H["Authorization"] = "Bearer $tok" } } catch {} }

$QUERIES = @(
  'topic:claude-code stars:>=1000',
  'topic:claude-code-plugin stars:>=500',
  'topic:claude-skills stars:>=500',
  'topic:agent-skills stars:>=1000',
  '"claude code" in:description stars:>=1000',
  'topic:mcp-server stars:>=5000',      # q6: MCP
  'topic:mcp stars:>=5000',             # q7: MCP
  'topic:claude stars:>=3000'
)
$i = 0
foreach ($q in $QUERIES) {
  $i++
  $u = "https://api.github.com/search/repositories?q=" + [uri]::EscapeDataString($q) + "&sort=stars&order=desc&per_page=100"
  try { $r = Invoke-RestMethod $u -Headers $H -TimeoutSec 60 } catch { Write-Warning "검색 실패 q$i ($q): $($_.Exception.Message)"; continue }
  $r | ConvertTo-Json -Depth 6 -Compress | Set-Content (Join-Path $dir "gh_q$i.json") -Encoding UTF8
  Write-Host "q$i $q → $($r.total_count)개 (받음 $($r.items.Count))"
  Start-Sleep -Seconds 3   # 검색 API 한도: 분당 30회
}
& (Join-Path $root "candidates.ps1")
