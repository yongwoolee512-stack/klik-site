# 매일 한 번 도는 전체 파이프라인 (GitHub Actions .github/workflows/daily.yml 이 05:00 KST에 실행, 로컬에서도 같은 명령)
#   stars.ps1    깃허브 별·업데이트일·이달 증가 (stars_history 누적)
#   skillssh.ps1 skills.sh 설치 수·지난주 증가 + 설치 10만+ 신규 후보
#   videos.ps1   유튜브 쇼츠 (깃허브 러너에서는 유튜브가 막을 수 있어 실패해도 계속)
#   discover.ps1 깃허브 검색 → 기준(★1,000 / MCP ★5,000) 넘긴 신규 후보
#   build.ps1    catalog.json / news.json 생성
# 신규 도구의 한글 설명·등록은 자동이 아니다(검수 필요). 후보는 data/candidates.json, data/skillssh_candidates.json 에 쌓인다.
param([switch]$SkipVideos, [switch]$SkipDiscover)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sw = [Diagnostics.Stopwatch]::StartNew()
function Step($name, $script) {
  Write-Host "`n=== $name ==="
  try { & (Join-Path $root $script); if ($LASTEXITCODE) { Write-Warning "$name 종료 코드 $LASTEXITCODE" } }
  catch { Write-Warning "$name 실패: $($_.Exception.Message)" }   # 한 단계가 죽어도 나머지는 돈다
}
Step "깃허브 신호" "stars.ps1"
Step "skills.sh 설치 수" "skillssh.ps1"
if (-not $SkipVideos) { Step "유튜브 쇼츠" "videos.ps1" }
if (-not $SkipDiscover) { Step "신규 후보 발견" "discover.ps1" }
Write-Host "`n=== 카탈로그 ==="
# build.ps1 은 site\news.json 에 소식을 누적한다. 새 체크아웃(site/ 는 gitignore)에서는 사이트 루트의 news.json 을 먼저 가져온다.
New-Item -ItemType Directory -Force (Join-Path $root "site") | Out-Null
if (-not (Test-Path (Join-Path $root "site\news.json")) -and (Test-Path (Join-Path $root "..\news.json"))) { Copy-Item (Join-Path $root "..\news.json") (Join-Path $root "site\news.json") }
& (Join-Path $root "build.ps1")   # 이것만은 실패하면 워크플로도 실패해야 한다
Copy-Item (Join-Path $root "site\catalog.json") (Join-Path $root "..\catalog.json") -Force
Copy-Item (Join-Path $root "site\news.json") (Join-Path $root "..\news.json") -Force
Write-Host "완료 ($([int]$sw.Elapsed.TotalSeconds)초)"
