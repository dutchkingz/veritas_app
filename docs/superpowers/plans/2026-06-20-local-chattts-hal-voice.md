# Local ChatTTS HAL 9000 Voice — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run a local Python ChatTTS microservice on localhost:5050 that produces HAL 9000-style narration audio, and wire it into the VERITAS AWARE page as the primary TTS source.

**Architecture:** A standalone FastAPI server loads ChatTTS once at startup using Apple MPS (Metal) for GPU acceleration, exposes `POST /tts`, and returns WAV audio. A new `LocalTtsService` in Rails calls it, falling back to ElevenLabs then browser TTS if unavailable.

**Tech Stack:** Python 3, FastAPI, uvicorn, ChatTTS, PyTorch (MPS), scipy; Ruby on Rails 8.1, Net::HTTP

---

## File Structure

| File | Responsibility |
|------|---------------|
| `tts_service/requirements.txt` | Python dependencies |
| `tts_service/server.py` | FastAPI app — loads ChatTTS, serves `POST /tts` |
| `app/services/local_tts_service.rb` | Rails HTTP client for the local TTS server |
| `app/controllers/pages_controller.rb` | Wire `LocalTtsService` into `aware_narration` action |
| `test/services/local_tts_service_test.rb` | Unit tests for the Rails service |

---

### Task 1: Python TTS Server — Dependencies & FastAPI App

**Files:**
- Create: `tts_service/requirements.txt`
- Create: `tts_service/server.py`

- [ ] **Step 1: Create the requirements file**

```txt
fastapi>=0.110
uvicorn[standard]>=0.29
ChatTTS>=0.2
torch>=2.2
scipy>=1.12
numpy>=1.26
```

- [ ] **Step 2: Create the FastAPI server**

```python
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
```

- [ ] **Step 3: Test the server manually**

```bash
cd tts_service
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

Wait for `[HAL] Model loaded. Ready.` to appear. Then in another terminal:

```bash
curl -X POST http://localhost:5050/tts \
  -H "Content-Type: application/json" \
  -d '{"text": "I am putting myself to the fullest possible use."}' \
  --output test.wav
```

Expected: `test.wav` is a valid WAV file. Play it with `afplay test.wav`. The voice should be flat and monotone.

Also check health:

```bash
curl http://localhost:5050/health
```

Expected: `{"status":"ok","model_loaded":true}`

- [ ] **Step 4: Tune the speaker seed (optional)**

If seed 42 doesn't sound deep/calm enough, try other seeds. Change `torch.manual_seed(42)` to other values (e.g. 7, 100, 2024) and re-run the curl test, listening to each. Pick the most HAL-like seed and hardcode it.

- [ ] **Step 5: Add tts_service to .gitignore for venv and cache**

Add to the project root `.gitignore`:

```
# ChatTTS local server
tts_service/.venv/
tts_service/__pycache__/
```

- [ ] **Step 6: Commit**

```bash
git add tts_service/requirements.txt tts_service/server.py .gitignore
git commit -m "feat: add local ChatTTS microservice for HAL 9000 voice"
```

---

### Task 2: Rails LocalTtsService

**Files:**
- Create: `test/services/local_tts_service_test.rb`
- Create: `app/services/local_tts_service.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/services/local_tts_service_test.rb
require "test_helper"
require "webmock/minitest"

class LocalTtsServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "returns audio bytes on successful response" do
    stub_request(:post, "http://localhost:5050/tts")
      .with(body: { text: "Hello world" }.to_json)
      .to_return(status: 200, body: "RIFF\x00\x00\x00\x00WAVEfmt ", headers: { "Content-Type" => "audio/wav" })

    result = LocalTtsService.new(text: "Hello world").call
    assert_equal "RIFF\x00\x00\x00\x00WAVEfmt ", result
  end

  test "returns nil when server is unreachable" do
    stub_request(:post, "http://localhost:5050/tts")
      .to_raise(Errno::ECONNREFUSED)

    result = LocalTtsService.new(text: "Hello world").call
    assert_nil result
  end

  test "returns nil on server error" do
    stub_request(:post, "http://localhost:5050/tts")
      .to_return(status: 500, body: '{"detail":"model crashed"}')

    result = LocalTtsService.new(text: "Hello world").call
    assert_nil result
  end

  test "returns nil when text is blank" do
    result = LocalTtsService.new(text: "").call
    assert_nil result
  end

  test "returns nil on timeout" do
    stub_request(:post, "http://localhost:5050/tts")
      .to_raise(Net::ReadTimeout)

    result = LocalTtsService.new(text: "Hello world").call
    assert_nil result
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bin/rails test test/services/local_tts_service_test.rb
```

Expected: `NameError: uninitialized constant LocalTtsService`

- [ ] **Step 3: Install webmock gem (if not present)**

Check `Gemfile` for `webmock`. If not present, add to the `:test` group:

```ruby
group :test do
  gem "webmock"
end
```

Then run `bundle install`.

- [ ] **Step 4: Write the LocalTtsService**

```ruby
# app/services/local_tts_service.rb
class LocalTtsService
  URL = "http://localhost:5050/tts".freeze

  def initialize(text:)
    @text = text
  end

  def call
    return nil if @text.blank?

    uri = URI(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = { text: @text }.to_json

    response = http.request(request)

    if response.code == "200"
      response.body
    else
      Rails.logger.warn "[LocalTTS] Server returned #{response.code}: #{response.body.first(200)}"
      nil
    end
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Rails.logger.warn "[LocalTTS] Unavailable: #{e.class} — falling back"
    nil
  rescue StandardError => e
    Rails.logger.error "[LocalTTS] Unexpected error: #{e.class} #{e.message}"
    nil
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rails test test/services/local_tts_service_test.rb
```

Expected: 5 tests, 5 assertions, 0 failures, 0 errors

- [ ] **Step 6: Commit**

```bash
git add app/services/local_tts_service.rb test/services/local_tts_service_test.rb
git commit -m "feat: add LocalTtsService — HTTP client for local ChatTTS server"
```

---

### Task 3: Wire LocalTtsService into PagesController

**Files:**
- Modify: `app/controllers/pages_controller.rb:80-94` (the `aware_narration` action)

- [ ] **Step 1: Update the aware_narration action**

Replace the existing `aware_narration` method (lines 80-94 of `app/controllers/pages_controller.rb`):

```ruby
# GET /api/aware_narration — TTS audio of the VERITAS self-narration
def aware_narration
  narration_text = build_aware_narration
  cache_key = "aware_narration/#{Digest::MD5.hexdigest(narration_text)}"

  audio_data = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    local_audio = LocalTtsService.new(text: narration_text).call
    if local_audio
      { bytes: local_audio, type: "audio/wav" }
    else
      eleven_audio = ElevenLabsService.new(text: narration_text).call
      eleven_audio ? { bytes: eleven_audio, type: "audio/mpeg" } : nil
    end
  end

  if audio_data
    send_data audio_data[:bytes], type: audio_data[:type], disposition: "inline"
  else
    head :service_unavailable
  end
end
```

This stores both the audio bytes and the content type in the cache so the correct MIME type is returned regardless of which service generated the audio.

- [ ] **Step 2: Verify manually**

Start the Python TTS server in one terminal:

```bash
cd tts_service && source .venv/bin/activate && python server.py
```

Start Rails in another terminal:

```bash
bin/dev
```

Open the AWARE page in the browser. The narration should autoplay with the ChatTTS HAL voice instead of the browser's built-in speech. Check the Rails log for absence of `[LocalTTS] Unavailable` messages.

- [ ] **Step 3: Verify fallback**

Stop the Python TTS server (Ctrl+C). Clear the Rails cache:

```bash
bin/rails runner "Rails.cache.clear"
```

Reload the AWARE page. The narration should fall through to browser Web Speech API (you'll see `[LocalTTS] Unavailable: Errno::ECONNREFUSED` in the Rails log).

- [ ] **Step 4: Commit**

```bash
git add app/controllers/pages_controller.rb
git commit -m "feat: wire LocalTtsService into AWARE narration with fallback chain"
```

---

### Task 4: Cleanup — Add .gitignore entries and update console log

**Files:**
- Modify: `.gitignore`
- Modify: `app/javascript/controllers/aware_consciousness_controller.js` (remove voice debug logging)

- [ ] **Step 1: Add tts_service ignores to .gitignore**

Append to the project root `.gitignore`:

```
# Local ChatTTS server
tts_service/.venv/
tts_service/__pycache__/
```

- [ ] **Step 2: Remove the temporary voice listing log from the Stimulus controller**

In `app/javascript/controllers/aware_consciousness_controller.js`, remove the console.log line that lists all available English voices (it was added for debugging during voice selection):

Find this line:
```javascript
    console.log("[VERITAS Voice] Available English voices:", enVoices.map(v => `${v.name} (${v.lang})`).join(", "))
```

Remove it entirely. Keep the `console.log("[VERITAS Voice] HAL mode — using:", preferred.name)` line — that one is useful for confirming which fallback voice is active.

- [ ] **Step 3: Commit**

```bash
git add .gitignore app/javascript/controllers/aware_consciousness_controller.js
git commit -m "chore: add tts_service to gitignore, remove debug voice listing"
```
