import io
import torch
import ChatTTS
import numpy as np
from scipy.io import wavfile
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

app = FastAPI(title="VERITAS TTS — HAL 9000")

# ── Model (loaded once at startup) ──────────────────────────
tts = None

@app.on_event("startup")
def load_model():
    global tts
    print("[HAL] Loading ChatTTS model...")
    tts = ChatTTS.Chat()
    tts.load(compile=False)  # compile=True needs triton, skip on macOS
    print("[HAL] Model loaded. Ready.")

# ── Request schema ──────────────────────────────────────────
class TTSRequest(BaseModel):
    text: str

# ── Endpoint ────────────────────────────────────────────────
@app.post("/tts")
def generate_speech(req: TTSRequest):
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="text is required")

    try:
        # HAL 9000 voice params: flat, monotone, deliberate
        params = ChatTTS.Chat.InferCodeParams(
            temperature=0.1,
            top_P=0.5,
            top_K=10,
        )

        # Use a fixed speaker seed for consistent voice across restarts
        torch.manual_seed(42)
        spk = tts.sample_random_speaker()
        params.spk_emb = spk

        wavs = tts.infer(
            [req.text],
            params_infer_code=params,
            use_decoder=True,
        )

        # ChatTTS returns list of numpy arrays, take first
        audio = wavs[0]
        if audio.ndim > 1:
            audio = audio[0]

        # Normalize to int16 WAV
        audio = np.clip(audio, -1.0, 1.0)
        audio_int16 = (audio * 32767).astype(np.int16)

        # Write WAV to buffer
        buf = io.BytesIO()
        wavfile.write(buf, 24000, audio_int16)  # ChatTTS default sample rate
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
