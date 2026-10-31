# 1단계 수집: 깃허브 + MCP 공식 레지스트리에서 새 스킬·플러그인·MCP 후보를 모은다.
# 출력: data/raw.json   환경변수 GITHUB_TOKEN 있으면 한도가 60/h -> 5000/h 로 늘어남.
param([int]$MaxReadme = 20)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
New-Item -ItemType Directory -Force (Join-Path $root "data") | Out-Null
$out = Join-Path $root "data\raw.json"

$gh = @{ "User-Agent" = "skillmart-collector"; "Accept" = "application/vnd.github+json" }
if ($env:GITHUB_TOKEN) { $gh["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

function Get-Json($url, $headers) {
  try { return Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30 }
  catch { Write-Warning "요청 실패 $url : $($_.Exception.Message)"; return $null }
}

$items = @{}
function Add-Item($id, $props) { if (-not $items.ContainsKey($id)) { $items[$id] = $props } else { foreach ($k in $props.Keys) { if (-not $items[$id][$k]) { $items[$id][$k] = $props[$k] } } } }

# --- A. 깃허브 토픽 검색 (종류별) ---
$searches = @(
  @{ kind = "mcp";    q = "topic:mcp-server" },
  @{ kind = "mcp";    q = "topic:model-context-protocol" },
  @{ kind = "plugin"; q = "topic:claude-code-plugin" },
  @{ kind = "skill";  q = "topic:claude-skills" },
  @{ kind = "skill";  q = "topic:agent-skills" }
)
foreach ($s in $searches) {
  $r = Get-Json "https://api.github.com/search/repositories?q=$([uri]::EscapeDataString($s.q))&sort=updated&order=desc&per_page=30" $gh
  if (-not $r) { continue }
  foreach ($repo in $r.items) {
    # 토픽만 달아 둔 무관한 저장소 걸러내기: 스킬·플러그인은 설명/토픽에 claude·anthropic·mcp·agent 언급이 있어야 함
    if ($s.kind -ne "mcp") { $blob = "$($repo.description) $($repo.topics -join ' ')".ToLower(); if ($blob -notmatch 'claude|anthropic|mcp|agent skill|agent-skill|codex|cursor') { continue } }
    Add-Item "gh:$($repo.full_name)" @{
      id = "gh:$($repo.full_name)"; kind = $s.kind; source = "github"
      name = $repo.name; full_name = $repo.full_name; owner = $repo.owner.login
      description = $repo.description; url = $repo.html_url; homepage = $repo.homepage
      stars = $repo.stargazers_count; forks = $repo.forks_count; open_issues = $repo.open_issues_count
      created_at = $repo.created_at; updated_at = $repo.pushed_at
      license = $repo.license.spdx_id; topics = @($repo.topics); archived = $repo.archived
    }
  }
  Start-Sleep -Milliseconds 1500   # 검색 API 한도(비로그인 10회/분) 보호
}

# --- B. MCP 공식 레지스트리 ---
$reg = Get-Json "https://registry.modelcontextprotocol.io/v0/servers?limit=100" @{ "User-Agent" = "skillmart-collector" }
if ($reg -and $reg.servers) {
  foreach ($e in $reg.servers) {
    $sv = if ($e.server) { $e.server } else { $e }
    $repoUrl = "$($sv.repository.url)"
    $id = if ($repoUrl -match 'github\.com/([^/]+/[^/\s]+)') { "gh:" + $Matches[1].TrimEnd('/') } else { "mcp:" + $sv.name }
    $pkg = $null; $remote = $null
    if ($sv.packages) { $p = $sv.packages | Where-Object { $_.registryType -eq "npm" -or $_.registry_name -eq "npm" } | Select-Object -First 1; if ($p) { $pkg = if ($p.identifier) { $p.identifier } else { $p.name } } }
    if ($sv.remotes) { $rm = $sv.remotes | Select-Object -First 1; if ($rm) { $remote = @{ transport = $(if ("$($rm.type)" -match 'sse') { 'sse' } else { 'http' }); url = $rm.url } } }
    Add-Item $id @{
      id = $id; kind = "mcp"; source = "mcp-registry"; name = ($sv.name -split '/')[-1]
      full_name = $(if ($id -like 'gh:*') { $id.Substring(3) } else { $sv.name }); owner = $(if ($id -like 'gh:*') { ($id.Substring(3) -split '/')[0] } else { ($sv.name -split '/')[0] })
      description = $sv.description; url = $(if ($repoUrl) { $repoUrl } else { "https://registry.modelcontextprotocol.io" })
      registry_name = $sv.name; version = $sv.version; npm_pkg = $pkg; remote = $remote
      stars = 0; created_at = $null; updated_at = $(if ($e._meta) { $e._meta.'io.modelcontextprotocol.registry/official'.updatedAt } else { $null })
    }
  }
}

# --- C. README 수집 (상위 N개: 별 많은 순) ---
$list = @($items.Values) | Sort-Object { -[int]$_.stars }
$n = 0
foreach ($it in $list) {
  if ($n -ge $MaxReadme) { break }
  if ($it.id -notlike 'gh:*' -or $it.full_name -notmatch '^[\w.-]+/[\w.-]+$') { continue }   # 깃허브 저장소가 있는 것만
  $rd = $null
  try { $rd = Invoke-RestMethod -Uri "https://api.github.com/repos/$($it.full_name)/readme" -Headers ($gh + @{ "Accept" = "application/vnd.github.raw+json" }) -TimeoutSec 30 } catch {}
  if ($rd) { $it.readme = "$rd".Substring(0, [Math]::Min(12000, "$rd".Length)); $n++ }
  # 별이 0인 레지스트리 항목은 깃허브 메타데이터 보강
  if (-not $it.created_at) { $m = Get-Json "https://api.github.com/repos/$($it.full_name)" $gh; if ($m) { $it.stars = $m.stargazers_count; $it.created_at = $m.created_at; $it.updated_at = $m.pushed_at; $it.license = $m.license.spdx_id; $it.archived = $m.archived; if (-not $it.description) { $it.description = $m.description } } }
}

$result = @{ collected_at = (Get-Date).ToUniversalTime().ToString("o"); count = $items.Count; items = @($items.Values) }
$result | ConvertTo-Json -Depth 8 | Set-Content -Path $out -Encoding UTF8
Write-Host "수집 완료: $($items.Count)개 후보, README ${n}개 -> $out"
