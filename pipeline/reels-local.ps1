# 이 컴퓨터에서 도는 인플루언서 릴스 처리: 브라우저에서 모은 주소 파일(urls.txt) → reels.py → 빌드 → 커밋·푸시
#   pwsh -File pipeline/reels-local.ps1 -Urls data/reels-urls.txt
param([string]$Urls = "data\reels-urls.txt")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$site = Split-Path -Parent $root
$u = if ([IO.Path]::IsPathRooted($Urls)) { $Urls } else { Join-Path $root $Urls }
if (-not (Test-Path $u)) { Write-Host "주소 파일 없음: $u"; exit 0 }
python (Join-Path $root "reels.py") --urls $u
if ($LASTEXITCODE) { Write-Warning "reels.py 종료 코드 $LASTEXITCODE" }
& (Join-Path $root "build.ps1")
Copy-Item (Join-Path $root "site\catalog.json") (Join-Path $site "catalog.json") -Force
Copy-Item (Join-Path $root "site\news.json") (Join-Path $site "news.json") -Force
git -C $site pull -q --no-rebase
git -C $site add catalog.json news.json sitemap.xml tools pipeline/data/mentions.json pipeline/data/videos_influencer.json pipeline/data/mentions_pending.json pipeline/data/state.json
if (-not (git -C $site diff --cached --quiet)) {
  git -C $site commit -q -m "인플루언서 릴스 읽기 $(Get-Date -Format 'yyyy-MM-dd HH:mm') (자동)"
  git -C $site push -q
  Write-Host "푸시 완료"
} else { Write-Host "변경 없음" }
