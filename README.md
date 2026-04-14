# Bin Sentinel

Bin Sentinel is a facility-aware recycling classification system. The camera captures an item; the backend identifies and classifies it using local Materials Recovery Facility (MRF) specs and returns a RECYCLE / TRASH / COMPOST verdict with facility-specific reasoning — because recyclability is local, and our system explains exactly why.

## Quickstart

```bash
cd backend && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt
```

Copy `.env.example` to `.env` and fill in your API keys, then start the server:

```bash
uvicorn main:app --reload
```

### Native iOS frontend

A native SwiftUI app lives in `BinSentinelIPad/`. Open `BinSentinelIPad/BinSentinelIPad.xcodeproj` in Xcode to build and run on a simulator or device.

---

## Submission / Project Description

### Inspiration

Recycling sounds simple — but it isn't. The rules are different in every city, change over time, and are almost never communicated clearly at the point where it actually matters: the bin. The result is **wish-cycling**, where people put items in recycling hoping they count, and contamination quietly ruins entire loads downstream.

We wanted to solve this at the source. Not an app you open before you leave the house, not a pamphlet on the side of the bin — a system that watches what you're about to throw away and tells you exactly what to do, in real time, right there.

What pushed us further was realizing that most recycling tools treat disposal as a two-state problem: recyclable or not. But there's a third category that almost nobody addresses — **hazardous items**. Phones, vape pens, earbuds, and old electronics contain lithium batteries that don't belong in any standard bin, and most people have no idea. We wanted Bin Sentinel to be the first consumer-facing recycling product that treats hazardous detection as a first-class feature.

### What it does

Bin Sentinel is a real-time computer vision system designed to sit at the bin. A camera feed in the browser detects when an object is in frame (using in-browser object detection) and triggers a capture; that **image** is sent to the backend. The backend uses **Claude (via Perplexity API)** with the image and the **full MRF (Materials Recovery Facility) guideline document** for the selected city — **Seattle, New York City, Chicago, or Los Angeles** — in a single request. Claude identifies the item from the image and classifies it against those specs, returning whether it is recyclable, trash, compost, or hazardous, with a city-specific explanation of why.

We also built a **RAG pipeline** (ChromaDB + LangChain + sentence-transformers) that chunks and embeds the same MRF docs for retrieval-based classification; it powers our test endpoint and could be used for alternative flows. The main user-facing scan uses the full-doc-in-prompt approach for simplicity and reliability.

### How we built it

- **Frontend:** React + Vite + Tailwind CSS. **TensorFlow.js COCO-SSD** runs in the browser for real-time object detection: it draws the green box around the item and decides when to trigger a capture (with stability and motion fallbacks for items COCO-SSD doesn't recognize). The captured image is then sent to the backend.
- **Backend:** FastAPI. One main path: receive image + city, load that city's full MRF text from disk, send **image + full MRF doc** in a single request to **Claude via Perplexity API**. Claude (multimodal) identifies the item and classifies it; we return the verdict and log it to SQLite.
- **Disposal categories:** Recyclable · Trash · Compost · Hazardous (special disposal).

### Challenges we ran into

**Cleaning the MRF guideline data was harder than expected.** Real municipal recycling documentation is not structured for machine consumption. Guidelines are buried in PDFs, use inconsistent terminology across cities, and contain overlapping or contradictory rules by material type. Getting the source data into a state where we could use it reliably — whether as full-doc context or as retrievable chunks for our RAG pipeline — required significant iteration on chunking, cleaning, and structure.

**CV behavior in an uncontrolled environment was a real problem.** COCO-SSD would frequently pick up background objects rather than the item being presented, and would misidentify or miss items under suboptimal lighting. We iterated on the detection logic extensively: confidence thresholds, picking a single "best" detection, constraining when we trigger (frame stability, time-based fallback), and a motion-based fallback so flexible packaging like chip bags still gets a box and can be scanned. The backend does its own vision (Claude sees the image), but the frontend still had to send the right frame at the right time.

**We switched vision providers mid-build.** We started with Google Cloud Vision API for item identification but found the label granularity too coarse and the results often inaccurate. We removed it and moved to **Claude Sonnet via Perplexity** for the whole pipeline: the backend now sends the image directly to Claude, which both identifies and classifies the item in one call. That proved much more effective.

### Accomplishments that we're proud of

Getting the full pipeline — camera to classification to city-specific disposal reasoning — running end-to-end is something we're genuinely proud of. The frontend handles real-time detection and framing in the browser; the backend does a single, clear request (image + city MRF doc → verdict). The system handles four disposal categories including **hazardous (special disposal)**, which no consumer recycling product we found treats as a primary feature.

We're also proud of the RAG pipeline we built. Ingesting and cleaning real MRF guidelines from four major US cities and making them reliably retrievable (ChromaDB + sentence-transformers) required real work. The main scan flow currently uses the full doc in the prompt, but the RAG path is there for the test endpoint and for future retrieval-based flows, and the result is a system that can ground answers in actual municipal policy rather than generic recycling rules.

### What we learned

Building from real-world municipal data is a lesson in how messy real data is. The problem isn't retrieval technology — ChromaDB and sentence-transformers handle that well. The problem is what you feed in. Garbage in, garbage out applies more literally than usual when you're building a recycling product.

We also learned that the frontend detection layer and the backend reasoning layer need to be designed together. The frontend decides *when* to capture and *what* frame to send; the backend does the actual identification and classification from that image. Prompt engineering for Claude was tied to understanding what kinds of images we were actually sending — framing, lighting, single vs. multiple objects — so both pieces had to be developed and tested in tandem.

### What's next

Bin Sentinel in its current form is a proof of concept, but the same pipeline is the foundation for something significantly more ambitious: **fully automated single-chute sorting**. One bin, no decision required from the consumer, with a downstream robotic system routing every item correctly. The technology demonstrated here is the sensing and reasoning layer that makes that vision possible.

On the nearer-term roadmap: expanding and automating MRF doc creation across the US, adding contamination-state detection (a clean pizza box vs. a greasy one should get different answers), and building a location-level analytics layer so building managers and city sustainability departments can see real-time contamination patterns — data that currently doesn't exist at that resolution anywhere.

