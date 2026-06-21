# Local ChatTTS HAL 9000 Voice — Design Spec

## Goal

Replace the broken ElevenLabs TTS dependency with a local Python ChatTTS microservice that produces a HAL 9000-style voice (flat, monotone, deliberate, calm) for the AWARE narration, running entirely on the same Mac alongside Rails.

## Architecture

A standalone Python FastAPI server runs on `localhost:5050`. It loads the ChatTTS model once at startup using Apple Metal (MPS) for GPU acceleration on Apple Silicon. It exposes a single endpoint that accepts text and returns audio.

On the Rails side, a new `LocalTtsService` calls the local server. The existing `PagesController#aware_narration` action tries local TTS first, falls back to ElevenLabs, and the frontend further falls back to browser Web Speech API if both fail.

### Fallback chain

1. **Local ChatTTS** (`localhost:5050`) — HAL voice, best quality, zero API cost
2. **ElevenLabs** (if API key is valid) — kept as optional remote fallback
3. **Browser Web Speech API** — always available, lowest quality

### System diagram

```
Browser                  Rails (bin/dev)              Python (server.py)
  |                          |                              |
  |-- GET /api/aware_narration -->                          |
  |                          |-- POST localhost:5050/tts --> |
  |                          |       (text payload)         |
  |                          |<-- WAV audio bytes --------- |
  |<-- audio/wav ----------- |                              |
  |                          |                              |
  | (if local TTS down, try ElevenLabs, then browser TTS)   |
```

## Python TTS Server

### Location

`tts_service/` directory at the project root, fully separate from Rails.

### Files

- `tts_service/server.py` — FastAPI app, model loading, single `/tts` endpoint
- `tts_service/requirements.txt` — Python dependencies

### Endpoint

```
POST /tts
Content-Type: application/json
Body: { "text": "The narration text..." }
Response: audio/wav binary
```

### Voice configuration (HAL 9000)

- **Temperature:** 0.1-0.3 (flat, predictable)
- **Top-P:** 0.5 (constrains randomness)
- **Speed:** Slightly slow (deliberate pacing)
- **Speaker seed:** A hardcoded seed number that produces a deep, calm male voice (determined experimentally at setup time)

### Hardware

- Apple M1 Mac (same machine as Rails)
- Uses MPS (Metal Performance Shaders) for GPU acceleration via PyTorch
- Model loads once at startup, stays resident in memory

### Dependencies

- `fastapi` + `uvicorn` — HTTP server
- `ChatTTS` — text-to-speech model
- `torch` — PyTorch with MPS backend
- `numpy`, `scipy` — audio processing

## Rails Integration

### New file: `app/services/local_tts_service.rb`

Mirrors the `ElevenLabsService` pattern:
- Accepts `text:` parameter
- POSTs to `http://localhost:5050/tts` with JSON body
- Returns raw audio bytes on success, `nil` on failure
- 5-second connect timeout, 30-second read timeout
- Rescues all errors and returns `nil` (never breaks the pipeline)

### Modified: `app/controllers/pages_controller.rb`

The `aware_narration` action changes from:

```ruby
audio = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
  ElevenLabsService.new(text: narration_text).call
end
```

To:

```ruby
audio = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
  LocalTtsService.new(text: narration_text).call ||
    ElevenLabsService.new(text: narration_text).call
end
```

The response content type adapts based on which service succeeded:
- Local TTS returns WAV → `audio/wav`
- ElevenLabs returns MP3 → `audio/mpeg`

The cache key includes a hash of the narration text, so it only regenerates when the content changes.

### No frontend changes needed

The `aware_consciousness_controller.js` already creates an `Audio` object from a blob URL. Both WAV and MP3 are natively supported by the browser `Audio` API. The browser TTS fallback remains as-is.

## Developer Workflow

Two terminals:

1. `bin/dev` — Rails + Solid Queue
2. `cd tts_service && python server.py` — ChatTTS on port 5050

The TTS server is optional. If it's not running, VERITAS still works via the fallback chain.

## Error Handling

- `LocalTtsService` returns `nil` on any failure (connection refused, timeout, server error)
- Rails logs the failure at warn level and proceeds to the next fallback
- The Python server returns HTTP 500 with a JSON error body if ChatTTS fails
- No retry logic — the fallback chain handles resilience

## Testing

- `test/services/local_tts_service_test.rb` — unit tests with stubbed HTTP responses (success, timeout, connection refused)
- Manual test: start the Python server, load the AWARE page, verify audio plays automatically with HAL voice
