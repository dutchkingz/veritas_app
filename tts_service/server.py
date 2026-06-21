import io
import re
import torch
import ChatTTS
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

app = FastAPI(title="VERITAS TTS — HAL 9000")

# ── Model + speaker (loaded once at startup) ────────────────
tts = None
spk_emb = None

@app.on_event("startup")
def load_model():
    global tts, spk_emb
    try:
        print("[HAL] Loading ChatTTS model...")
        tts = ChatTTS.Chat()
        tts.load(compile=False)  # compile=True needs triton, skip on macOS

        # Seed 8888: deep, stable male voice (community-recommended for flat delivery)
        torch.manual_seed(8888)
        spk_emb = tts.sample_random_speaker()
        print("[HAL] Model loaded. Ready.")
    except Exception as e:
        print(f"[HAL] FATAL: Failed to load model: {e}")
        tts = None
        spk_emb = None

# ── Number-to-words (ChatTTS chokes on digits) ─────────────
ONES = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

def _num_to_words(n):
    n = int(n)
    if n == 0:
        return "zero"
    if n < 0:
        return "minus " + _num_to_words(-n)
    parts = []
    if n >= 1000:
        parts.append(_num_to_words(n // 1000) + " thousand")
        n %= 1000
    if n >= 100:
        parts.append(ONES[n // 100] + " hundred")
        n %= 100
    if n >= 20:
        parts.append(TENS[n // 10] + ("-" + ONES[n % 10] if n % 10 else ""))
    elif n > 0:
        parts.append(ONES[n])
    return " ".join(parts)

def prep_text(text):
    """Replace digits with words and strip special chars ChatTTS can't handle."""
    text = re.sub(r'\d+', lambda m: _num_to_words(m.group()), text)
    text = text.replace("-", " ")
    text = re.sub(r'[^\w\s.,;:!?\'"]', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text

# ── Request schema ──────────────────────────────────────────
class TTSRequest(BaseModel):
    text: str

# ── Endpoint ────────────────────────────────────────────────
@app.post("/tts")
def generate_speech(req: TTSRequest):
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="text is required")
    if tts is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        # HAL 9000 voice: cold, flat, unwavering
        # Low temperature = no emotional variance, no pitch fluctuation
        params_infer_code = ChatTTS.Chat.InferCodeParams(
            temperature=0.1,
            top_P=0.7,
            top_K=20,
        )
        params_infer_code.spk_emb = spk_emb

        # Strict refine: slow speed, no random oral sounds/laughs/breaks
        params_refine_text = ChatTTS.Chat.RefineTextParams(
            prompt='[speed_3]',
        )

        clean_text = prep_text(req.text)

        wavs = tts.infer(
            [clean_text],
            params_infer_code=params_infer_code,
            params_refine_text=params_refine_text,
            use_decoder=True,
        )

        # ChatTTS returns list of numpy arrays, take first
        audio = wavs[0]
        if audio.ndim > 1:
            audio = audio[0]

        # Low-pass filter to strip high-frequency crackling artifacts
        b, a = butter(6, 6000, btype='low', fs=24000)
        audio = lfilter(b, a, audio).astype(np.float32)

        # Normalize peak to 0.85 to prevent clipping distortion
        peak = np.max(np.abs(audio))
        if peak > 0:
            audio = audio * (0.85 / peak)

        # Fade in/out to prevent click artifacts at boundaries
        fade_len = min(480, len(audio) // 4)  # 20ms at 24kHz
        audio[:fade_len] *= np.linspace(0, 1, fade_len).astype(np.float32)
        audio[-fade_len:] *= np.linspace(1, 0, fade_len).astype(np.float32)

        # Convert to int16 WAV
        audio_int16 = (audio * 32767).astype(np.int16)

        # Write WAV to buffer
        buf = io.BytesIO()
        wavfile.write(buf, 24000, audio_int16)
        buf.seek(0)

        return Response(content=buf.read(), media_type="audio/wav")

    except Exception as e:
        print(f"[HAL] TTS error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ── Health check ────────────────────────────────────────────
@app.get("/health")
def health():
    return {"status": "ok", "model_loaded": tts is not None}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5050)
