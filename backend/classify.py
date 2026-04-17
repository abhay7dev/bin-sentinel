"""Single-call image classifier: sends image + full city MRF doc to Claude in one request."""

import base64
import hashlib
import json
import os
import time

from dotenv import load_dotenv
from perplexity import Perplexity

MODEL_ID = "anthropic/claude-sonnet-4-6"

load_dotenv()

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")

pplx_client = Perplexity(api_key=os.getenv("PERPLEXITY_API_KEY"))

SYSTEM_PROMPT = """You are a recycling compliance system for a Materials Recovery Facility.
You reason strictly from the facility documentation provided. Never use general knowledge.

STEP 1: Identify the PRIMARY disposable/waste item in the image.
Ignore people, hands, background, furniture, and surfaces.
If there is no disposable or waste item visible, return {"action":"N/A"}.

STEP 2: Classify it using ONLY the facility specs below.

When the item is black plastic of any kind, you MUST state that NIR optical
sorters cannot detect carbon-black pigmented polymers.

Return ONLY a JSON object with exactly these keys:
- item: specific name (e.g. "black plastic takeout container", "clear PET water bottle")
- action: "RECYCLE", "TRASH", "COMPOST", or "SPECIAL"
  - COMPOST: only for cities with composting programs, only for food waste/food-soiled items
  - SPECIAL: only for hazardous/regulated items (batteries, electronics, paint, chemicals)
  - TRASH: everything else not recyclable or compostable
- reason: one sentence citing specific facility equipment or rule from the docs
- confidence: "high", "medium", or "low"

No preamble. No markdown. No text outside the JSON object."""

# Load all city MRF docs into memory at startup
_city_docs: dict[str, str] = {}

CITY_FILES = {
    "seattle": "seattle_mrf.txt",
    "nyc": "nyc_mrf.txt",
    "la": "la_mrf.txt",
    "chicago": "chicago_mrf.txt",
}

_city_doc_hashes: dict[str, str] = {}

for city_key, filename in CITY_FILES.items():
    filepath = os.path.join(DATA_DIR, filename)
    if os.path.exists(filepath):
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
        _city_docs[city_key] = content
        _city_doc_hashes[city_key] = hashlib.sha256(content.encode()).hexdigest()[:12]
        print(f"[classify] loaded {filename} ({len(content)} chars, hash={_city_doc_hashes[city_key]})")


def _detect_mime_type(image_bytes: bytes) -> str:
    if image_bytes[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if image_bytes[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if image_bytes[:4] == b"RIFF" and image_bytes[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


class ClassificationError(Exception):
    """Wraps classify failures with structured retry/permanent hints."""

    def __init__(self, message: str, *, retryable: bool = False, raw: str = ""):
        super().__init__(message)
        self.retryable = retryable
        self.raw = raw


def classify_image(image_bytes: bytes, city: str) -> dict:
    """Single API call: identify item from image + classify against city MRF docs.

    Returns dict with keys: item, action, reason, confidence, _meta (timing/model info).
    Raises ClassificationError on failure.
    """
    t0 = time.monotonic()

    city_doc = _city_docs.get(city)
    if not city_doc:
        raise ClassificationError(f"No MRF document found for city: {city}", retryable=False)

    mime_type = _detect_mime_type(image_bytes)
    b64 = base64.b64encode(image_bytes).decode()
    data_uri = f"data:{mime_type};base64,{b64}"
    t_prep = time.monotonic()

    user_prompt = f"""FACILITY SPECS ({city} MRF documentation):
{city_doc}

CITY: {city}

Look at the image and classify the waste item based only on the facility specs above."""

    try:
        response = pplx_client.responses.create(
            model=MODEL_ID,
            instructions=SYSTEM_PROMPT,
            input=[
                {
                    "type": "message",
                    "role": "user",
                    "content": [
                        {"type": "input_text", "text": user_prompt},
                        {"type": "input_image", "image_url": data_uri},
                    ],
                }
            ],
            max_output_tokens=200,
        )
    except Exception as e:
        raise ClassificationError(
            f"Model API error: {e}", retryable=True
        ) from e

    t_model = time.monotonic()

    raw = response.output_text.strip()

    if raw.startswith("```"):
        raw = raw.split("\n", 1)[-1]
        raw = raw.rsplit("```", 1)[0]
        raw = raw.strip()

    try:
        result = json.loads(raw)
    except json.JSONDecodeError:
        print(f"[classify] JSON parse error. Raw: {raw}")
        raise ClassificationError(
            "Model returned malformed JSON", retryable=True, raw=raw[:500]
        )

    t_parse = time.monotonic()

    timings = {
        "prep_ms": int((t_prep - t0) * 1000),
        "model_ms": int((t_model - t_prep) * 1000),
        "parse_ms": int((t_parse - t_model) * 1000),
        "total_ms": int((t_parse - t0) * 1000),
        "model": MODEL_ID,
        "mrf_doc_hash": _city_doc_hashes.get(city, ""),
    }

    print(
        f"[classify] {result.get('item')} → {result.get('action')} "
        f"({result.get('confidence')}) [{timings['total_ms']}ms]"
    )

    return {
        "item": result.get("item", "unknown item"),
        "action": result.get("action", "TRASH"),
        "reason": result.get("reason", "No reason provided"),
        "confidence": result.get("confidence", "low"),
        "_meta": timings,
    }
