import json
import os
from pathlib import Path
from dotenv import load_dotenv
load_dotenv()

try:
    from pypdf import PdfReader
except ImportError as exc:
    raise ImportError(
        "This script requires pypdf. Install it with: python3 -m pip install pypdf"
    ) from exc

try:
    from mem0 import Memory
except ImportError as exc:
    raise ImportError(
        "This script requires the mem0 package. Install it in your environment or ensure it is available to Python."
    ) from exc


def extract_text_from_pdf(path: Path) -> str:
    reader = PdfReader(str(path))
    pages = []
    for page in reader.pages:
        text = page.extract_text() or ""
        pages.append(text)
    return "\n\n".join(pages).strip()


def load_teaching_rag_files(rag_dir: Path):
    documents = []
    if not rag_dir.exists() or not rag_dir.is_dir():
        raise FileNotFoundError(f"Teaching RAG directory not found: {rag_dir}")

    for path in sorted(rag_dir.iterdir()):
        if path.is_dir():
            continue
        if path.suffix.lower() == ".pdf":
            content = extract_text_from_pdf(path)
        elif path.suffix.lower() in {".txt", ".md", ".json"}:
            content = path.read_text(encoding="utf-8")
        else:
            # Skip unsupported file types for text extraction
            continue

        if content:
            documents.append({
                "source": path.name,
                "content": content,
            })
    return documents


def main():
    this_dir = Path(__file__).resolve().parent
    rag_dir = this_dir / "teaching_rag"

    # Reuse the same vector store configuration as backend/rag.py
    config = {
        "vector_store": {
            "provider": "mongodb",
            "config": {
                "db_name": "mem0-db",
                "collection_name": "mem0-collection",
                "mongo_uri": "mongodb://username:password@localhost:27017",
            },
        }
    }

    os.environ.setdefault("OPENAI_API_KEY", os.getenv("OPENAI_API_KEY", ""))

    memory = Memory.from_config(config)
    documents = load_teaching_rag_files(rag_dir)

    if not documents:
        print(f"No supported files found in {rag_dir}.")
        return

    for doc in documents:
        print(f"Ingesting {doc['source']}...")
        memory.add([
            {
                "role": "user",
                "content": doc["content"],
            }
        ], user_id="teaching_rag", metadata={"source": doc["source"]})

    result = memory.get_all(filters={"user_id": "teaching_rag"})
    if isinstance(result, dict):
        items = result.get("results", [])
    else:
        items = result or []

    if not items:
        print("No vectors were returned after ingestion.")
        return

    first = items[0]
    print("\nFirst stored vector entry:")
    print(json.dumps(first, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
