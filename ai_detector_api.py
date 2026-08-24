"""
SurfNStay – AI Image Detector Service
--------------------------------------
Runs on port 7861 (so it doesn't conflict with the chatbot on 8000).

Accepts a multipart/form-data POST with a field named "file".
Returns JSON:
  {
    "is_ai": true | false,
    "ai_score": 0.0 – 1.0,    // probability that the image is AI-generated
    "real_score": 0.0 – 1.0,
    "label": "AI-Generated" | "Real"
  }

Run with:
  python ai_detector_api.py
  – or –
  uvicorn ai_detector_api:app --host 0.0.0.0 --port 7861
"""

import io
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from PIL import Image
from transformers import pipeline
import torch

# ── Load the model once at startup ──────────────────────────────────────────
print("Loading model Organika/sdxl-detector …")
_pipe = pipeline(
    "image-classification",
    model="Organika/sdxl-detector",
    device=0 if torch.cuda.is_available() else -1,
)
print("Model loaded successfully!")

# ── FastAPI app ──────────────────────────────────────────────────────────────
app = FastAPI(title="SurfNStay AI Image Detector")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class DetectionResult(BaseModel):
    is_ai: bool
    ai_score: float
    real_score: float
    label: str


@app.get("/")
def root():
    return {"status": "AI Image Detector API running ✅"}


@app.post("/detect", response_model=DetectionResult)
async def detect(file: UploadFile = File(...)):
    """
    Upload an image file and receive an AI-detection verdict.
    If ai_score > 0.50 → is_ai = True.
    """
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be an image.")

    try:
        contents = await file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read image: {e}")

    # Run classification
    results = _pipe(image)
    print(f"DEBUG: Raw model results = {results}")

    # Build a score dict regardless of label order
    scores: dict[str, float] = {r["label"]: r["score"] for r in results}

    # The model uses labels "artificial" / "human" (case-insensitive check)
    ai_score = 0.0
    real_score = 0.0
    for label, score in scores.items():
        lower = label.lower()
        if lower in ("artificial", "ai", "ai-generated", "fake", "sdxl"):
            ai_score = score
        elif lower in ("real", "natural", "authentic", "human"):
            real_score = score

    # Fallback: if we couldn't map labels, treat the highest-score label
    if ai_score == 0.0 and real_score == 0.0 and results:
        # Sort by score descending; first entry treated as "AI" if its label
        # isn't something we recognise as "real"
        sorted_results = sorted(results, key=lambda x: x["score"], reverse=True)
        top = sorted_results[0]
        if any(w in top["label"].lower() for w in ("real", "natural", "human", "authentic")):
            real_score = top["score"]
            ai_score = 1.0 - top["score"]
        else:
            ai_score = top["score"]
            real_score = 1.0 - top["score"]

    is_ai = ai_score > 0.70
    print(f"DEBUG: AI Score = {ai_score:.4f}, Real Score = {real_score:.4f} -> Verdict: {'AI' if is_ai else 'Real'}")

    return DetectionResult(
        is_ai=is_ai,
        ai_score=round(ai_score, 4),
        real_score=round(real_score, 4),
        label="AI-Generated" if is_ai else "Real",
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("ai_detector_api:app", host="0.0.0.0", port=7861, reload=False)
