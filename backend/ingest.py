import glob
import os

from dotenv import load_dotenv
from langchain_community.document_loaders import TextLoader
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

load_dotenv()

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
CHROMA_PERSIST_DIR = os.getenv("CHROMA_PERSIST_DIR", "./chroma_db")


def ingest():
    # Lazy import so chromadb isn't loaded at module level
    import chromadb
    from langchain_community.vectorstores import Chroma

    splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
    embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")

    all_chunks = []
    for filepath in sorted(glob.glob(os.path.join(DATA_DIR, "*.txt"))):
        filename = os.path.basename(filepath)
        city = filename.replace("_mrf.txt", "")

        loader = TextLoader(filepath, encoding="utf-8")
        docs = loader.load()

        chunks = splitter.split_documents(docs)
        for chunk in chunks:
            chunk.metadata["city"] = city
        all_chunks.extend(chunks)
        print(f"  {filename}: {len(chunks)} chunks (city={city})")

    client = chromadb.PersistentClient(path=CHROMA_PERSIST_DIR)
    vectorstore = Chroma.from_documents(
        documents=all_chunks,
        embedding=embeddings,
        client=client,
        collection_name="mrf_docs",
    )

    print(f"\nTotal chunks ingested: {len(all_chunks)}")
    print(f"Persisted to: {CHROMA_PERSIST_DIR}")


if __name__ == "__main__":
    ingest()
