import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlmodel import Session, select

from database import create_db_and_tables, engine
from models import Scan
from rag import get_facility_verdict
from vision import identify_object

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

    vision_result = identify_object(image_bytes)
    normalized = vision_result["normalized"]
    print(f"[scan] normalized: {normalized}")

    try:
        verdict = get_facility_verdict(normalized, city)
    except ValueError as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": "Vision API error", "detail": str(e)},
        )

    item_name = vision_result["label"]
    result = {
        "item": item_name,
        "action": verdict["action"],
        "reason": verdict["reason"],
        "confidence": verdict["confidence"],
        "city": city,
    }

    with Session(engine) as session:
        scan_record = Scan(
            item=item_name,
            action=verdict["action"],
            reason=verdict["reason"],
            confidence=verdict["confidence"],
            city=city,
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

    try:
        verdict = get_facility_verdict(item, city)
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
