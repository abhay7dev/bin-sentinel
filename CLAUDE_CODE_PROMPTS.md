# BIN SENTINEL — Claude Code Prompt Sequence
# Copy-paste these prompts into Claude Code in order.
# Wait for Claude Code to finish each prompt before pasting the next one.

---

## BEFORE YOU START — ONE-TIME SETUP

### 1. Claude Code settings (optional but useful)
Create `.claude/settings.json` in the repo root to allow Claude Code to run shell commands
without prompting you for permission every time:

```json
{
  "permissions": {
    "allow": [
      "Bash(pip install *)",
      "Bash(python *)",
      "Bash(uvicorn *)",
      "Bash(npm *)",
      "Bash(git *)"
    ]
  }
}
```

### 2. GitHub MCP server (optional, saves time)
Claude Code can push commits to GitHub directly if you install the GitHub MCP server.
Run this once: `claude mcp add github` and follow the prompts. Then Claude Code can
run `git add`, `git commit`, and `git push` on your behalf without you switching windows.

### 3. Files that must exist before starting
- `CLAUDE.md` in repo root ← Claude Code reads this automatically every session
- `backend/data/seattle_mrf.txt`
- `backend/data/nyc_mrf.txt`
- `backend/data/la_mrf.txt`
- `backend/data/chicago_mrf.txt`

### 4. Start Claude Code
```bash
cd your-repo-root
claude
```

---

## PROMPT 1 — Environment, Repo Scaffold & Backend Skeleton
*~10 min*

```
Read CLAUDE.md in full before writing any code.

First, set up the Python virtual environment and install dependencies:

1. Create backend/requirements.txt with exactly these packages:
   fastapi
   uvicorn[standard]
   python-multipart
   langchain==1.2.10
   langchain-community
   langchain-openai
   langchain-huggingface
   langchain-text-splitters
   sentence-transformers
   chromadb==1.5.2
   google-cloud-vision
   sqlmodel
   python-dotenv

2. Run these shell commands to create and activate the venv and install deps:
   cd backend
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   cd ..

3. Create backend/.env.example with these keys and empty values:
   PERPLEXITY_API_KEY=
   GOOGLE_APPLICATION_CREDENTIALS=./gcp-key.json
   CHROMA_PERSIST_DIR=./chroma_db
   DATABASE_URL=sqlite:///./bin_sentinel.db

4. Create backend/.gitignore that ignores:
   .env
   gcp-key.json
   venv/
   chroma_db/
   __pycache__/
   *.pyc
   bin_sentinel.db

5. Create backend/models.py with a SQLModel Scan table:
   id (int, primary key), item (str), action (str), reason (str),
   confidence (str), city (str), timestamp (datetime, default=utcnow)

6. Create backend/database.py that creates the SQLite engine from DATABASE_URL env var
   and exports a get_session dependency and a create_db_and_tables() function.

7. Create backend/main.py with a FastAPI app that:
   - Calls create_db_and_tables() on startup
   - Has CORSMiddleware with allow_origins=["*"]
   - POST /scan — accepts image (UploadFile) and city (Form, default "seattle")
     Returns a hardcoded response matching the API contract in CLAUDE.md for now
   - GET /history — returns { "scans": [] } for now
   - GET /health — returns { "status": "ok" }

8. Create a root-level .gitignore that also ignores backend/venv/ and backend/chroma_db/

9. Create README.md with a one-paragraph project description and quickstart:
   cd backend && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt

Do not write vision.py, rag.py, or ingest.py yet.
```

---

## PROMPT 2 — Vision Layer
*~10 min*

```
Read CLAUDE.md before starting. The venv is at backend/venv/ — all python commands
should run with the venv active.

Build the vision layer:

1. Create backend/vision_normalize.py with the complete LABEL_MAP and normalize_labels
   function exactly as written in CLAUDE.md. Do not modify the map.

2. Create backend/vision.py with an identify_object(image_bytes: bytes) -> dict function:
   - Creates a google.cloud.vision.ImageAnnotatorClient
   - Calls label_detection on the image bytes
   - Calls object_localization on the image bytes
   - Returns:
     {
       "label": str,          # top label from label_detection
       "all_labels": list,    # top 5 labels
       "objects": list,       # object_localization names
       "normalized": str      # normalize_labels() output from top 4 labels
     }
   - If Vision returns 0 labels, returns { "label": "unknown item", "all_labels": [],
     "objects": [], "normalized": "unknown item" }

3. Update main.py /scan to:
   - Read the image bytes from the UploadFile
   - Call identify_object(image_bytes)
   - Print the normalized label to console (for debugging)
   - Still return the hardcoded response for now

Do not touch rag.py yet.
```

---

## PROMPT 3 — RAG Pipeline & ChromaDB Ingestion
*~15 min*

```
Read CLAUDE.md before starting.

Build the RAG pipeline. Use the venv at backend/venv/.

1. Create backend/ingest.py:
   - Load all .txt files from backend/data/ using TextLoader
   - Extract city name from filename (e.g. "seattle_mrf.txt" → city = "seattle")
   - Add {"city": city_name} as metadata to every document chunk
   - Split with RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
   - Create embeddings with HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
     from langchain_huggingface
   - Persist to ChromaDB at the CHROMA_PERSIST_DIR env var path
   - Print total chunk count when done
   Run this script now to populate the database.

2. Create backend/rag.py:
   - Load ChromaDB vectorstore using HuggingFaceEmbeddings (same model as ingestion)
   - Define get_facility_verdict(normalized_item: str, city: str) -> dict
   - Query: f"{normalized_item} {city} MRF recycling"
   - Retrieve k=4 docs via similarity_search
   - Create ChatOpenAI with:
       model="anthropic/claude-sonnet-4-5"
       openai_api_key=os.getenv("PERPLEXITY_API_KEY")
       openai_api_base="https://api.perplexity.ai"
       temperature=0
       max_tokens=400
   - Use the EXACT system prompt and human prompt from CLAUDE.md
   - Use JsonOutputParser at the end of the chain
   - On JSON parse failure, return:
     { "action": "TRASH", "reason": "Classification error — defaulting to trash", "confidence": "low" }

3. Wire main.py /scan end-to-end:
   - identify_object(image_bytes) → get normalized label
   - get_facility_verdict(normalized_label, city) → verdict
   - Save scan to SQLite using the Scan model
   - Return the full API contract shape from CLAUDE.md

4. Wire /history to return last 10 Scan records from SQLite, ordered by timestamp desc.
```

---

## PROMPT 4 — Hardening & Test Endpoint
*~10 min*

```
Read CLAUDE.md before starting.

1. Add input validation to /scan in main.py:
   - Missing image → 422: { "error": "No image provided" }
   - City not in ["seattle", "nyc", "la", "chicago"] → 422: { "error": "Invalid city" }
   - Non-image content_type → 422: { "error": "File must be an image" }

2. Add GET /scan/test endpoint that:
   - Takes a query param: item (str, default "black plastic container") and city (str, default "seattle")
   - Calls get_facility_verdict(item, city) directly — no image needed
   - Returns the full verdict JSON
   This lets you test RAG + Claude without uploading an image.

3. Create backend/Dockerfile:
   FROM python:3.11-slim
   WORKDIR /app
   COPY requirements.txt .
   RUN pip install --no-cache-dir -r requirements.txt
   COPY . .
   EXPOSE 8000
   CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

   Note: The Dockerfile does NOT use the venv — Railway builds in its own clean environment.
   The venv is only for local development.

4. Add a startup log to main.py that prints:
   - The CHROMA_PERSIST_DIR path being used
   - Confirmation that DB tables were created

5. Test the /scan/test endpoint locally:
   source backend/venv/bin/activate
   cd backend && uvicorn main:app --reload
   curl "http://localhost:8000/scan/test?item=black+plastic+container&city=seattle"
   The response action must be TRASH and the reason must mention NIR and carbon-black.
```

---

## PROMPT 5 — Frontend
*~15 min*

```
Read CLAUDE.md before starting.

Build the React frontend in the /frontend directory. The backend API URL comes from
VITE_API_URL env var, defaulting to http://localhost:8000.

1. Scaffold with Vite:
   npm create vite@latest frontend -- --template react
   cd frontend && npm install
   npm install axios
   npm install -D tailwindcss postcss autoprefixer
   npx tailwindcss init -p
   Configure tailwind.config.js to scan ./src/**/*.{js,jsx}

2. Create frontend/.env.example:
   VITE_API_URL=http://localhost:8000

3. Create frontend/src/CitySelector.jsx:
   Dropdown with 4 options: Seattle (seattle), NYC (nyc), Los Angeles (la), Chicago (chicago)
   Props: value, onChange

4. Create frontend/src/ResultCard.jsx:
   Props: item, action, reason, confidence, city
   - RECYCLE → green styling
   - TRASH → red styling
   - COMPOST → amber styling
   No fancy styling yet — just correct colors and readable layout.

5. Create frontend/src/Scanner.jsx:
   - file input: accept="image/*" capture="environment" (CRITICAL for mobile rear camera)
   - Visible scan button that triggers the file input
   - CitySelector dropdown (default "seattle")
   - On file select: POST to ${VITE_API_URL}/scan as multipart/form-data
     form.append('image', file)   ← exact field name
     form.append('city', city)    ← exact field name
   - Loading state: "Checking facility specs..."
   - On success: show ResultCard
   - On error: show plain error text

6. Create frontend/src/History.jsx:
   - Calls GET /history on mount
   - Renders last 10 scans as a simple list: item name, action (colored), city, time

7. Wire in frontend/src/App.jsx: Scanner on top, History below.

8. Create frontend/vercel.json:
   { "rewrites": [{ "source": "/(.*)", "destination": "/" }] }

9. Create frontend/.gitignore that ignores node_modules/ and dist/

Test that the app loads at localhost:5173 and that a scan attempt hits the backend.
```

---

## PROMPT 6 — Final Checks Before Manual Testing
*~5 min*

```
Before we do manual end-to-end testing on a real phone, make these final checks:

1. Confirm main.py CORS allows all origins (allow_origins=["*"]) — already set but verify.

2. In frontend/src/Scanner.jsx, verify the FormData field names are EXACTLY:
   form.append('image', file)
   form.append('city', selectedCity)
   These must match the FastAPI parameter names image and city.

3. In main.py, confirm the /scan endpoint signature is:
   async def scan_item(image: UploadFile = File(...), city: str = Form("seattle"))

4. Add frontend package.json scripts if not already present:
   "dev": "vite", "build": "vite build", "preview": "vite preview"

5. Create backend/README_DEPLOY.md with Railway deploy steps:
   - Push to GitHub
   - Create new Railway project from GitHub repo
   - Set root directory to /backend
   - Set environment variables: PERPLEXITY_API_KEY, GOOGLE_APPLICATION_CREDENTIALS,
     CHROMA_PERSIST_DIR, DATABASE_URL
   - Note: gcp-key.json must be added as a Railway secret file — do not commit it
   - The ingest.py script must be run once after deploy to populate ChromaDB

6. Print a complete list of every file created so we can verify nothing is missing.
```

---

## PROMPT 7 — UX Polish
### ⚠️ DO NOT RUN until all 5 demo items return correct verdicts on a real phone

```
Read CLAUDE.md. Core pipeline is verified. Now polish the UI.

Make it look like a real product:

1. ResultCard.jsx: Large, bold action text with color-filled card background.
   Clear, readable reason text. Small icon per action: ♻️ RECYCLE, 🚫 TRASH, 🌱 COMPOST.

2. Scanner.jsx: Full-width scan button on mobile. Show a preview of the scanned image
   while loading. Smooth fade-in on result reveal. Clean layout.

3. History.jsx: Scan cards in a scrollable list, small colored action badge per scan.

4. App.jsx: Header with "Bin Sentinel" and tagline "Your city's actual recycling rules."

5. Verify everything looks good at 390px width (iPhone 14 viewport).

Do not change any backend files. Do not change API call logic or field names.
```

---

## PROMPT 8 — Stretch Features
### Only if core is solid and time remains

```
Add these in order of demo impact:

1. After a TRASH verdict, add a one-sentence "why this matters" below the reason:
   - Black plastic → "NIR sorters use infrared light to identify polymers. Carbon-black absorbs all IR, making the item invisible to sorting equipment."
   - Plastic bag → "Flexible plastics wrap around conveyor augers, triggering shutdowns that cost ~$5,000/hour in downtime."
   - Garden hose → "Hoses are among the most destructive tanglers — they wrap around rollers and can require cutting equipment to remove."
   Hard-code these by action + item type. No new API calls needed.

2. Scan count badge in the App header showing total scans this session.

3. "Try scanning one of these" section on the landing screen listing 3 suggested items.

4. Share button on ResultCard: copies to clipboard:
   "Bin Sentinel: [item] → [ACTION] in [city]. [reason]"

Do not add more cities, PWA features, or streaming — not worth the time.
```

---

## TROUBLESHOOTING

**"ModuleNotFoundError" when running backend**
→ venv is not activated.
→ Run: `source backend/venv/bin/activate` then retry.

**"ChromaDB returns 0 results"**
→ ingest.py hasn't been run yet, or CHROMA_PERSIST_DIR is wrong.
→ Run: `cd backend && source venv/bin/activate && python ingest.py`

**"Black plastic returns RECYCLE"**
→ Add explicit rule to the system prompt in rag.py:
  "When the item is black plastic, the action MUST be TRASH."

**"Claude returns malformed JSON / not JSON"**
→ The system prompt must end with: "No preamble. No markdown. No text outside the JSON."
→ Confirm JsonOutputParser is the last step in the LangChain chain.

**"Perplexity API returns 401"**
→ PERPLEXITY_API_KEY is not set in backend/.env
→ Confirm the key is the Perplexity API key, not an Anthropic key.

**"CORS error in browser"**
→ Confirm CORSMiddleware in main.py has allow_origins=["*"]

**"Camera doesn't open on iPhone"**
→ File input must have BOTH: accept="image/*" AND capture="environment"
→ App must be served over HTTPS. Vercel deploy is HTTPS automatically.
   localhost works on desktop. For mobile testing of local dev, use ngrok.

**"sentence-transformers download fails"**
→ First run downloads ~90MB. Needs internet access.
→ After first run, the model is cached locally in ~/.cache/huggingface/

**"Railway deploy fails — can't find ingest.py output"**
→ ChromaDB data is not persisted between Railway deployments by default.
→ Solution: run ingest.py as a Railway one-off job after first deploy,
  or mount a Railway volume at the CHROMA_PERSIST_DIR path.
→ For the hackathon, the simplest fix: run ingest.py locally, commit the
  chroma_db/ folder to the repo (exception to the gitignore rule — just for demo day).
```

---

## API COST REFERENCE

| Service | Cost |
|---|---|
| Google Cloud Vision | ~$1.50 / 1,000 images (first 1,000/month free) |
| Perplexity (claude-sonnet-4-5) | $3 input / $15 output per 1M tokens (~$0.01-0.02/scan) |
| sentence-transformers embeddings | Free — runs locally |
| Full demo day estimate | Under $5 total |
