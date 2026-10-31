# 3단계 한글화: Claude API로 README를 읽고 사이트 카드 틀("이게 뭐예요/이런 분께/이렇게 써요")로 다시 쓴다.
# 입력: data/trusted.json  출력: data/summarized.json
# ANTHROPIC_API_KEY 없으면 요약을 건너뛰고 status=pending 으로 남긴다 (사이트에 노출 안 됨).
param([int]$Max = 30, [string]$Model = "claude-opus-5-5")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$data = Get-Content (Join-Path $root "data\trusted.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$cachePath = Join-Path $root "data\summaries.json"   # 이미 요약한 것은 다시 부르지 않음 (비용 절감)
$cache = @{}
if (Test-Path $cachePath) { (Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }

$SYSTEM = @"
당신은 '스킬마트' 편집자다. 스킬마트는 개발을 모르는 한국인 일반 사용자에게 Claude Code·Claude 앱·ChatGPT용 스킬/플러그인/MCP를 소개하는 사이트다.
깃허브 README를 읽고 아래 규칙으로 한글 카드를 쓴다.
- 기술 용어 대신 "이걸로 뭘 할 수 있는지"를 쓴다. 'API', 'CLI', '서버', '프로토콜' 같은 단어는 꼭 필요할 때만.
- name_ko: 기능이 드러나는 한글 이름 (예: "노션 연결", "엑셀 정리·수식 자동화"). 10자 안팎.
- one: 한 문장. "~해 줍니다/~합니다"로 끝난다. 40자 이내.
- when: "~하는 분" 형태로 어떤 사람에게 필요한지. 30자 이내.
- tips: 실제로 입력할 법한 한국어 명령 예시 1~3개. 따옴표 포함 ("\"어제 회의록 요약해 줘\"").
- category: design, dev, docs, data, marketing, web, work, auto 중 하나.
- level: 1(설치 후 바로 씀) 2(계정 로그인 등 한 단계 더) 3(설정 파일이나 키 발급 필요).
- note: 사용 전 꼭 알아야 할 주의 사항(유료 계정 필요 등). 없으면 빈 문자열.
- 과장하지 않는다. README에 없는 기능을 지어내지 않는다.
"@
$SCHEMA = @{
  type = "object"; additionalProperties = $false
  required = @("name_ko","one","when","tips","category","level","note")
  properties = @{
    name_ko = @{ type = "string" }; one = @{ type = "string" }; when = @{ type = "string" }
    tips = @{ type = "array"; items = @{ type = "string" } }
    category = @{ type = "string"; enum = @("design","dev","docs","data","marketing","web","work","auto") }
    level = @{ type = "integer"; enum = @(1,2,3) }
    note = @{ type = "string" }
  }
}

function Invoke-Claude($item) {
  $user = "저장소: $($item.full_name)`n종류: $($item.kind)`n설명: $($item.description)`n`n--- README ---`n$($item.readme)"
  $body = @{
    model = $Model; max_tokens = 2048
    output_config = @{ effort = "low"; format = @{ type = "json_schema"; schema = $SCHEMA } }
    fallbacks = "default"
    system = @(@{ type = "text"; text = $SYSTEM; cache_control = @{ type = "ephemeral" } })
    messages = @(@{ role = "user"; content = $user })
  } | ConvertTo-Json -Depth 12
  $headers = @{ "x-api-key" = $env:ANTHROPIC_API_KEY; "anthropic-version" = "2026-10-21"; "anthropic-beta" = "server-side-fallback-2026-07-01"; "content-type" = "application/json" }
  $r = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
  if ($r.stop_reason -eq "refusal") { throw "모델이 요약을 거부함 ($($r.stop_details.category))" }
  if ($r.stop_reason -eq "max_tokens") { throw "출력이 잘림" }
  $text = ($r.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1).text
  return ($text | ConvertFrom-Json)
}

$done = 0; $skipped = 0; $failed = 0
foreach ($it in $data.items) {
  $id = $it.id
  if ($it.trust.grade -eq "caution") { $it | Add-Member status "rejected" -Force; continue }
  if ($cache.ContainsKey($id)) { $it | Add-Member ko $cache[$id] -Force; $it | Add-Member status "published" -Force; continue }
  if (-not $env:ANTHROPIC_API_KEY -or -not $it.readme -or $done -ge $Max) { $it | Add-Member status "pending" -Force; $skipped++; continue }
  try {
    $ko = Invoke-Claude $it
    $cache[$id] = $ko
    $it | Add-Member ko $ko -Force; $it | Add-Member status "published" -Force; $done++
    Write-Host "  요약: $($it.full_name) -> $($ko.name_ko)"
  } catch { Write-Warning "요약 실패 $($it.full_name): $($_.Exception.Message)"; $it | Add-Member status "pending" -Force; $failed++ }
}
$cache | ConvertTo-Json -Depth 6 | Set-Content $cachePath -Encoding UTF8
$data | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $root "data\summarized.json") -Encoding UTF8
Write-Host "한글화 완료: 새 요약 $done, 대기 $skipped, 실패 $failed" + $(if (-not $env:ANTHROPIC_API_KEY) { "  (ANTHROPIC_API_KEY 없음 → 요약 생략)" })
