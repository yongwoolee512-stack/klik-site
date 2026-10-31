# 깃허브 검색 결과(data/src2/gh_q*.json)를 합쳐 "딸깍으로 설치 가능한지"를 README로 판정한다.
# 기준: Claude Code 도구 ★1,000+, MCP 서버 ★5,000+ (사용자 결정 2026-10-30). 이미 진열된 저장소는 뺀다.
# 결과: data/candidates.json  — install 종류: plugin(마켓) / mcp-http(원격) / mcp-npm(Node 필요) / skills-npx(Node 필요) / none
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$UA = @{ "User-Agent" = "klik-pipeline" }
if ($env:GITHUB_TOKEN) { $UA["Authorization"] = "Bearer $env:GITHUB_TOKEN" }
else { try { $cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null; $tok = ($cred | ? { $_ -like "password=*" }) -replace '^password=', ''; if ($tok) { $UA["Authorization"] = "Bearer $tok" } } catch {} }

$have = @{}
foreach ($f in "seed.json","seed_community.json","seed_official.json","seed_popular.json","seed_skillssh.json") { $p = Join-Path $root "data\$f"; if (Test-Path $p) { (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) | % { if ($_.repo -match 'github\.com/([^/]+/[^/#?]+)') { $have[$Matches[1].ToLower()] = $true } } } }

$all = @{}
Get-ChildItem (Join-Path $root "data\src2") -Filter "gh_q*.json" | % {
  $isMcp = (Get-Content $_.FullName -Raw) -match '"total_count"' -and $_.Name -match 'q[67]\.json'
  (Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).items | % {
    $min = if ($isMcp) { 5000 } else { 1000 }
    if ($_.stargazers_count -lt $min -or $_.archived -or $_.fork) { return }
    $k = $_.full_name.ToLower(); if ($have[$k]) { return }
    if (-not $all[$k]) { $all[$k] = $_ }
  }
}
Write-Host "후보 $($all.Count)개, README 확인 중…"

$out = @()
$i = 0
foreach ($r in ($all.Values | Sort-Object stargazers_count -Descending)) {
  $i++
  $md = $null
  foreach ($b in $r.default_branch, "main", "master") { try { $md = (Invoke-WebRequest "https://raw.githubusercontent.com/$($r.full_name)/$b/README.md" -Headers $UA -TimeoutSec 20).Content; break } catch {} }
  if (-not $md) { continue }
  $kind = "none"; $market = ""; $url = ""; $pkg = ""; $name = ""
  if ($md -match '/plugin marketplace add\s+([\w.-]+/[\w.-]+)') { $kind = "plugin"; $market = $Matches[1]; if ($md -match '/plugin install\s+([\w.-]+)') { $name = $Matches[1] } }
  elseif ($md -match 'claude mcp add\s+(?:--transport\s+(?:http|sse)\s+)?([\w.-]+)\s+(?:--transport\s+(?:http|sse)\s+)?(https://[^\s"'']+)') { $kind = "mcp-http"; $name = $Matches[1]; $url = $Matches[2] }
  elseif ($md -match 'claude mcp add\s+([\w.-]+)\s+(?:--\s+)?npx\s+(?:-y\s+)?(@?[\w./-]+)') { $kind = "mcp-npm"; $name = $Matches[1]; $pkg = $Matches[2] }
  elseif ($md -match 'npx\s+(?:-y\s+)?@?[\w./-]*mcp[\w./-]*' -or $md -match '"command":\s*"npx"') { $kind = "mcp-npm"; if ($md -match 'npx\s+(?:-y\s+)?(@?[\w./-]*mcp[\w./-]*)') { $pkg = $Matches[1] } }
  elseif ($md -match 'npx skills add') { $kind = "skills-npx" }
  elseif ($md -match 'claude-plugin/marketplace\.json' -or $md -match '/plugin install') { $kind = "plugin?" }
  $out += [ordered]@{ full_name = $r.full_name; stars = $r.stargazers_count; desc = $r.description; pushed_at = $r.pushed_at; license = $r.license.spdx_id; kind = $kind; name = $name; market = $market; url = $url; pkg = $pkg; topics = ($r.topics -join ",") }
  if ($i % 25 -eq 0) { Write-Host "  $i / $($all.Count)" }
}
ConvertTo-Json -InputObject @($out) -Depth 3 | Set-Content (Join-Path $root "data\candidates.json") -Encoding UTF8
$out | Group-Object kind | % { Write-Host "$($_.Name): $($_.Count)" }
# 사람이 볼 검수 대기 목록: 지난번에 없던 저장소만 "새로 들어옴"으로 표시
$seenPath = Join-Path $root "data\candidates_seen.json"
$seen = @{}; if (Test-Path $seenPath) { (Get-Content $seenPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | % { $seen[$_.Name] = $_.Value } }
$INSTALLABLE = "plugin", "mcp-http", "skills-npx"   # 딸깍 도우미가 깔 수 있는 종류 (skills-npx 는 kind=skill 로 git 설치)
$fresh = @($out | ? { -not $seen[$_.full_name.ToLower()] -and $INSTALLABLE -contains $_.kind })
foreach ($c in $out) { if (-not $seen[$c.full_name.ToLower()]) { $seen[$c.full_name.ToLower()] = (Get-Date).ToString("yyyy-MM-dd") } }
$seen | ConvertTo-Json | Set-Content $seenPath -Encoding UTF8
# 검수 대기(pending.json): 딸깍 가능한 후보만, 처음 본 날짜와 함께 누적. 등록하거나 제외하면 사람이 지운다.
$pendPath = Join-Path $root "data\pending.json"
$pend = @(); if (Test-Path $pendPath) { $pend = @(Get-Content $pendPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
$pendKeys = @($pend | % { $_.full_name.ToLower() })
foreach ($c in $out) { $k = $c.full_name.ToLower(); if ($INSTALLABLE -contains $c.kind -and $pendKeys -notcontains $k) { $pend += [pscustomobject]@{ full_name = $c.full_name; stars = $c.stars; kind = $c.kind; desc = $c.desc; first_seen = $seen[$k] } } }
ConvertTo-Json -InputObject @($pend | Sort-Object stars -Descending) -Depth 3 | Set-Content $pendPath -Encoding UTF8
Write-Host "딸깍 가능한 신규 후보(처음 봄): $($fresh.Count)개 / 검수 대기 전체 $($pend.Count)개"; $fresh | % { Write-Host "  + $($_.full_name) ★$($_.stars) [$($_.kind)] $($_.desc)" }
