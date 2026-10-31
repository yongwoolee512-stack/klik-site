"""영상 '시청': 인스타 릴스·유튜브·틱톡 주소를 받아 음성을 한글 글로 바꾼다.
사용: python watch.py <url> [--model small|base|medium] [--lang ko]
출력: data/watch/<id>.json {url, title, uploader, caption, transcript, segments}  + 콘솔에 요약 인쇄
필요: pip install yt-dlp faster-whisper  (ffmpeg 없이도 됨: 음성 파일을 그대로 받아 PyAV로 읽는다)
"""
import sys, json, re, pathlib, argparse
ap = argparse.ArgumentParser(); ap.add_argument("url"); ap.add_argument("--model", default="small"); ap.add_argument("--lang", default="ko")
a = ap.parse_args()
here = pathlib.Path(__file__).resolve().parent
out = here / "data" / "watch"; out.mkdir(parents=True, exist_ok=True)
tmp = here / "data" / "watch" / "_tmp"; tmp.mkdir(exist_ok=True)

import yt_dlp
opts = {"format": "bestaudio[ext=m4a]/bestaudio/best", "outtmpl": str(tmp / "%(id)s.%(ext)s"), "quiet": True, "noplaylist": True, "no_warnings": True}
with yt_dlp.YoutubeDL(opts) as y:
    info = y.extract_info(a.url, download=True)
vid = info.get("id"); path = pathlib.Path(y.prepare_filename(info))
if not path.exists():
    cands = list(tmp.glob(f"{vid}.*"));
    if not cands: sys.exit("다운로드 실패: 파일이 없음")
    path = cands[0]
print(f"받음: {path.name} ({path.stat().st_size//1024}KB) · {info.get('uploader')} · {info.get('title','')[:60]}")

import av, numpy as np
def load_audio(p, sr=16000):
    # faster-whisper 내장 디코더가 최신 PyAV(19)와 안 맞아 직접 디코딩: 16kHz 모노 float32
    with av.open(str(p)) as c:
        stream = next(s for s in c.streams if s.type == "audio")
        res = av.AudioResampler(format="s16", layout="mono", rate=sr)
        chunks = []
        for frame in c.decode(stream):
            for f in res.resample(frame):
                chunks.append(f.to_ndarray().reshape(-1))
        for f in res.resample(None):
            chunks.append(f.to_ndarray().reshape(-1))
    return (np.concatenate(chunks).astype(np.float32) / 32768.0) if chunks else np.zeros(0, np.float32)
audio = load_audio(path)
print(f"음성 {len(audio)/16000:.1f}초")
from faster_whisper import WhisperModel
model = WhisperModel(a.model, device="cpu", compute_type="int8")
segments, meta = model.transcribe(audio, language=a.lang, vad_filter=True)
segs = [{"start": round(s.start, 1), "end": round(s.end, 1), "text": s.text.strip()} for s in segments]
text = " ".join(s["text"] for s in segs)
safe = re.sub(r"[^A-Za-z0-9_-]", "_", vid or "video")
rec = {"url": a.url, "id": vid, "title": info.get("title"), "uploader": info.get("uploader"), "caption": info.get("description"), "duration": info.get("duration"), "transcript": text, "segments": segs}
(out / f"{safe}.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"=== 자막 ({len(segs)}문장, {meta.language} {meta.language_probability:.2f}) → data/watch/{safe}.json")
print(text)
