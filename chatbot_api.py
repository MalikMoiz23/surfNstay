import pandas as pd
import numpy as np
import re
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uuid

# Add rapidfuzz imports with try-except
try:
    from rapidfuzz import process as fuzz_process, fuzz
    FUZZY_OK = True
except ImportError:
    FUZZY_OK = False

# ─────────────────────────────────────────────────────────────────
# HOW TO RUN IN COLAB:
#   !pip install sentence-transformers fastapi uvicorn
#   Upload CSVs to /content/ then run this file
# ─────────────────────────────────────────────────────────────────

# =========================
# Load Dataset
# =========================
df = pd.read_csv("clean_surfNStay_famous_places_dataset_AI_FINAL1.csv")
df.columns = df.columns.str.strip()

df['city']      = df['city'].str.lower()
df['user_type'] = df['user_type'].str.lower()
df['budget']    = df['budget'].str.lower()
df['type']      = df['category'].str.lower()

# Define PLACE_NAMES_L after df is loaded
import os

# Remote URLs for datasets (Google Drive direct download links)
PLACES_URL = "https://drive.google.com/uc?export=download&id=1YyToN_FMc1_4vIC2_HhKPXE9ykqqemy0"
USERS_URL  = "https://drive.google.com/uc?export=download&id=1E3Xr_FwqL3TgrlotDZ1Ng1Wez2iCouoq"

BASE = os.path.dirname(os.path.abspath(__file__))
PLACES_F = os.path.join(BASE, "clean_surfNStay_famous_places_dataset_AI_FINAL1.csv")
USERS_F  = os.path.join(BASE, "user_interaction_accurate.csv")

def load_csv_with_fallback(url: str, local_path: str) -> pd.DataFrame:
    """Attempt to load CSV from a remote URL; fall back to a local file if needed."""
    try:
        print(f"Attempting remote load: {url}")
        return pd.read_csv(url)
    except Exception as e:
        print(f"Remote load failed ({e}); loading local file: {local_path}")
        return pd.read_csv(local_path)

# Load datasets using fallback
df = load_csv_with_fallback(PLACES_URL, PLACES_F)
df.columns = df.columns.str.strip()
df['city'] = df['city'].str.lower()
df['user_type'] = df['user_type'].str.lower()
df['budget'] = df['budget'].str.lower()
df['type'] = df['category'].str.lower()

PLACE_NAMES_L = df['place_name'].str.lower().unique().tolist()


# =========================
# User Interaction Data
# =========================
interactions = load_csv_with_fallback(USERS_URL, USERS_F)
# columns: user_id, place_name, rating
# columns: user_id, place_name, rating

# =========================
# TEXT FEATURES FOR AI
# =========================
df["text_features"] = (
    df["place_name"] + " " +
    df["type"]       + " " +
    df["city"]       + " " +
    df["user_type"]  + " " +
    df["budget"]
)

# =========================
# SBERT MODEL
# =========================
print("🔄 Loading SBERT model...")
sbert = SentenceTransformer("all-MiniLM-L6-v2")
print("🔄 Creating embeddings...")
embeddings   = sbert.encode(df["text_features"].tolist(), show_progress_bar=True)
content_sim  = cosine_similarity(embeddings)

# =========================
# Collaborative Filtering
# =========================
user_item = interactions.pivot_table(
    index="user_id", columns="place_id", values="rating"
).fillna(0)

user_sim   = cosine_similarity(user_item)
user_index = {u: i for i, u in enumerate(user_item.index)}

# =========================
# GOOGLE MAPS LINK HELPERS
# =========================
def maps_link(lat, lon):
    """Opens exact location on Google Maps."""
    return f"https://www.google.com/maps/search/?api=1&query={lat},{lon}"

def directions_link(lat, lon, name):
    """
    Get directions TO this place.
    Traveler clicks the link → Google Maps opens and asks for their
    current location → shows full route + distance automatically.
    """
    encoded = str(name).replace(" ", "+")
    return f"https://www.google.com/maps/dir/?api=1&destination={lat},{lon}&destination_place_name={encoded}"

# =========================
# NLP FUNCTIONS
# =========================
def detect_intent(text):
    t = text.lower()
    if any(re.search(r'\b' + w + r'\b', t) for w in ["hi","hello","hey","assalam","salam"]):
        return "greeting"
    if any(w in t for w in ["thank","thanks","shukriya"]):
        return "thanks"
    if any(w in t for w in ["bye","exit","quit","goodbye"]):
        return "exit"
    if any(w in t for w in ["more","show more","next"]):
        return "more"
    detail_keywords = ["tell me about", "details", "detail", "information", "info", "about", "describe"]
    if any(k in t for k in detail_keywords):
        return "place_detail"
    rec_kw = ["place","places","visit","go","recommend","suitable","best",
              "mall","malls","park","parks","tourist","lake","mountain",
              "hiking","trail","waterfall","attraction","show","find","suggest"]
    if any(w in t for w in rec_kw):
        return "recommendation"
    return "unknown"

def extract_city(text):
    t = text.lower()
    for city in sorted(df['city'].unique(), key=len, reverse=True):
        if city in t:
            return city
    return None

type_synonyms = {
    "shopping mall": "shopping mall",
    "mall": "shopping mall",
    "malls": "shopping mall",
    "shopping": "shopping mall",
    "park": "park",
    "parks": "park",
    "garden": "park",
    "hiking": "hiking/trail",
    "trek": "hiking/trail",
    "trail": "hiking/trail",
    "lake": "lake",
    "waterfall": "waterfall",
    "mountain": "mountain",
    "tourist attraction": "tourist attraction",
    "tourist place": "tourist attraction",
    "tourist places": "tourist attraction",
    "tourist": "tourist attraction",
    "attraction": "tourist attraction",
    "historical": "tourist attraction",
}

def extract_type(text):
    t = text.lower()
    for k in sorted(type_synonyms, key=len, reverse=True):
        if k in t:
            return type_synonyms[k]
    return None

def extract_user_type(text):
    t = text.lower()
    for u in ["family","friends","couple","solo"]:
        if re.search(r'\b' + u + r'\b', t):
            return u
    return None

def extract_budget(text):
    t = text.lower()
    for b in ["high","luxury","expensive","medium","moderate","low","cheap","affordable","free"]:
        if re.search(r'\b' + b + r'\b', t):
            if b in ["high","luxury","expensive"]:
                return "high"
            if b in ["medium","moderate"]:
                return "medium"
            return "low"
    return None

def extract_place_name(text):
    text = text.lower()
    for place in PLACE_NAMES_L:
        if place in text:
            return place
    if FUZZY_OK:
        result = fuzz_process.extractOne(
            text,
            PLACE_NAMES_L,
            scorer=fuzz.partial_ratio,
            score_cutoff=75
        )
        if result:
            return result[0]
    return None

# =========================
# HYBRID RECOMMENDER
# =========================
def hybrid_recommend(user_id, city=None, user_type=None, budget=None,
                     place_type=None, exclude_ids=None, top_n=3, alpha=0.6):
    exclude_ids = exclude_ids or []
    data = df[df["rating"] >= 4.4].copy()
    if city:
        data = data[data['city'] == city]
    if user_type:
        data = data[data['user_type'].str.contains(user_type, na=False)]
    if budget:
        data = data[data['budget'] == budget]
    if place_type:
        data = data[data['type'].str.contains(place_type, na=False)]
    if exclude_ids:
        data = data[~data['place_id'].isin(exclude_ids)]
    # Relax budget
    if data.empty and budget:
        data = df[df["rating"] >= 4.4].copy()
        if city:
            data = data[data['city'] == city]
        if user_type:
            data = data[data['user_type'].str.contains(user_type, na=False)]
        if place_type:
            data = data[data['type'].str.contains(place_type, na=False)]
        if exclude_ids:
            data = data[~data['place_id'].isin(exclude_ids)]
    # Relax category
    if data.empty and place_type:
        data = df[df["rating"] >= 4.4].copy()
        if city:
            data = data[data['city'] == city]
        if user_type:
            data = data[data['user_type'].str.contains(user_type, na=False)]
        if exclude_ids:
            data = data[~data['place_id'].isin(exclude_ids)]
    if data.empty:
        return pd.DataFrame()
    idxs = data.index.tolist()
    content_scores = content_sim[idxs][:, idxs].mean(axis=1)
    if user_id not in user_index:
        final_scores = content_scores
    else:
        uidx = user_index[user_id]
        cf_scores = []
        for pid in data["place_id"]:
            if pid in user_item.columns:
                ratings = user_item[pid].values
                score = np.dot(user_sim[uidx], ratings) / (np.sum(np.abs(user_sim[uidx])) + 1e-6)
            else:
                score = 0
            cf_scores.append(score)
        cf_scores = np.array(cf_scores)
        final_scores = alpha * content_scores + (1 - alpha) * cf_scores
    data = data.copy()
    data["score"] = final_scores
    data = data.sort_values(["score", "rating"], ascending=[False, False])
    return data.drop_duplicates("place_name").head(top_n)

# =========================
# RESPONSE FORMATTERS
# =========================
DIVIDER = "─" * 55

def format_place_detail(row):
    lat = row["latitude"]
    lon = row["longitude"]
    name = row["place_name"]
    return f"""
📍 {name}

⭐ Rating          : {row['rating']}/5.0
🏷️ Category        : {row['category']}
👥 Best For        : {row['user_type']}
💰 Budget          : {row['budget']}
🎯 User Preferences: {row['user_preferences']}
🕐 Best Time       : {row['best_time_to_visit']}
🌤️ Season          : {row['seasonal_suitability']}
📍 City            : {row['city']}

🗺️ Google Map:
{maps_link(lat, lon)}

🧭 Directions:
{directions_link(lat, lon, name)}"""

def format_places(results, rank_start=1):
    lines = []
    for i, (_, r) in enumerate(results.iterrows()):
        bi = {"low":"💚","medium":"💛","high":"💰"}.get(r["budget"].lower(), "💰")
        stars = "⭐" * int(round(r["rating"]))
        lines.append(
            f"{rank_start+i}. 📍 {r['place_name']}\n"
            f"   Category: {r['category']}\n"
            f"   Rating: {r['rating']}/5.0 {stars}\n"
            f"   Budget: {bi} {r['budget'].title()}\n"
            f"   Best For: {r['user_type'].title()}\n"
            f"   Best Time: {r['best_time_to_visit']}\n"
            f"   🗺️ View on Map: {maps_link(r['latitude'], r['longitude'])}\n"
            f"   🧭 Directions: {directions_link(r['latitude'], r['longitude'], r['place_name'])}"
        )
    return "\n\n".join(lines)

# =========================
# FastAPI App
# =========================
app = FastAPI(title="SurfNStay AI Chatbot")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

class ChatRequest(BaseModel):
    message: str
    session_id: str = ""

class ChatResponse(BaseModel):
    reply: str
    session_id: str

# Simple in‑memory session store
sessions = {}

class SessionState:
    def __init__(self):
        self.city = None
        self.user_type = None
        self.budget = None
        self.place_type = None
        self.shown_ids = []
        self.active = False
        self.user_id = "U1"
    def new_search(self, city, user_type, budget, place_type):
        self.city = city
        self.user_type = user_type
        self.budget = budget
        self.place_type = place_type
        self.shown_ids = []
        self.active = True
    def merge_search(self, city, user_type, budget, place_type):
        if not self.active:
            self.city = city
        else:
            if not city:
                city = self.city
        self.city = city
        self.user_type = user_type
        self.budget = budget
        self.place_type = place_type
        self.shown_ids = []
        self.active = True

@app.get("/")
def root():
    return {"status": "SurfNStay Chatbot API running ✅"}

@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    sid = req.session_id or str(uuid.uuid4())
    if sid not in sessions:
        sessions[sid] = SessionState()
    session = sessions[sid]
    raw = req.message.strip()
    fixed = raw  # spelling correction can be added if desired
    intent = detect_intent(fixed)
    reply = ""
    if intent == "exit":
        sessions.pop(sid, None)
        reply = "Khuda Hafiz! 🌍 Safe travels! ✈️"
    elif intent == "greeting":
        reply = (
            "Hello! 👋 Welcome to SurfNStay AI Assistant!\n"
            "Ask me for recommendations, place details, or say 'more' to see additional results."
        )
    elif intent == "thanks":
        reply = "You’re welcome 😊 Happy to help!"
    elif intent == "more":
        if not session.active:
            reply = "Please start a search first."
        else:
            results = hybrid_recommend(
                user_id=session.user_id,
                city=session.city,
                user_type=session.user_type,
                budget=session.budget,
                place_type=session.place_type,
                exclude_ids=session.shown_ids,
                top_n=3,
            )
            if results.empty:
                reply = "✅ No more places found. Try a new query."
                session.active = False
            else:
                start = len(session.shown_ids) + 1
                session.shown_ids += results["place_id"].tolist()
                reply = f"More recommendations:\n{format_places(results, start)}"
    elif intent == "place_detail":
        place_query = extract_place_name(raw)
        if not place_query:
            reply = "I couldn't locate that place."
        else:
            place_data = df[df["place_name"].str.lower() == place_query]
            if place_data.empty:
                reply = "Place not found in our database."
            else:
                row = place_data.iloc[0]
                reply = format_place_detail(row)
    elif intent == "recommendation":
        city = extract_city(raw)
        user_type = extract_user_type(raw)
        budget = extract_budget(raw)
        place_type = extract_type(raw)
        session.new_search(city, user_type, budget, place_type)
        results = hybrid_recommend(
            user_id=session.user_id,
            city=city,
            user_type=user_type,
            budget=budget,
            place_type=place_type,
            top_n=3,
        )
        if results.empty:
            reply = "No matching places found. Try adjusting your criteria."
            session.active = False
        else:
            session.shown_ids = results["place_id"].tolist()
            reply = f"Top recommendations:\n{format_places(results, 1)}"
    else:
        reply = (
            "I didn't understand. Try queries like:\n"
            "• recommend parks in Islamabad for families\n"
            "• details about Murree\n"
            "• more"
        )
    return ChatResponse(reply=reply, session_id=sid)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("chatbot_api:app", host="0.0.0.0", port=8000, reload=True)
