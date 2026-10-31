# 2단계 신뢰성 검사: 후보마다 등급(official / verified / community / caution)을 매기고 이유를 남긴다.
# 입력: data/raw.json  출력: data/trusted.json   caution 등급은 사이트에 올라가지 않는다.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$raw = Get-Content (Join-Path $root "data\raw.json") -Raw -Encoding UTF8 | ConvertFrom-Json

# 공식 조직: 이 목록은 편집팀이 관리 (제품 회사 본인 계정)
$OFFICIAL = @("anthropics","modelcontextprotocol","github","microsoft","google","googleapis","notion","makenotion","figma","supabase","supabase-community","vercel","cloudflare","stripe","getsentry","upstash","slackapi","linear","atlassian","asana","apify","playwright","openai","aws","awslabs","azure","hashicorp","elastic","mongodb","redis","neondatabase","prisma","twilio","sendgrid","shopify","zapier")

# README·설치 안내에서 위험 신호 (하나라도 있으면 caution)
$DANGER = @(
  @{ re = 'curl[^\n|]*\|\s*(sudo\s+)?(ba)?sh'; why = "원격 스크립트를 받아 바로 실행 (curl | sh)" },
  @{ re = 'iex\s*\(|Invoke-Expression'; why = "PowerShell Invoke-Expression 실행" },
  @{ re = 'base64\s*(-d|--decode)[^\n]*\|'; why = "base64로 숨긴 명령 실행" },
  @{ re = 'rm\s+-rf\s+[/~]'; why = "루트/홈 디렉터리 삭제 명령" },
  @{ re = 'chmod\s+777'; why = "전체 권한 개방" },
  @{ re = '(?i)disable\s+(windows\s+)?defender|--no-sandbox|--dangerously'; why = "보안 기능 해제 안내" }
)
# MCP가 요구하는 권한 추정 (카드에 표시)
$PERMS = @(
  @{ re = '(?i)\b(write|edit|delete|remove)\s+(files?|directory|folder)|fs\.write|writeFile'; label = "파일 쓰기" },
  @{ re = '(?i)\b(shell|bash|terminal|exec(ute)?)\b.*\b(command|tool)'; label = "명령 실행" },
  @{ re = '(?i)\b(api[_ ]?key|token|secret|credential)s?\b'; label = "API 키 필요" },
  @{ re = '(?i)\b(browser|playwright|puppeteer|chrome)\b'; label = "브라우저 조작" },
  @{ re = '(?i)\b(payment|stripe|billing|charge)\b'; label = "결제 접근" },
  @{ re = '(?i)\b(email|gmail|smtp)\b'; label = "메일 접근" }
)

$outItems = @()
foreach ($it in $raw.items) {
  $reasons = @(); $score = 0
  $owner = "$($it.owner)".ToLower()
  $text = "$($it.description)`n$($it.readme)"
  $ageDays = if ($it.created_at) { (New-TimeSpan -Start ([datetime]$it.created_at) -End (Get-Date)).TotalDays } else { 0 }
  $staleDays = if ($it.updated_at) { (New-TimeSpan -Start ([datetime]$it.updated_at) -End (Get-Date)).TotalDays } else { 999 }

  $isOfficial = $OFFICIAL -contains $owner
  if ($isOfficial) { $score += 50; $reasons += "공식 조직 계정 ($owner)" }
  if ([int]$it.stars -ge 1000) { $score += 25; $reasons += "별 $($it.stars)개" } elseif ([int]$it.stars -ge 100) { $score += 10; $reasons += "별 $($it.stars)개" } elseif ([int]$it.stars -lt 20) { $score -= 10; $reasons += "별 20개 미만" }
  if ($ageDays -ge 90) { $score += 10 } elseif ($ageDays -gt 0 -and $ageDays -lt 14) { $score -= 10; $reasons += "생성 2주 미만" }
  if ($staleDays -gt 365) { $score -= 15; $reasons += "1년 이상 업데이트 없음" }
  if ($it.license) { $score += 5 } else { $score -= 5; $reasons += "라이선스 없음" }
  if ($it.archived) { $score -= 30; $reasons += "보관(archived)된 저장소" }
  if ($it.source -eq "mcp-registry") { $score += 15; $reasons += "MCP 공식 레지스트리 등재" }

  $danger = @()
  foreach ($d in $DANGER) { if ($text -match $d.re) { $danger += $d.why } }
  $perms = @()
  foreach ($p in $PERMS) { if ($text -match $p.re) { $perms += $p.label } }
  if (-not $it.readme) { $reasons += "README 미수집(검사 제한)" }

  $grade = if ($danger.Count -gt 0) { "caution" } elseif ($isOfficial -and $score -ge 50) { "official" } elseif ($score -ge 40) { "verified" } elseif ($score -ge 10) { "community" } else { "caution" }
  if ($grade -eq "caution" -and $danger.Count -eq 0) { $reasons += "신뢰 점수 부족 ($score)" }

  $it | Add-Member -NotePropertyName trust -NotePropertyValue @{ grade = $grade; score = $score; reasons = $reasons; danger = $danger; permissions = ($perms | Select-Object -Unique) } -Force
  $outItems += $it
}
$summary = $outItems | Group-Object { $_.trust.grade } | ForEach-Object { "$($_.Name)=$($_.Count)" }
@{ checked_at = (Get-Date).ToUniversalTime().ToString("o"); items = $outItems } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root "data\trusted.json") -Encoding UTF8
Write-Host "신뢰성 검사 완료: $($summary -join ', ')"
