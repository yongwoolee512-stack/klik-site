# 일회성: 그래피파이·헤드룸 시드 + 원문 한글판 + lazy_owen 릴스 영상 추가 (2026-10-31)
$ErrorActionPreference = "Stop"
$s = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "data"

$seed = @(Get-Content "$s\seed_community.json" -Raw -Encoding UTF8 | ConvertFrom-Json)
if ($seed | Where-Object { $_.id -in "graphify","headroom" }) { Write-Host "이미 있음"; } else {
$new = @(
  [ordered]@{ id='graphify'; kind='skill'; cat='dev'; name='그래피파이 (코드 지도)'; en='Graphify'
    one='프로젝트 전체를 ''지도''로 만들어 두고, Claude가 파일을 뒤지는 대신 지도를 보고 필요한 곳만 읽게 합니다. 새는 토큰을 막아요.'
    when='프로젝트가 커서 Claude가 매번 엉뚱한 파일을 뒤지느라 사용량이 바닥나는 분'
    level=2; plat=@('claude-code'); added='2026-10-31'; color='#d6f0e8'; repo='https://github.com/Graphify-Labs/graphify'
    install=[ordered]@{ kind='py'; pkg='graphifyy'; post='graphify install' }
    trust=[ordered]@{ grade='community'; reasons=@('깃허브 ★14만, Y Combinator 투자사(Graphify Labs) 제작','Apache-2.0 라이선스, 코드 분석은 내 컴퓨터 안에서만(외부 전송 없음)','파이썬이 필요해요. 없으면 딸깍 도우미가 같이 깔아 줍니다') }
    note='파이썬(무료)으로 만들어진 도구라 설치에 1~2분 더 걸릴 수 있어요.'
    tips=@('"/graphify ." 라고 치면 지금 폴더 전체 지도를 만듭니다. 처음 한 번만.','지도가 생기면 "이 프로젝트에서 로그인 처리는 어디서 해?"처럼 그냥 물어보세요. 파일을 다 안 읽고 답합니다.','graph.html 파일을 열면 프로젝트 구조를 클릭하며 구경할 수 있어요.') },
  [ordered]@{ id='headroom'; kind='plugin'; cat='dev'; name='헤드룸 (토큰 압축기)'; en='Headroom'
    one='Claude에 보내는 긴 로그·JSON·파일을 자동으로 압축해 토큰을 줄입니다. 코딩 작업 약 20%, JSON은 60~95%까지. 답은 그대로.'
    when='명령 결과나 로그가 길어서 사용량이 금방 바닥나는 분'
    level=3; plat=@('claude-code'); added='2026-10-31'; color='#f0e0d6'; repo='https://github.com/headroomlabs-ai/headroom'
    install=[ordered]@{ kind='py'; pkg='headroom-ai[all]'; plugin='headroom@headroom-marketplace'; market='headroomlabs-ai/headroom' }
    trust=[ordered]@{ grade='community'; reasons=@('깃허브 ★7.8만, Headroom Labs 제작','Apache-2.0 라이선스, 압축은 내 컴퓨터 안에서만(내용을 밖으로 보내지 않음)','원본은 그대로 보관돼 필요하면 Claude가 다시 꺼내 봅니다') }
    note='파이썬이 필요하고, 설치 뒤에는 Claude Code를 ''헤드룸을 거쳐'' 켜야 효과가 납니다(터미널에서 headroom wrap claude). 개발자에게 맞는 도구예요.'
    tips=@('"headroom wrap claude" 를 터미널에 치면 그때부터 모든 대화가 압축을 거칩니다.','"/headroom" 이라고 치면 지금까지 얼마나 아꼈는지 보여 줍니다.') }
)
$seed += ($new | ForEach-Object { [pscustomobject]$_ })
ConvertTo-Json -InputObject $seed -Depth 8 | Set-Content "$s\seed_community.json" -Encoding UTF8
}

$rk = Get-Content "$s\readme_ko_community.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$rk | Add-Member graphify @(
  @{ h='이게 뭐예요'; p='AI 도우미 안에서 /graphify 라고 치면 프로젝트 전체(코드, 문서, PDF, 이미지, 영상)를 ''지식 그래프''라는 지도로 만듭니다. 그다음부터는 파일을 하나하나 뒤지는 대신 지도에 질문해서 답을 얻습니다.' },
  @{ h='왜 토큰이 줄어드나'; p='코드 지도는 내 컴퓨터에서 문법 분석기(tree-sitter)로 만들어 AI를 쓰지 않고, 아무것도 밖으로 나가지 않습니다. 지도가 있으면 Claude가 ''어디를 읽어야 하는지''를 먼저 알고 그 부분만 읽기 때문에 낭비가 줍니다.' },
  @{ h='연결마다 근거가 붙어요'; p='지도의 모든 연결선에는 ''원문에 명시됨(EXTRACTED)'' 또는 ''그래피파이가 추론함(INFERRED)'' 표시가 붙어서, 직접 읽은 사실과 추측을 구분할 수 있습니다. 벡터 검색이 아니라 진짜 그래프라 경로를 따라갈 수 있습니다.' },
  @{ h='설치·결과물'; p='파이썬 3.10 이상이 필요합니다. 설치 후 graphify install 이 쓰는 AI 도우미를 알아서 감지해 스킬을 등록합니다. 실행하면 graphify-out 폴더에 graph.html(브라우저에서 클릭하며 보는 지도), GRAPH_REPORT.md(핵심 요약), graph.json(전체 데이터) 세 파일이 생깁니다.' },
  @{ h='유료 버전'; p='Graphify Cloud(유료, 14일 무료)는 여러 저장소를 묶고 Sentry·Jira 같은 서비스까지 한 지도에 넣어 줍니다. 로컬 버전만으로도 핵심 기능은 전부 됩니다.' }
) -Force
$rk | Add-Member headroom @(
  @{ h='이게 뭐예요'; p='AI에 보내기 전에 도구 결과, 로그, 파일, 검색 결과를 압축해 주는 도구입니다. 예시로 로그 10,144토큰이 1,260토큰으로 줄어도 같은 오류를 똑같이 찾아냅니다. 압축은 내 컴퓨터에서만 일어나고 내용은 어디로도 보내지 않습니다.' },
  @{ h='쓰는 방식 네 가지'; p='(1) 프로그램 안에서 compress() 함수로, (2) 프록시 서버로(코드 수정 없이), (3) headroom wrap claude 처럼 Claude Code·Codex·Cursor 등을 한 줄로 감싸서, (4) MCP 서버로. 비개발자에게 현실적인 건 (3)입니다.' },
  @{ h='어떻게 줄이나'; p='내용 종류를 알아내서 JSON은 SmartCrusher, 소스코드는 CodeCompressor, 일반 글은 Kompress 모델이 각각 압축합니다. 원본은 내 컴퓨터에 보관돼서(CCR) 모델이 필요하면 headroom_retrieve 로 전체를 다시 꺼내 봅니다. 모델이 ''쓰는'' 답도 군더더기를 줄입니다.' },
  @{ h='추가 기능'; p='Claude·Codex·Gemini·Grok 사이에 기억을 공유하는 메모리, 실패한 세션에서 교훈을 뽑아 CLAUDE.md에 적어 주는 headroom learn 기능이 있습니다.' },
  @{ h='설치'; p='pip install "headroom-ai[all]" (파이썬 3.10 이상). 그다음 headroom wrap claude 로 Claude Code를 감싸서 실행합니다. 되돌리려면 headroom unwrap claude.' }
) -Force
$rk | ConvertTo-Json -Depth 6 | Set-Content "$s\readme_ko_community.json" -Encoding UTF8

$v = Get-Content "$s\videos.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$reel = [pscustomobject]@{ url='https://www.instagram.com/reel/DeykbAkzXxL/'; by='lazy_owen (게으른 빌더)' }
foreach ($id in 'ponytail','graphify','headroom') {
  $cur = @(); if ($v.PSObject.Properties[$id]) { $cur = @($v.$id) }
  if (-not ($cur | Where-Object { $_.url -eq $reel.url })) { $cur += $reel }
  $v | Add-Member $id $cur -Force
}
$v | ConvertTo-Json -Depth 5 | Set-Content "$s\videos.json" -Encoding UTF8
Write-Host "완료: seed $((Get-Content "$s\seed_community.json" -Raw | ConvertFrom-Json).Count)개, videos: " + ((($v.PSObject.Properties | Where-Object { $_.Name -ne '_doc' }) | ForEach-Object { "$($_.Name)=$(@($_.Value).Count)" }) -join ', ')
