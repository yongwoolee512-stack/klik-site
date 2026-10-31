# 일회성: 영상 읽기 스킬(klik-watch) 시드 + 원문 한글판 (2026-10-31)
$ErrorActionPreference = "Stop"
$s = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "data"
$seed = @(Get-Content "$s\seed_community.json" -Raw -Encoding UTF8 | ConvertFrom-Json)
if (-not ($seed | Where-Object { $_.id -eq 'klik-watch-video' })) {
  $seed += [pscustomobject][ordered]@{ id='klik-watch-video'; kind='skill'; cat='docs'; name='영상 읽기 (유튜브·릴스 자막 뽑기)'; en='klik-watch-video'
    one='유튜브·인스타 릴스·틱톡 주소를 주면 영상 속 말을 글로 바꿔 Claude가 내용을 읽습니다. "이 릴스 요약해 줘"가 됩니다.'
    when='릴스·쇼츠에서 본 도구나 정보를 Claude한테 바로 물어보고 싶은 분'
    level=2; plat=@('claude-code'); added='2026-10-31'; color='#d6ecf5'; repo='https://github.com/yongwoolee512-stack/klik-watch'
    install=[ordered]@{ kind='skill'; repo='yongwoolee512-stack/klik-watch' }
    trust=[ordered]@{ grade='verified'; reasons=@('딸깍 편집팀이 직접 만들고 공개한 스킬 (MIT)','영상 받기(yt-dlp)와 음성→글(faster-whisper) 모두 내 컴퓨터에서, 외부 서비스 없음','파이썬이 필요해요. 처음 한 번 모델 파일(약 460MB)을 받습니다') }
    note='파이썬(무료)이 필요합니다. 처음 쓸 때 Claude가 준비물 설치 명령을 안내하고, 모델 내려받기에 1~2분 걸려요. 공개 영상만 됩니다.'
    tips=@('"이 릴스에서 소개하는 도구가 뭐야? https://www.instagram.com/reel/…"','"이 유튜브 10줄로 요약해 줘 https://www.youtube.com/watch?v=…"','영어 영상이면 "영어 영상이야"라고 덧붙이면 더 정확해요.') }
  ConvertTo-Json -InputObject $seed -Depth 8 | Set-Content "$s\seed_community.json" -Encoding UTF8
}
$rk = Get-Content "$s\readme_ko_community.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$rk | Add-Member 'klik-watch-video' @(
  @{ h='이게 뭐예요'; p='Claude Code에 영상 주소를 주면 말소리를 글(자막)로 바꿔 내용을 읽는 스킬입니다. 유튜브·인스타 릴스·틱톡의 공개 영상을 지원하고, 딸깍 편집팀이 만들었습니다.' },
  @{ h='어떻게 돌아가나'; p='(1) yt-dlp가 영상에서 음성만 내려받고 (2) faster-whisper가 그 음성을 글로 바꾸고 (3) Claude가 그 글을 읽고 질문에 답합니다. 글로 바꾼 결과는 내 컴퓨터(~/.klik/watch)에 저장돼 같은 영상을 다시 물으면 바로 답합니다.' },
  @{ h='준비물'; p='파이썬 3.10 이상. 준비물이 없으면 스크립트가 설치 명령(pip install yt-dlp faster-whisper av numpy)을 알려 주고, Claude가 대신 실행해 줍니다. 처음 한 번 음성 인식 모델(약 460MB)을 내려받습니다.' },
  @{ h='한계'; p='비공개·로그인 필요 영상은 받을 수 없습니다. 음악만 있고 말이 없는 영상은 자막이 비어 캡션만으로 답합니다. 도구 이름 같은 고유명사는 음성 인식이 틀릴 수 있어 화면 글자와 맞춰 보정합니다.' }
) -Force
$rk | ConvertTo-Json -Depth 6 | Set-Content "$s\readme_ko_community.json" -Encoding UTF8
Write-Host "완료: seed $((Get-Content "$s\seed_community.json" -Raw | ConvertFrom-Json).Count)개"
