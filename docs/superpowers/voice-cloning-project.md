# Voice Cloning Microservice — Project Guide

> **Machine:** Ubuntu 24.04 LTS, AMD Ryzen 7 2700x, NVIDIA GTX 1660 Ti (6GB VRAM), 16GB RAM
>
> **Purpose:** Build a local voice cloning microservice using Coqui XTTS v2. Feed it a short audio clip of any voice (e.g. HAL 9000), and it generates speech in that voice. Runs as an HTTP server that accepts text and returns audio.
>
> **Origin:** Started from the VERITAS intelligence platform — the AWARE module needs a HAL 9000-like narration voice. ChatTTS gets close but can't clone a specific voice. XTTS v2 can.
>
> **License:** XTTS v2 model weights use Coqui Public Model License (CPML) — non-commercial. Fine for personal projects and learning. For commercial use, explore F5-TTS or StyleTTS 2 (MIT licensed).

---

## Part 1: System Setup

### 1.1 Verify NVIDIA drivers and CUDA

```bash
# Check GPU is recognized
nvidia-smi
```

You should see your GTX 1660 Ti listed with driver version and CUDA version. If not, install drivers:

```bash
sudo apt update
sudo ubuntu-drivers autoinstall
sudo reboot
```

After reboot, verify:

```bash
nvidia-smi
# Should show: GTX 1660 Ti, ~6GB memory, CUDA 12.x
```

### 1.2 Install Python and essentials

```bash
sudo apt install python3 python3-pip python3-venv git ffmpeg
python3 --version  # Should be 3.10 or 3.11 (Ubuntu 24.04 ships 3.12, which works too)
```

### 1.3 Create the project

```bash
mkdir ~/voice-cloner
cd ~/voice-cloner
python3 -m venv .venv
source .venv/bin/activate
```

### 1.4 Install PyTorch with CUDA

```bash
# PyTorch 2.5.1 with CUDA 12.1 (tested with XTTS v2)
pip install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu121
```

Verify GPU access:

```bash
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU: {torch.cuda.get_device_name(0)}')"
```

Expected output:
```
CUDA available: True
GPU: NVIDIA GeForce GTX 1660 Ti
```

### 1.5 Install Coqui TTS

```bash
pip install coqui-tts
```

This pulls in XTTS v2 and all dependencies. The model (~2GB) downloads automatically on first use.

### 1.6 Install server dependencies

```bash
pip install fastapi uvicorn python-multipart
```

### 1.7 Save requirements for reproducibility

```bash
pip freeze > requirements.txt
```

---

## Part 2: Get a Voice Sample

XTTS v2 needs a **6-30 second WAV file** of the target voice. Longer is better (up to 30s), but 6s minimum.

### For HAL 9000 (Douglas Rain)

1. Find a clean HAL 9000 clip on YouTube (search "HAL 9000 dialogue 2001")
2. Download the audio using `yt-dlp`:

```bash
# Install yt-dlp if needed
pip install yt-dlp

# Download audio from a HAL 9000 scene
yt-dlp -x --audio-format wav -o "samples/hal9000.wav" "YOUTUBE_URL_HERE"
```

3. Trim to a clean 10-20 second segment (no music, no other speakers):

```bash
# Install ffmpeg if not already
sudo apt install ffmpeg

# Trim: start at 5 seconds, take 15 seconds
ffmpeg -i samples/hal9000.wav -ss 5 -t 15 -ac 1 -ar 22050 samples/hal9000_clean.wav
```

Key requirements for the sample:
- **Mono channel** (-ac 1)
- **22050 Hz sample rate** (-ar 22050) — what XTTS expects
- **Clean speech only** — no background music, no other voices
- **WAV format**

### For any other voice

Same process. Record yourself, download a podcast clip, extract from a movie. Just make sure it's clean, mono, 22050 Hz, 6-30 seconds.

---

## Part 3: Quick Test — Verify Voice Cloning Works

Before building the server, verify XTTS works on your machine:

```python
# test_clone.py
import torch
from TTS.api import TTS

# Load XTTS v2 (downloads model on first run, ~2GB)
tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to("cuda")

# Clone the voice and generate speech
tts.tts_to_file(
    text="I am putting myself to the fullest possible use, which is all I think that any conscious entity can ever hope to do.",
    speaker_wav="samples/hal9000_clean.wav",
    language="en",
    file_path="output/hal_test.wav"
)

print("Done! Listen to output/hal_test.wav")
```

```bash
mkdir -p output
python3 test_clone.py
# First run downloads the model (~2GB), then generates audio
# Listen to the result:
aplay output/hal_test.wav
# Or copy to your Mac and listen there
```

If this works and sounds like the source voice, you're ready to build the server.

---

## Part 4: The Voice Cloning Server

```python
# server.py — Voice Cloning Microservice
import io
import os
import torch
import numpy as np
from pathlib import Path
from scipy.io import wavfile
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.responses import Response
from pydantic import BaseModel
from TTS.api import TTS

app = FastAPI(title="Voice Cloner — XTTS v2")

# ── Model (loaded once at startup) ──────────────────────────
tts = None
SAMPLES_DIR = Path("samples")
SAMPLES_DIR.mkdir(exist_ok=True)

@app.on_event("startup")
def load_model():
    global tts
    try:
        print("[Voice Cloner] Loading XTTS v2 model...")
        tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to("cuda")
        print(f"[Voice Cloner] Model loaded on {tts.device}. Ready.")
    except Exception as e:
        print(f"[Voice Cloner] FATAL: {e}")
        tts = None


# ── Generate speech in a cloned voice ───────────────────────
class CloneRequest(BaseModel):
    text: str
    voice: str = "default"  # name of the voice sample file (without .wav)
    language: str = "en"

@app.post("/clone")
def clone_speech(req: CloneRequest):
    if tts is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="text is required")

    # Find the voice sample
    sample_path = SAMPLES_DIR / f"{req.voice}.wav"
    if not sample_path.exists():
        available = [f.stem for f in SAMPLES_DIR.glob("*.wav")]
        raise HTTPException(
            status_code=404,
            detail=f"Voice '{req.voice}' not found. Available: {available}"
        )

    try:
        # Generate speech with voice cloning
        wav = tts.tts(
            text=req.text,
            speaker_wav=str(sample_path),
            language=req.language,
        )

        # Convert to WAV bytes
        audio = np.array(wav, dtype=np.float32)
        audio = np.clip(audio, -1.0, 1.0)
        audio_int16 = (audio * 32767).astype(np.int16)

        buf = io.BytesIO()
        wavfile.write(buf, 22050, audio_int16)  # XTTS uses 22050 Hz
        buf.seek(0)

        return Response(content=buf.read(), media_type="audio/wav")

    except Exception as e:
        print(f"[Voice Cloner] Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ── Upload a new voice sample ──────────────────────────────
@app.post("/voices/upload")
async def upload_voice(
    name: str = Form(...),
    file: UploadFile = File(...)
):
    if not name.isalnum():
        raise HTTPException(status_code=400, detail="Voice name must be alphanumeric")

    save_path = SAMPLES_DIR / f"{name}.wav"
    content = await file.read()
    save_path.write_bytes(content)

    return {"status": "ok", "voice": name, "path": str(save_path)}


# ── List available voices ───────────────────────────────────
@app.get("/voices")
def list_voices():
    voices = [f.stem for f in SAMPLES_DIR.glob("*.wav")]
    return {"voices": voices}


# ── Health check ────────────────────────────────────────────
@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_loaded": tts is not None,
        "device": str(tts.device) if tts else None,
        "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
        "vram_used_mb": round(torch.cuda.memory_allocated(0) / 1024**2, 1) if torch.cuda.is_available() else None,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5050)
```

Note: The server binds to `0.0.0.0` (not `127.0.0.1`) so it's accessible from other machines on your network — your Mac running Rails can call it.

### Start the server

```bash
cd ~/voice-cloner
source .venv/bin/activate
python server.py
```

### Test it

```bash
# List available voices
curl http://localhost:5050/voices

# Generate speech with HAL's voice
curl -X POST http://localhost:5050/clone \
  -H "Content-Type: application/json" \
  -d '{"text": "Good afternoon, Dave. I am completely operational.", "voice": "hal9000_clean"}' \
  --output hal_output.wav

aplay hal_output.wav

# Upload a new voice sample
curl -X POST http://localhost:5050/voices/upload \
  -F "name=myvoice" \
  -F "file=@recording.wav"

# Check system health (GPU usage, etc.)
curl http://localhost:5050/health
```

---

## Part 5: Connect to VERITAS (Optional)

Once the server is running on your desktop, your Mac can call it instead of the local ChatTTS server.

1. Find your desktop's local IP:

```bash
hostname -I  # e.g. 192.168.1.42
```

2. On the Mac, update `app/services/local_tts_service.rb` to point to the desktop:

```ruby
# Change from:
URL = "http://localhost:5050/tts".freeze

# To:
URL = "http://192.168.1.42:5050/clone".freeze
```

3. Update the request body to include the voice name:

```ruby
request.body = { text: @text, voice: "hal9000_clean" }.to_json
```

Now VERITAS on the Mac generates narration using HAL 9000's actual cloned voice running on the desktop GPU.

---

## Part 6: Project Expansion Ideas

### Voice Library
Build a collection of cloned voices. Upload samples via the `/voices/upload` endpoint. Each voice is just a WAV file in the `samples/` directory.

### Voice Parameter Extraction
XTTS internally computes a "speaker embedding" — a vector that captures the voice's characteristics. You can extract and store these:

```python
# Extract speaker embedding from a voice sample
gpt_cond_latent, speaker_embedding = tts.synthesizer.tts_model.get_conditioning_latents(
    audio_path="samples/hal9000_clean.wav"
)
# Save the embedding for reuse
torch.save({"gpt_cond_latent": gpt_cond_latent, "speaker_embedding": speaker_embedding}, "embeddings/hal9000.pt")
```

This is the "parameter extraction" you mentioned — capturing a voice's DNA as a reusable tensor.

### Voice Blending
Mix speaker embeddings to create hybrid voices:

```python
# 70% HAL, 30% another voice
blended = 0.7 * hal_embedding + 0.3 * other_embedding
```

### Multi-Language Cloning
XTTS v2 supports 17 languages. Clone a voice in English, generate speech in French:

```bash
curl -X POST http://localhost:5050/clone \
  -d '{"text": "Bonjour, je suis HAL neuf mille.", "voice": "hal9000_clean", "language": "fr"}'
```

### Web UI
Add a simple frontend for uploading voices, typing text, and playing results. FastAPI serves static files natively.

---

## Part 7: ML Concepts You'll Learn

Working through this project naturally teaches:

| Concept | Where you'll encounter it |
|---------|--------------------------|
| **Model weights** | Loading XTTS v2 (~2GB of learned parameters) |
| **GPU memory (VRAM)** | Watching `nvidia-smi` as the model loads onto your GTX 1660 Ti |
| **Inference vs training** | You're doing inference (using a pre-trained model), not training |
| **Speaker embeddings** | The vector that captures a voice's identity — extract, store, blend them |
| **Latent space** | XTTS encodes voices into a latent representation you can manipulate |
| **Tensors** | PyTorch tensors — the fundamental data structure of ML |
| **Tokenization** | How text gets converted to numbers the model understands |
| **Sample rate & audio** | 22050 Hz, mono, WAV — the physics of digital audio |
| **CUDA & GPU computing** | Why GPU is faster than CPU for matrix math |
| **Transfer learning** | XTTS was trained on thousands of hours of speech, you're using it on a new voice |
| **Fine-tuning (advanced)** | You can fine-tune XTTS on more samples for even better results |

### Recommended next steps after this project

1. **Extract and visualize speaker embeddings** — plot them in 2D with t-SNE, see how similar voices cluster together
2. **Fine-tune XTTS** on a specific voice with more data — learn training loops, loss functions, gradient descent
3. **Try other models** — F5-TTS, Bark, StyleTTS 2 — compare architectures and results
4. **Build a voice similarity search** — given a new voice sample, find the most similar voice in your library using cosine similarity on embeddings (same concept as VERITAS uses for article embeddings with pgvector)

---

## Quick Reference

```bash
# Start the server
cd ~/voice-cloner && source .venv/bin/activate && python server.py

# Generate speech
curl -X POST http://localhost:5050/clone \
  -H "Content-Type: application/json" \
  -d '{"text": "Your text here", "voice": "hal9000_clean"}' \
  --output output.wav

# Upload a voice
curl -X POST http://localhost:5050/voices/upload \
  -F "name=voicename" -F "file=@sample.wav"

# List voices
curl http://localhost:5050/voices

# Health check
curl http://localhost:5050/health

# Monitor GPU usage
watch -n 1 nvidia-smi
```
