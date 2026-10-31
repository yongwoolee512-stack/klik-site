"""인플루언서 영상 수집: 영상 주소들을 받아 말소리를 글로 바꾸고, 딸깍 도구 언급을 찾아 모은다.
사용:
  python reels.py --youtube                 # influencers.json 의 유튜브 채널에서 최근 쇼츠 목록을 받아 처리 (서버에서도 됨)
  python reels.py --urls urls.txt           # 한 줄에 하나씩 적힌 영상 주소 처리 (인스타 릴스는 이 방식: 목록은 브라우저에서 읽어 넘김)
  python reels.py --url <url> --by <계정>   # 하나만
결과:
  data/mentions.json          영상별 기록 {url, platform, by, title, date, transcript, matched:[도구id], unknown:[이름]}  (누적, 같은 주소는 한 번만)
  data/videos_influencer.json 도구id → [{url, by, title}]  (build.ps1 이 상세 창 '짧은 영상'에 합침)
  data/mentions_pending.json  카탈로그에 없는 도구 이름 후보 (사람 검수용)
"""
import sys, json, re, pathlib, argparse, datetime, tempfile
here = pathlib.Path(__file__).resolve().parent
data = here / "data"
ap = argparse.ArgumentParser()
ap.add_argument("--youtube", action="store_true"); ap.add_argument("--urls"); ap.add_argument("--url"); ap.add_argument("--by", default="")
ap.add_argument("--model", default="small"); ap.add_argument("--limit", type=int, default=0)
a = ap.parse_args()

try:
    import yt_dlp, av, numpy as np
    from faster_whisper import WhisperModel
except ModuleNotFoundError as e:
    sys.exit(f"준비물 없음 ({e.name}): python -m pip install --user yt-dlp faster-whisper av numpy")

cfg = json.loads((data / "influencers.json").read_text(encoding="utf-8"))
mpath = data / "mentions.json"
mentions = json.loads(mpath.read_text(encoding="utf-8")) if mpath.exists() else []
seen = {m["url"].split("?")[0].rstrip("/") for m in mentions}
limit = a.limit or int(cfg.get("per_account_limit", 5))
max_age = int(cfg.get("max_age_days", 14))

# ---- 1. 처리할 영상 주소 모으기 ----
jobs = []   # (url, by, platform)
def norm(u): return u.split("?")[0].rstrip("/")
if a.youtube:
    for ch in cfg.get("youtube", []):
        opts = {"quiet": True, "no_warnings": True, "extract_flat": True, "playlistend": limit, "skip_download": True}
        try:
            with yt_dlp.YoutubeDL(opts) as y: info = y.extract_info(ch, download=False)
        except Exception as e:
            print(f"목록 실패 {ch}: {str(e)[:120]}"); continue
        by = info.get("uploader") or info.get("channel") or ch
        for e in (info.get("entries") or [])[:limit]:
            u = e.get("url") or (f"https://www.youtube.com/watch?v={e['id']}" if e.get("id") else None)
            if u and norm(u) not in seen: jobs.append((u, by, "youtube"))
if a.urls:
    for line in pathlib.Path(a.urls).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        u, _, by = line.partition(" ")
        if norm(u) not in seen: jobs.append((u, by.strip() or a.by, "instagram" if "instagram.com" in u else "youtube" if "youtu" in u else "tiktok"))
if a.url and norm(a.url) not in seen:
    jobs.append((a.url, a.by, "instagram" if "instagram.com" in a.url else "youtube" if "youtu" in a.url else "tiktok"))
print(f"처리할 영상 {len(jobs)}개 (이미 읽은 {len(seen)}개 제외)")
if not jobs: sys.exit(0)

# ---- 2. 도구 이름 사전 (카탈로그 + 별칭) ----
cat = json.loads((here / "site" / "catalog.json").read_text(encoding="utf-8")) if (here / "site" / "catalog.json").exists() else json.loads((here.parent / "catalog.json").read_text(encoding="utf-8"))
alias_path = data / "aliases.json"
aliases = json.loads(alias_path.read_text(encoding="utf-8")) if alias_path.exists() else {}
lexicon = []  # (pattern, id)
for it in cat["items"]:
    # 이름 전체만 맞춘다(부분 단어 매칭은 'agent'·'design' 같은 흔한 말에 전부 걸려 오탐). 영문 이름은 'skill/MCP/plugin' 꼬리를 뗀 전체, 한글은 첫 단어(3자 이상)
    names = set()
    en = re.sub(r"\(.*?\)", "", it.get("en", "")).strip()
    en = re.sub(r"\s+(skills?|plugin|MCP|connector|server|CLI)$", "", en, flags=re.I).strip()
    GENERIC = {"skill", "skills", "plugin", "claude", "code", "agent", "agents", "tools", "server", "official", "design", "image", "prompts", "extract", "browser", "memory"}
    if en and len(en) >= 4 and en.lower() not in GENERIC: names.add(en)
    ko = re.sub(r"\(.*?\)", "", it.get("name", "")).strip()
    if len(ko) >= 2: names.add(ko)                       # 한글은 이름 전체 ("에이전트"처럼 흔한 첫 단어만으로는 안 맞춘다)
    if ko.endswith(" 연결") and len(ko.split(" ")[0]) >= 2: names.add(ko.split(" ")[0])   # "노션 연결" → "노션" (서비스 이름은 고유)
    for al in aliases.get(it["id"], []): names.add(al)
    for n in names:
        pat = re.escape(n).replace(r"\ ", r"\s*")
        if re.match(r"^[A-Za-z]", n): pat = r"(?<![A-Za-z0-9])" + pat + r"(?![A-Za-z0-9])"   # 영문은 단어 경계
        else: pat = r"(?<![가-힣])" + pat + r"(?![가-힣])"                                      # 한글도 경계 ("미로"가 "미로핏"에 걸리지 않게)
        lexicon.append((re.compile(pat, re.I), it["id"]))
# 알려지지 않은 도구 후보: "OO 플러그인/스킬/MCP/도구" 바로 앞 단어, 또는 영문 고유명사
unk_re = re.compile(r"([A-Za-z][A-Za-z0-9.-]{2,}|[가-힣]{2,8})\s*(?:이라는|라는|이란|란|라고|이라고)?\s*(플러그인|스킬|MCP|엠씨피|도구|확장|툴)")
cap_re = re.compile(r"\b([A-Z][a-zA-Z0-9]{3,}(?:\s[A-Z][a-zA-Z0-9]{2,})?)\b")
STOP = {"Claude", "Code", "ChatGPT", "GPT", "Gemini", "Cursor", "Codex", "Python", "Windows", "Mac", "Google", "Notion", "YouTube", "Instagram", "OpenAI", "Anthropic", "API", "Reels"}

# ---- 3. 음성 → 글 ----
def load_audio(p, sr=16000):
    with av.open(str(p)) as c:
        stream = next(s for s in c.streams if s.type == "audio")
        res = av.AudioResampler(format="s16", layout="mono", rate=sr); chunks = []
        for frame in c.decode(stream):
            for f in res.resample(frame): chunks.append(f.to_ndarray().reshape(-1))
        for f in res.resample(None): chunks.append(f.to_ndarray().reshape(-1))
    return (np.concatenate(chunks).astype(np.float32) / 32768.0) if chunks else np.zeros(0, np.float32)
model = WhisperModel(a.model, device="cpu", compute_type="int8")
tmp = pathlib.Path(tempfile.gettempdir()) / "klik-reels"; tmp.mkdir(exist_ok=True)

vi_path = data / "videos_influencer.json"
vids = json.loads(vi_path.read_text(encoding="utf-8")) if vi_path.exists() else {}
pend_path = data / "mentions_pending.json"
pending = json.loads(pend_path.read_text(encoding="utf-8")) if pend_path.exists() else []
new_matches = 0
for url, by, platform in jobs:
    opts = {"format": "bestaudio[ext=m4a]/bestaudio/best", "outtmpl": str(tmp / "%(id)s.%(ext)s"), "quiet": True, "noplaylist": True, "no_warnings": True}
    try:
        with yt_dlp.YoutubeDL(opts) as y:
            info = y.extract_info(url, download=True); path = pathlib.Path(y.prepare_filename(info))
    except Exception as e:
        print(f"받기 실패 {url}: {str(e)[:120]}"); continue
    up = info.get("upload_date") or ""
    if up and max_age and (datetime.date.today() - datetime.date(int(up[:4]), int(up[4:6]), int(up[6:8]))).days > max_age:
        print(f"오래됨({up}) 건너뜀 {url}"); seen.add(norm(url)); mentions.append({"url": url, "platform": platform, "by": by, "skipped": "old", "date": up}); continue
    if not path.exists():
        c = list(tmp.glob(f"{info.get('id')}.*")); path = c[0] if c else None
    if not path: print(f"파일 없음 {url}"); continue
    audio = load_audio(path)
    segs, meta = model.transcribe(audio, language="ko", vad_filter=True)
    text = " ".join(s.text.strip() for s in segs)
    try: path.unlink()
    except OSError: pass
    caption = info.get("description") or ""
    hay = text + "\n" + (info.get("title") or "")   # 캡션은 채널 링크(github·slack…)가 늘 들어 있어 도구 매칭에서는 뺀다
    matched = sorted({tid for rx, tid in lexicon if rx.search(hay)})
    hay = hay + "\n" + caption
    unknown = sorted({m.group(1) for m in unk_re.finditer(hay)} | {m.group(1) for m in cap_re.finditer(hay)} - STOP)
    rec = {"url": url, "platform": platform, "by": by or info.get("uploader") or "", "title": (info.get("title") or "")[:120], "date": up,
           "duration": info.get("duration"), "transcript": text, "caption": caption[:600], "matched": matched, "unknown": unknown[:20],
           "read_at": datetime.datetime.now().isoformat(timespec="seconds")}
    mentions.append(rec); seen.add(norm(url))
    for tid in matched:
        lst = vids.setdefault(tid, [])
        if not any(v["url"] == url for v in lst):
            lst.append({"url": url, "by": rec["by"], "title": rec["title"]}); new_matches += 1
    if unknown and not matched:
        pending.append({"url": url, "by": rec["by"], "date": up, "candidates": unknown[:10], "snippet": text[:300]})
    print(f"읽음 [{platform}] {rec['by']} · {rec['title'][:40]} → 도구 {matched or '-'} / 후보 {unknown[:5]}")

mpath.write_text(json.dumps(mentions, ensure_ascii=False, indent=1), encoding="utf-8")
vi_path.write_text(json.dumps(vids, ensure_ascii=False, indent=1), encoding="utf-8")
pend_path.write_text(json.dumps(pending, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"완료: 기록 {len(mentions)}개, 새로 연결된 영상 {new_matches}개, 검수 대기 {len(pending)}건")
