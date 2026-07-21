# Fix: Vector Dimension Mismatch (3072 vs 768)

## Completed Steps

- [x] Root cause analysis: Gemini `gemini-embedding-001` outputs **3072-dim** vectors, but FAISS index was built with **768-dim**
- [x] Plan confirmed with user

## TODO

### Step 1: Fix `backend/app/services/embeddings.py`
- [x] Fix misleading comment (768 → 3072)
- [x] Add `get_actual_embedding_dimension()` method to auto-detect real dimension
- [x] Better error handling

### Step 2: Fix `backend/app/services/vectorstore.py`
- [x] Add auto-rebuild logic when dimension mismatch is detected during `add()`
- [x] Add `rebuild()` method
- [x] Improve logging for dimension issues

### Step 3: Fix `backend/app/services/ingestion.py`
- [x] Handle dimension mismatch gracefully — auto-rebuild vectorstore and retry
- [x] Add cleanup of stale FAISS index on dimension mismatch

### Step 4: Delete stale FAISS index files
- [x] No stale files locally (only `.gitkeep` present)
- [ ] On Render: delete `data/vectorstore/index.faiss` and `data/vectorstore/meta.pkl` before restarting

### Step 5: Verify and test (on Render deployment)
- [ ] Restart backend server
- [ ] Upload a document and confirm ingestion succeeds
- [ ] Verify AI copilot finds documents and generates reports

