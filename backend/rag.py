import json
import os

import chromadb
from dotenv import load_dotenv
from langchain_community.vectorstores import Chroma
from langchain_huggingface import HuggingFaceEmbeddings
from perplexity import Perplexity

load_dotenv()

CHROMA_PERSIST_DIR = os.getenv("CHROMA_PERSIST_DIR", "./chroma_db")

SYSTEM_PROMPT = """You are a recycling compliance system for a Materials Recovery Facility.
You reason strictly from the facility documentation provided. Never use general knowledge.

When the item is black plastic of any kind, you MUST state in the reason that NIR optical
sorters cannot detect carbon-black pigmented polymers.

Return ONLY a JSON object with exactly these keys:
- action: "RECYCLE", "TRASH", or "COMPOST" (COMPOST only valid for NYC)
- reason: one sentence citing specific facility equipment or rule from the retrieved docs
- confidence: "high", "medium", or "low"

No preamble. No markdown. No text outside the JSON object."""

HUMAN_PROMPT = """FACILITY SPECS (retrieved from {city} MRF documentation):
{context}

ITEM DETECTED: {item}
CITY: {city}

Classify this item based only on the facility specs above."""

embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

chroma_client = chromadb.PersistentClient(path=CHROMA_PERSIST_DIR)
vectorstore = Chroma(
    client=chroma_client,
    collection_name="mrf_docs",
    embedding_function=embeddings,
)

pplx_client = Perplexity(api_key=os.getenv("PERPLEXITY_API_KEY"))


def get_facility_verdict(normalized_item: str, city: str) -> dict:
    query = f"{normalized_item} {city} MRF recycling"
    docs = vectorstore.similarity_search(query, k=4)

    if not docs:
        raise ValueError("No facility documents found — cannot classify without MRF specs")

    context = "\n\n".join(doc.page_content for doc in docs)

    prompt = HUMAN_PROMPT.format(context=context, item=normalized_item, city=city)

    response = pplx_client.responses.create(
        model="anthropic/claude-sonnet-4-6",
        instructions=SYSTEM_PROMPT,
        input=prompt,
        max_output_tokens=400,
    )

    raw = response.output_text.strip()

    try:
        result = json.loads(raw)
    except json.JSONDecodeError:
        print(f"[rag] JSON parse error. Raw response: {raw}")
        return {
            "action": "TRASH",
            "reason": "Classification error — defaulting to trash",
            "confidence": "low",
        }

    return {
        "action": result.get("action", "TRASH"),
        "reason": result.get("reason", "No reason provided"),
        "confidence": result.get("confidence", "low"),
    }
