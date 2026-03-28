import chromadb, os
from dotenv import load_dotenv
from langchain_community.vectorstores import Chroma
from langchain_huggingface import HuggingFaceEmbeddings

load_dotenv()
embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
chroma_client = chromadb.PersistentClient(
    path=os.getenv("CHROMA_PERSIST_DIR", "./chroma_db")
)
vectorstore = Chroma(
    client=chroma_client,
    collection_name="mrf_docs",
    embedding_function=embeddings
)

tests = [
    ("black plastic container", "seattle"),
    ("plastic bag",             "nyc"),
    ("garden hose",             "chicago"),
    ("glass bottle",            "la"),
]

for item, city in tests:
    print(f"\n{'='*50}")
    print(f"{item} | {city}")
    results = vectorstore.similarity_search(
        f"{item} {city} MRF recycling", k=2, filter={"city": city}
    )
    for r in results:
        print(r.page_content[:300])
        print("---")
