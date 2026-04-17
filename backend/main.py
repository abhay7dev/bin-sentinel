import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlmodel import Session, select

from classify import ClassificationError, classify_image
from database import create_db_and_tables, engine
from models import MAX_IMAGE_BYTES, Scan
VALID_CITIES = {"seattle", "nyc", "la", "chicago"}


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    print(f"[startup] DB tables created")
    print(f"[startup] CHROMA_PERSIST_DIR = {os.getenv('CHROMA_PERSIST_DIR', './chroma_db')}")
    yield


app = FastAPI(title="Bin Sentinel", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.post("/scan")
async def scan(image: UploadFile = File(None), city: str = Form("seattle")):
    if image is None:
        return JSONResponse(status_code=422, content={"error": "No image provided"})

    if city not in VALID_CITIES:
        return JSONResponse(status_code=422, content={"error": "Invalid city"})

    if image.content_type and not image.content_type.startswith("image/"):
        return JSONResponse(status_code=422, content={"error": "File must be an image"})

    image_bytes = await image.read()

    if len(image_bytes) > MAX_IMAGE_BYTES:
        return JSONResponse(
            status_code=422,
            content={
                "error": "Image too large",
                "detail": f"Max {MAX_IMAGE_BYTES // (1024*1024)} MB",
            },
        )

    if len(image_bytes) == 0:
        return JSONResponse(status_code=422, content={"error": "Empty image file"})

    try:
        result = classify_image(image_bytes, city)
    except ClassificationError as e:
        status = 503 if e.retryable else 500
        content = {"error": "Classification error", "detail": str(e), "retryable": e.retryable}
        if e.raw:
            content["raw_snippet"] = e.raw[:200]
        return JSONResponse(status_code=status, content=content)
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": "Classification error", "detail": str(e), "retryable": False},
        )

    meta = result.pop("_meta", {})
    result["city"] = city

    if result["action"] != "N/A":
        with Session(engine) as session:
            scan_record = Scan(
                item=result["item"],
                action=result["action"],
                reason=result["reason"],
                confidence=result["confidence"],
                city=city,
                model=meta.get("model", ""),
                latency_ms=meta.get("total_ms"),
            )
            session.add(scan_record)
            session.commit()

    return result


@app.get("/scan/test")
async def scan_test(
    item: str = Query(default="black plastic container"),
    city: str = Query(default="seattle"),
):
    if city not in VALID_CITIES:
        return JSONResponse(status_code=422, content={"error": "Invalid city"})

    synthetic = {
        "item_name": item,
        "material": "unknown",
        "color": "unknown",
        "condition": "normal",
        "is_disposable": True,
    }

    try:
        # Import lazily so the main API can still start even if optional RAG
        # dependencies (e.g. embedding model downloads) are unavailable.
        from rag import get_facility_verdict

        verdict = get_facility_verdict(synthetic, city)
    except ImportError as e:
        return JSONResponse(
            status_code=503,
            content={
                "error": "RAG test endpoint unavailable",
                "detail": f"RAG dependencies could not be initialized: {e}",
            },
        )
    except ValueError as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": "Classification error", "detail": str(e)},
        )

    return {
        "item": item,
        "action": verdict["action"],
        "reason": verdict["reason"],
        "confidence": verdict["confidence"],
        "city": city,
    }


@app.get("/history")
async def history():
    with Session(engine) as session:
        statement = select(Scan).order_by(Scan.timestamp.desc()).limit(10)
        scans = session.exec(statement).all()
        return {
            "scans": [
                {
                    "item": s.item,
                    "action": s.action,
                    "reason": s.reason,
                    "confidence": s.confidence,
                    "city": s.city,
                    "timestamp": s.timestamp.isoformat(),
                }
                for s in scans
            ]
        }


@app.get("/health")
async def health():
    return {"status": "ok"}
