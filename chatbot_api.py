"""
SurfNStay AI Chatbot – FastAPI Backend
======================================
Run with:   uvicorn chatbot_api:app --host 0.0.0.0 --port 8000 --reload

Place this file in the SAME folder as:
  - clean_surfNStay_famous_places_dataset_AI_FINAL1.csv
  - user_interaction_accurate.csv
"""

import os, re, uuid
import pandas as pd
import numpy as np
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sklearn.metrics.pairwise import cosine_similarity

try:
    from rapidfuzz import process as fuzz_process, fuzz
    FUZZY_OK = True
except ImportError:
    FUZZY_OK = False

try:
    from sentence_transformers import SentenceTransformer
    SBERT_OK = True
except ImportError:
    SBERT_OK = False
    from sklearn.feature_extraction.text import TfidfVectorizer

# ─────────────────────────────────────────────────────────────────
#  FILE PATHS
# ─────────────────────────────────────────────────────────────────
BASE     = os.path.dirname(os.path.abspath(__file__))
PLACES_F = os.path.join(BASE, "clean_surfNStay_famous_places_dataset_AI_FINAL1.csv")
USERS_F  = os.path.join(BASE, "user_interaction_accurate.csv")

# ─────────────────────────────────────────────────────────────────
#  LOAD DATA
# ─────────────────────────────────────────────────────────────────
df = pd.read_csv(PLACES_F)
df.columns = df.columns.str.strip()
for col in ["city","budget","category","user_type","user_preferences","seasonal_suitability"]:
    df[col] = df[col].astype(str).str.strip()
df["city_l"]     = df["city"].str.lower()
df["budget_l"]   = df["budget"].str.lower()
df["category_l"] = df["category"].str.lower()
df["utype_l"]    = df["user_type"].str.lower()

interactions = pd.read_csv(USERS_F)

df["text_features"] = (
    df["place_name"] + " " + df["category"] + " " + df["city"] + " " +
    df["user_type"] + " " + df["budget"] + " " + df["user_preferences"] + " " +
    df["seasonal_suitability"]
)

# ─────────────────────────────────────────────────────────────────
#  EMBEDDINGS
# ─────────────────────────────────────────────────────────────────
if SBERT_OK:
    print("Loading SBERT...")
    sbert       = SentenceTransformer("all-MiniLM-L6-v2")
    embeddings  = sbert.encode(df["text_features"].tolist(), show_progress_bar=True, batch_size=64)
    content_sim = cosine_similarity(embeddings)
    print("SBERT ready.")
else:
    _tfidf      = TfidfVectorizer(stop_words="english")
    _mat        = _tfidf.fit_transform(df["text_features"])
    content_sim = cosine_similarity(_mat)

# ─────────────────────────────────────────────────────────────────
#  COLLABORATIVE FILTERING
# ─────────────────────────────────────────────────────────────────
user_item  = interactions.pivot_table(index="user_id", columns="place_id", values="rating").fillna(0)
user_sim   = cosine_similarity(user_item)
user_index = {u: i for i, u in enumerate(user_item.index)}

W_RATING  = 0.60
W_CONTENT = 0.25
W_CF      = 0.15

# ─────────────────────────────────────────────────────────────────
#  NLU
# ─────────────────────────────────────────────────────────────────
KNOWN_CITIES = sorted(df["city_l"].unique().tolist())

CATEGORY_MAP = {
    "shopping mall":"Shopping Mall","mall":"Shopping Mall","malls":"Shopping Mall",
    "shopping":"Shopping Mall","shop":"Shopping Mall","shops":"Shopping Mall",
    "park":"Park","parks":"Park","garden":"Park","gardens":"Park",
    "hiking":"Hiking/Trail","hike":"Hiking/Trail","trek":"Hiking/Trail",
    "trail":"Hiking/Trail","trails":"Hiking/Trail","trekking":"Hiking/Trail",
    "lake":"Lake","lakes":"Lake","waterfall":"Waterfall","waterfalls":"Waterfall",
    "mountain":"Mountain","mountains":"Mountain",
    "tourist attraction":"Tourist Attraction","attraction":"Tourist Attraction",
    "historical":"Tourist Attraction","monument":"Tourist Attraction",
    "fort":"Tourist Attraction","shrine":"Tourist Attraction",
    "museum":"Tourist Attraction","tourist":"Tourist Attraction",
}

UTYPE_MAP = {
    "family":"family","families":"family","kids":"family","children":"family","parents":"family",
    "friends":"friends","group":"friends","buddy":"friends","college":"friends","yaar":"friends",
    "couple":"couple","romantic":"couple","honeymoon":"couple","partner":"couple",
    "wife":"couple","husband":"couple","adventure":"adventure","solo":"friends",
}

BUDGET_MAP = {
    "high":"high","luxury":"high","expensive":"high","premium":"high","lavish":"high",
    "medium":"medium","moderate":"medium","mid":"medium","normal":"medium",
    "low":"low","cheap":"low","affordable":"low","free":"low","inexpensive":"low",
}

SPELL_MAP = {
    "islamabd":"islamabad","islambad":"islamabad","lahroe":"lahore","lahor":"lahore",
    "karachhi":"karachi","krachi":"karachi","murre":"murree","murrree":"murree",
    "swaat":"swat","sawt":"swat","hunnza":"hunza","hunzaa":"hunza",
    "skarduu":"skardu","skadu":"skardu","abottabad":"abbottabad","abbotabad":"abbottabad",
    "peshwar":"peshawar","queta":"quetta","kasmir":"kashmir",
    "famly":"family","faimly":"family","famliy":"family","frends":"friends",
    "freind":"friends","frnd":"friends","hikin":"hiking","hikng":"hiking",
    "shoping":"shopping","shoppping":"shopping","toursit":"tourist","tourest":"tourist",
    "atraction":"attraction","attarction":"attraction","buget":"budget","budjet":"budget",
    "romantik":"romantic","romntaic":"romantic","prak":"park","advnture":"adventure",
    "waterfal":"waterfall","mountian":"mountain",
}

def correct_spelling(text):
    return " ".join(SPELL_MAP.get(w, w) for w in text.lower().split())

def _sim(a, b):
    a, b = a.lower(), b.lower()
    m, n = len(a), len(b)
    dp = list(range(n+1))
    for i in range(1, m+1):
        prev, dp[0] = dp[:], i
        for j in range(1, n+1):
            dp[j] = prev[j-1] if a[i-1]==b[j-1] else 1+min(prev[j], dp[j-1], prev[j-1])
    return 1 - dp[n]/max(m, n, 1)

def fuzzy_city(text):
    t = text.lower()
    for c in sorted(KNOWN_CITIES, key=len, reverse=True):
        if c in t: return c
    tokens = t.split()
    cands = tokens + [" ".join(tokens[i:i+2]) for i in range(len(tokens)-1)]
    best_city, best_score = None, 0.0
    for cand in cands:
        if len(cand) < 3: continue
        if FUZZY_OK:
            res = fuzz_process.extractOne(cand, KNOWN_CITIES, scorer=fuzz.ratio, score_cutoff=75)
            if res and res[1]/100 > best_score:
                best_score = res[1]/100; best_city = res[0]
        else:
            for city in KNOWN_CITIES:
                s = _sim(cand, city)
                if s > 0.78 and s > best_score:
                    best_score = s; best_city = city
    return best_city

def detect_intent(text):
    t = text.lower()
    if any(re.search(r'\b'+w+r'\b', t) for w in ["hi","hello","hey","assalam","salam","helo","hii"]):
        return "greeting"
    if any(re.search(r'\b'+w+r'\b', t) for w in ["thank","thanks","shukriya","thx","thankyou"]):
        return "thanks"
    if any(re.search(r'\b'+w+r'\b', t) for w in ["bye","exit","quit","goodbye","alvida"]) or "khuda hafiz" in t:
        return "exit"
    if any(re.search(r'\b'+w+r'\b', t) for w in ["more","next","aur"]) or "show more" in t or "more places" in t:
        return "more"
    rec_kw = ["place","places","visit","suggest","recommend","best","top","good",
              "mall","malls","park","parks","lake","mountain","hiking","trail",
              "waterfall","tourist","attraction","show","find","tell","give",
              "travel","trip","tour","where","which","jana","ghoomna"]
    if any(w in t for w in rec_kw) or fuzzy_city(t):
        return "recommendation"
    return "unknown"

def extract_all(text):
    corrected = correct_spelling(text)
    t = corrected.lower()
    intent = {}
    city = fuzzy_city(t)
    if city: intent["city"] = city
    for phrase in sorted(CATEGORY_MAP, key=len, reverse=True):
        if phrase in t:
            intent["category"] = CATEGORY_MAP[phrase]; break
    if "category" not in intent:
        for word in t.split():
            if len(word) < 4: continue
            best_phrase, best_s = None, 0.0
            if FUZZY_OK:
                res = fuzz_process.extractOne(word, list(CATEGORY_MAP.keys()), scorer=fuzz.ratio, score_cutoff=82)
                if res: best_phrase = res[0]
            else:
                for phrase in CATEGORY_MAP:
                    s = _sim(word, phrase)
                    if s > 0.82 and s > best_s:
                        best_s = s; best_phrase = phrase
            if best_phrase:
                intent["category"] = CATEGORY_MAP[best_phrase]; break
    for kw, val in UTYPE_MAP.items():
        if re.search(r'\b'+re.escape(kw)+r'\b', t):
            intent["user_type"] = val; break
    for kw, val in BUDGET_MAP.items():
        if re.search(r'\b'+re.escape(kw)+r'\b', t):
            intent["budget"] = val; break
    return intent, corrected

def normalise(arr):
    mn, mx = arr.min(), arr.max()
    if mx - mn < 1e-8: return np.ones(len(arr))
    return (arr - mn) / (mx - mn)

def hybrid_recommend(user_id, city=None, user_type=None, budget=None, category=None, exclude_ids=None, top_n=3):
    exclude_ids = exclude_ids or []
    data = df.copy()
    if city:      data = data[data["city_l"] == city.lower()]
    if category:  data = data[data["category_l"].str.contains(category.lower(), na=False)]
    if user_type: data = data[data["utype_l"].str.contains(user_type.lower(), na=False)]
    if budget:    data = data[data["budget_l"] == budget.lower()]
    if exclude_ids: data = data[~data["place_id"].isin(exclude_ids)]
    if data.empty and budget:
        data = df.copy()
        if city:      data = data[data["city_l"] == city.lower()]
        if category:  data = data[data["category_l"].str.contains(category.lower(), na=False)]
        if user_type: data = data[data["utype_l"].str.contains(user_type.lower(), na=False)]
        if exclude_ids: data = data[~data["place_id"].isin(exclude_ids)]
    if data.empty and category:
        data = df.copy()
        if city:      data = data[data["city_l"] == city.lower()]
        if user_type: data = data[data["utype_l"].str.contains(user_type.lower(), na=False)]
        if exclude_ids: data = data[~data["place_id"].isin(exclude_ids)]
    if data.empty: return pd.DataFrame()
    idxs   = data.index.tolist()
    cb_raw = content_sim[idxs][:, idxs].mean(axis=1)
    if user_id in user_index:
        uidx = user_index[user_id]
        cf_raw = []
        for pid in data["place_id"]:
            if pid in user_item.columns:
                r = user_item[pid].values
                s = np.dot(user_sim[uidx], r) / (np.sum(np.abs(user_sim[uidx])) + 1e-8)
            else: s = 0.0
            cf_raw.append(s)
        cf_raw = np.array(cf_raw)
    else:
        cf_raw = np.zeros(len(data))
    data       = data.copy()
    data["_score"] = (W_RATING * normalise(data["rating"].values) +
                      W_CONTENT * normalise(cb_raw) +
                      W_CF      * normalise(cf_raw))
    return data.sort_values("_score", ascending=False).drop_duplicates("place_name").head(top_n)

def maps_link(lat, lon): return f"https://maps.google.com/?q={lat},{lon}"

def format_places(results, rank_start=1):
    lines = []
    for i, (_, r) in enumerate(results.iterrows()):
        bi = {"low":"💚","medium":"💛","high":"💰"}.get(r["budget"].lower(), "💰")
        stars = "⭐" * int(round(r["rating"]))
        lines.append(
            f"{rank_start+i}. 📍 {r['place_name']}\n"
            f"   Category: {r['category']}\n"
            f"   Rating: {r['rating']}/5.0 {stars}\n"
            f"   Budget: {bi} {r['budget']}\n"
            f"   Best For: {r['user_type']}\n"
            f"   Best Time: {r['best_time_to_visit']}\n"
            f"   🗺️ Map: {maps_link(r['latitude'], r['longitude'])}"
        )
    return "\n\n".join(lines)

def ctx_label(intent):
    p = []
    if intent.get("category"):  p.append(intent["category"]+"s")
    if intent.get("city"):      p.append("in " + intent["city"].title())
    if intent.get("user_type"): p.append("for " + intent["user_type"].title())
    if intent.get("budget"):    p.append("(" + intent["budget"].title() + " budget)")
    return " ".join(p) if p else "tourist places"

# ─────────────────────────────────────────────────────────────────
#  SESSION STORE  (in-memory, per session_id)
# ─────────────────────────────────────────────────────────────────
sessions = {}

class SessionState:
    def __init__(self):
        self.intent      = {}
        self.shown_ids   = []
        self.total_shown = 0
        self.active      = False
        self.context     = {}
        self.user_id     = "U1"

    def new_search(self, intent):
        self.intent = intent; self.shown_ids = []; self.total_shown = 0
        self.active = True;   self.context   = dict(intent)

    def merge(self, new_intent):
        merged = {}
        if not new_intent.get("city") and self.context.get("city"):
            merged["city"] = self.context["city"]
        merged.update({k: v for k, v in new_intent.items() if v})
        return merged

# ─────────────────────────────────────────────────────────────────
#  FASTAPI APP
# ─────────────────────────────────────────────────────────────────
app = FastAPI(title="SurfNStay AI Chatbot")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

class ChatRequest(BaseModel):
    message:    str
    session_id: str = ""

class ChatResponse(BaseModel):
    reply:      str
    session_id: str

@app.get("/")
def root():
    return {"status": "SurfNStay Chatbot API running ✅"}

@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    sid = req.session_id or str(uuid.uuid4())
    if sid not in sessions:
        sessions[sid] = SessionState()
    session = sessions[sid]

    raw    = req.message.strip()
    fixed  = correct_spelling(raw)
    itype  = detect_intent(fixed)
    reply  = ""

    if itype == "exit":
        del sessions[sid]
        reply = "Khuda Hafiz! 🌍 Safe travels! ✈️"

    elif itype == "greeting":
        reply = ("Hello! 😊 Welcome to SurfNStay!\n\n"
                 "I can help you find the best places to visit in Pakistan.\n\n"
                 "Try asking:\n"
                 "• suggest parks in Islamabad for family\n"
                 "• best malls in Lahore for friends\n"
                 "• cheap hiking trails in Swat\n"
                 "• romantic places in Murree for couple\n\n"
                 "Type 'more' to see more results for your last search.")

    elif itype == "thanks":
        reply = "You're most welcome! 😊 Happy to help anytime!\nAsk me about any city or place in Pakistan! 🇵🇰"

    elif itype == "more":
        if not session.active:
            reply = "Please search for places first!\nExample: 'best parks in Islamabad for family'"
        else:
            results = hybrid_recommend(
                user_id=session.user_id,
                city=session.intent.get("city"),
                user_type=session.intent.get("user_type"),
                budget=session.intent.get("budget"),
                category=session.intent.get("category"),
                exclude_ids=session.shown_ids, top_n=3,
            )
            if results.empty:
                reply = f"✅ No more places available for {ctx_label(session.intent)}.\n\nTry searching for a different city or category!"
                session.active = False
            else:
                rank_start = session.total_shown + 1
                session.shown_ids   += results["place_id"].tolist()
                session.total_shown += len(results)
                nxt = hybrid_recommend(
                    user_id=session.user_id,
                    city=session.intent.get("city"), user_type=session.intent.get("user_type"),
                    budget=session.intent.get("budget"), category=session.intent.get("category"),
                    exclude_ids=session.shown_ids, top_n=1
                )
                footer = "\n\nType 'more' for more places." if not nxt.empty else "\n\n✅ That's all places for this search."
                reply  = f"More {ctx_label(session.intent)}:\n\n{format_places(results, rank_start)}{footer}"

    elif itype == "recommendation":
        extracted, _ = extract_all(fixed)
        intent = session.merge(extracted)
        if not intent:
            reply = "🤔 Could you be more specific?\n\nTry: 'best malls in Islamabad for family'"
        elif not intent.get("city"):
            cities = ", ".join(c.title() for c in KNOWN_CITIES[:12])
            reply  = f"🌆 Which city would you like to explore?\n\nAvailable: {cities}..."
            session.context.update(extracted)
        else:
            session.new_search(intent)
            results = hybrid_recommend(
                user_id=session.user_id,
                city=intent.get("city"), user_type=intent.get("user_type"),
                budget=intent.get("budget"), category=intent.get("category"), top_n=3,
            )
            if results.empty:
                reply = f"😔 No places found for {ctx_label(intent)}.\n\nTry removing some filters or searching a different city."
                session.active = False
            else:
                session.shown_ids   = results["place_id"].tolist()
                session.total_shown = len(results)
                nxt = hybrid_recommend(
                    user_id=session.user_id,
                    city=intent.get("city"), user_type=intent.get("user_type"),
                    budget=intent.get("budget"), category=intent.get("category"),
                    exclude_ids=session.shown_ids, top_n=1
                )
                footer = "\n\nType 'more' for more places." if not nxt.empty else "\n\n✅ That's all places for this search."
                reply  = f"✨ Top {ctx_label(intent)} (highest rated first):\n\n{format_places(results, 1)}{footer}"
    else:
        reply = ("🤔 I didn't quite understand that.\n\nTry:\n"
                 "• 'malls in Islamabad for family'\n"
                 "• 'tourist attractions in Murree'\n"
                 "• 'cheap parks in Lahore'")

    return ChatResponse(reply=reply, session_id=sid)
