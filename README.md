# Bin Sentinel

Bin Sentinel is a facility-aware recycling classification system that uses a camera to identify disposable objects via Google Cloud Vision, retrieves local Materials Recovery Facility (MRF) specs through a LangChain RAG pipeline, and returns a RECYCLE / TRASH / COMPOST verdict with facility-specific reasoning — because recyclability is local, and our system knows exactly why.

## Quickstart

```bash
cd backend && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt
```

Copy `.env.example` to `.env` and fill in your API keys, then start the server:

```bash
uvicorn main:app --reload
```
