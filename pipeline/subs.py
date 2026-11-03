"""유튜브 영상의 소리를 글로 옮겨 pipeline/data/transcripts.json 에 저장 (한국어 요약의 재료).
자막 요청은 429로 막혀서 소리(오디오)를 받아 faster-whisper 로 읽는다. 이미 읽은 영상은 건너뛴다.
사용: python pipeline/subs.py [--limit N] [--sleep 2] [--model small] [--max-sec 240]"""
import json, re, sys, time, random, tempfile, pathlib, argparse

D = pathlib.Path(__file__).parent / "data"
ap = argparse.ArgumentParser()
ap.add_argument("--limit", type=int, default=0)
ap.add_argument("--sleep", type=float, default=2.0)
ap.add_argument("--model", default="small")
ap.add_argument("--max-sec", type=int, default=240)
a = ap.parse_args()
try:
    import yt_dlp, av, numpy as np
    from faster_whisper import WhisperModel
except ImportError as e:
    sys.exit(f"준비물 없음 ({e.name}): python -m pip install --user yt-dlp faster-whisper av numpy")

def vid(u):
    m = re.search(r"(?:shorts/|v=|youtu\.be/)([\w-]{11})", u)
    return m.group(1) if m else None

urls = {}
for f in ("videos.json", "videos_influencer.json", "videos_auto.json"):
    p = D / f
    if not p.exists():
        continue
    for k, arr in json.loads(p.read_text(encoding="utf-8")).items():
        if k.startswith("_") or not isinstance(arr, list):
            continue
        for v in arr:
            i = vid(v.get("url", ""))
            if i:
                urls[i] = v["url"]

out_p = D / "transcripts.json"
out = json.loads(out_p.read_text(encoding="utf-8")) if out_p.exists() else {}
todo = [i for i in urls if i not in out]
if a.limit:
    todo = todo[: a.limit]
print(f"videos={len(urls)} todo={len(todo)}", flush=True)
if not todo:
    sys.exit(0)

def load_audio(p, sr=16000, max_sec=240):
    with av.open(str(p)) as c:
        stream = next(s for s in c.streams if s.type == "audio")
        res = av.AudioResampler(format="s16", layout="mono", rate=sr); chunks = []; n = 0
        for frame in c.decode(stream):
            for f in res.resample(frame):
                x = f.to_ndarray().reshape(-1); chunks.append(x); n += len(x)
            if n >= sr * max_sec:
                break
    return (np.concatenate(chunks).astype(np.float32) / 32768.0) if chunks else np.zeros(0, np.float32)

model = WhisperModel(a.model, device="cpu", compute_type="int8")
tmp = pathlib.Path(tempfile.gettempdir()) / "klik-subs"; tmp.mkdir(exist_ok=True)
blocks = 0
for n, i in enumerate(todo, 1):
    opts = {"format": "bestaudio[ext=m4a]/bestaudio/best", "outtmpl": str(tmp / "%(id)s.%(ext)s"),
            "quiet": True, "noplaylist": True, "no_warnings": True}
    try:
        with yt_dlp.YoutubeDL(opts) as y:
            info = y.extract_info(urls[i], download=True); path = pathlib.Path(y.prepare_filename(info))
        blocks = 0
    except Exception as e:
        msg = str(e)
        print(f"받기 실패 {i}: {msg[:110]}", flush=True)
        if re.search(r"429|rate-limit|sign in|bot|please wait", msg, re.I):
            blocks += 1
            if blocks >= 2:
                print("차단 의심: 연속 2번 막힘 → 멈춥니다", flush=True); break
        else:
            out[i] = {"lang": "", "text": "", "err": msg[:80]}   # 비공개·삭제 등: 다시 두드리지 않는다
            out_p.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
        continue
    if not path.exists():
        c = list(tmp.glob(f"{i}.*")); path = c[0] if c else None
    if not path:
        continue
    try:
        audio = load_audio(path, max_sec=a.max_sec)
        segs, inf = model.transcribe(audio, vad_filter=True, beam_size=1)
        text = " ".join(s.text.strip() for s in segs)
        out[i] = {"lang": inf.language, "text": text[:6000], "title": info.get("title", ""), "dur": info.get("duration", 0)}
    finally:
        try: path.unlink()
        except OSError: pass
    out_p.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    print(f"{n}/{len(todo)} {i} {out[i]['lang']} {len(out[i]['text'])}자", flush=True)
    time.sleep(a.sleep * random.uniform(0.6, 1.4))
