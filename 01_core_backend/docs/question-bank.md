# StudyAI Question Bank

## Overview

The StudyAI question bank is a curated collection of real math competition and standardized test problems stored in PostgreSQL. Questions are embedded with OpenAI `text-embedding-3-small` and retrieved using semantic similarity search against the user's session context, mistakes, and weakness profile.

---

## Dataset Summary

| Source | Label | Problems | Difficulty | Question Type |
|--------|-------|----------|------------|---------------|
| AJHSME (1985–1999) | `amc8` | ~450 | 1–3 | Multiple choice (5 options) |
| AMC 8 (2000–2024) | `amc8` | ~625 | 1–3 | Multiple choice (5 options) |
| AMC 10 (2000–2024) | `amc10` | ~1,440 | 2–4 | Multiple choice (5 options) |
| AMC 12 (2000–2025) | `amc12` | ~1,199 | 2–5 | Multiple choice (5 options) |
| AIME (1983–2024) | `aime` | ~931 | 3–5 | Short answer (integer 0–999) |
| SAT Math | `sat` | ~208 | 3 | Multiple choice (4 options) |
| **Total** | | **~4,853** | | |

---

## Sources

### AJHSME / AMC 8 (`amc8`)
**American Junior High School Mathematics Examination** (1985–1999), renamed **AMC 8** from 2000.

- **Target audience**: Grade 8 and below
- **Format**: 25–30 multiple choice questions, answers A–E
- **Difficulty scale** (by problem position):
  - Problems 1–8 → difficulty **1** (easy)
  - Problems 9–17 → difficulty **2** (medium)
  - Problems 18–25/30 → difficulty **3** (hard)
- **Topics**: Arithmetic, basic algebra, geometry, number sense, logic, word problems
- **Source**: Scraped from [AoPS wiki](https://artofproblemsolving.com/wiki) via `scrape-aops-amc.js`
- **Answer key**: From AoPS answer key pages (`{year}_AJHSME_Answer_Key` / `{year}_AMC_8_Answer_Key`)

---

### AMC 10 (`amc10`)
**American Mathematics Competition 10** — open to students in grade 10 and below.

- **Target audience**: Grade 9–10, strong middle schoolers
- **Format**: 30 multiple choice questions, answers A–E
- **Variants**: Single test 2000–2001; AMC 10A + 10B from 2002 onwards
- **Difficulty scale** (by problem position):
  - Problems 1–10 → difficulty **2**
  - Problems 11–20 → difficulty **3**
  - Problems 21–30 → difficulty **4**
- **Topics**: Algebra, geometry, number theory, combinatorics, probability
- **Source**: Scraped from AoPS wiki via `scrape-aops-amc.js`

---

### AMC 12 (`amc12`)
**American Mathematics Competition 12** — open to students in grade 12 and below.

- **Target audience**: Grade 10–12, competitive math students
- **Format**: 30 multiple choice questions, answers A–E
- **Variants**: AMC 12A + 12B from 2002 onwards
- **Difficulty scale** (by problem position):
  - Problems 1–10 → difficulty **2**
  - Problems 11–20 → difficulty **3**
  - Problems 21–30 → difficulty **4–5**
- **Topics**: Algebra, geometry, trigonometry, number theory, combinatorics, logarithms, complex numbers
- **Source**: `edev2000/amc12-full` on HuggingFace (JSONL, CC0 / unspecified license)
- **Note**: Asymptote figures stripped from question text and replaced with scraped PNG images from AoPS

---

### AIME (`aime`)
**American Invitational Mathematics Examination** — invitation-only for top AMC scorers.

- **Target audience**: Elite high school competitors (top ~5% of AMC participants)
- **Format**: 15 short answer questions, integer answers 0–999, no multiple choice
- **Variants**: Single test 1983–1999; AIME I + AIME II from 2000 onwards
- **Difficulty scale** (by problem position):
  - Problems 1–5 → difficulty **3**
  - Problems 6–10 → difficulty **4**
  - Problems 11–15 → difficulty **5**
- **Topics**: Number theory, algebra, geometry, combinatorics — all at olympiad level
- **Source**: `gneubig/aime-1983-2024` on HuggingFace (CSV, CC0 license)
- **Figures**: Scraped from AoPS wiki where available

---

### SAT Math (`sat`)
**SAT Mathematics Section** — US college admission standardized test.

- **Target audience**: Grade 11–12, college-bound students
- **Format**: Multiple choice (4 options A–D) and grid-in; this dataset contains multiple choice only
- **Difficulty**: All tagged difficulty **3** (no per-question difficulty in source data)
- **Topics**: Algebra, data analysis, advanced math, problem solving — applied/contextual problems
- **Source**: AGIEval `sat-math.jsonl` from [ruixiangcui/AGIEval](https://github.com/ruixiangcui/AGIEval) on GitHub (MIT license)
- **Note**: AGIEval already excluded figure-dependent problems from this dataset; an additional ~12 problems with figure references were purged during import

---

## Difficulty Scale

| Level | Label | Description | Typical source |
|-------|-------|-------------|----------------|
| 1 | Beginner | Early AMC 8 / AJHSME problems | AMC 8 P1–8 |
| 2 | Easy–Medium | Mid AMC 8, early AMC 10 | AMC 8 P9–17, AMC 10 P1–10 |
| 3 | Intermediate | Late AMC 8, mid AMC 10/12, SAT | AMC 10 P11–20, SAT |
| 4 | Advanced | Hard AMC 10/12, mid AIME | AMC 10 P21–30, AIME P1–10 |
| 5 | Expert | Hard AMC 12, hard AIME | AMC 12 P21–30, AIME P11–15 |

---

## Topics

All questions are tagged with a two-level topic using GPT-4o-mini classification:

| Category | Subcategories |
|----------|--------------|
| **Algebra** | Linear Equations, Quadratic Equations, Polynomials, Functions & Graphs, Inequalities, Systems of Equations, Exponents & Logarithms, Word Problems |
| **Number Theory** | Divisibility & Primes, Modular Arithmetic, Integer Properties, Diophantine Equations |
| **Geometry** | Triangles, Circles, Polygons, Coordinate Geometry, 3D Geometry, Angles & Lines |
| **Combinatorics** | Counting & Permutations, Combinations, Probability, Expected Value |
| **Sequences & Series** | Arithmetic, Geometric, Recursive |
| **Trigonometry** | Right Triangles, Identities & Equations |
| **Statistics** | Data Analysis, Mean / Median / Mode |
| **Logic** | Word Problems |

---

## Figures

Questions with geometric diagrams have the figure stored as a base64-encoded PNG in `question_bank.figure_data`. Figures are scraped from AoPS wiki's pre-rendered Asymptote images (`class="latexcenter"`).

- AMC 8 / AMC 10: figures scraped during `scrape-aops-amc.js`
- AMC 12 / AIME: Asymptote code stripped from question text; figures scraped via `scrape-question-figures.js`
- SAT: figure-dependent questions excluded (AGIEval pre-filtered)

Questions without a figure have `figure_data = NULL`.

---

## Retrieval Architecture

Questions are retrieved using **hybrid retrieval**: metadata pre-filter + in-memory cosine similarity.

```
User context (sessions + mistakes + weakness keys)
    ↓
buildContextSummary() → short natural language string
    ↓
OpenAI text-embedding-3-small → 1536-dim query vector
    ↓
In-memory cache (loaded once at server startup, ~28MB)
    ├── Metadata pre-filter: difficulty range, question type, source, exclude seen
    └── Cosine similarity ranking
    ↓
Diversity filter (≤3 questions per topic in a set)
    ↓
Top K questions → formatted as GeneratedQuestion for iOS
```

**Cache**: All embeddings (~2,350+ rows × 1536 floats) are loaded into memory on first request. Subsequent retrievals are instant. Invalidated on server restart.

---

## Database Schema

```sql
question_bank (
  id              UUID PRIMARY KEY,
  source          VARCHAR(20),     -- 'amc8' | 'amc10' | 'amc12' | 'aime' | 'sat'
  source_id       TEXT,            -- e.g. '2023A-P15', '1990-I-5'
  subject         VARCHAR(50),     -- always 'Mathematics' currently
  topic           VARCHAR(120),    -- 'Geometry - Triangles'
  difficulty      INTEGER,         -- 1–5
  question_type   VARCHAR(20),     -- 'multiple_choice' | 'short_answer'
  question        TEXT,            -- LaTeX notation
  options         JSONB,           -- [{label, text, is_correct}] or null
  correct_answer  TEXT,            -- letter (A–E) or integer string
  explanation     TEXT,
  embedding       FLOAT8[],        -- 1536 dims, text-embedding-3-small
  figure_data     TEXT,            -- base64 PNG or null
  figure_mime     VARCHAR(20),     -- 'image/png' or null
  times_used      INTEGER,
  created_at      TIMESTAMPTZ
)

user_seen_questions (
  user_id         UUID,
  question_id     UUID REFERENCES question_bank(id),
  seen_at         TIMESTAMPTZ,
  was_correct     BOOLEAN,
  PRIMARY KEY (user_id, question_id)
)
```

---

## Scripts

| Script | Purpose |
|--------|---------|
| `import-question-bank.js` | Import AMC12, AIME, SAT from HuggingFace datasets |
| `scrape-aops-amc.js` | Scrape AMC 8 and AMC 10 from AoPS wiki |
| `scrape-question-figures.js` | Scrape figures for AMC12/AIME from AoPS |
| `cleanup-asy-blocks.js` | Strip Asymptote code from question text, mark for figure scrape |
| `tag-question-topics.js` | GPT-4o-mini topic tagging + re-embed with topic |
| `test-question-bank.js` | Retrieval quality test + figure scan + purge |

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/ai/generate-questions/practice/v2` | Generate questions — use `mode: 4` for bank retrieval |
| `GET` | `/api/ai/question-bank/figure/:questionId` | Serve stored figure PNG (cached 1 year) |
| `POST` | `/api/ai/question-bank/record-result` | Mark question seen, record correctness |

**Mode 4 request body:**
```json
{
  "subject": "Mathematics",
  "mode": 4,
  "count": 5,
  "difficulty": 3,
  "bank_source": "amc10",
  "question_type": "any",
  "mistakes_data": [...],
  "short_term_context": [...]
}
```

---

## Licensing

| Dataset | License | Commercial use |
|---------|---------|----------------|
| AJHSME / AMC 8 / AMC 10 (AoPS scrape) | MAA copyright — educational use | ⚠️ Check with MAA |
| AMC 12 (`edev2000/amc12-full`) | Not specified | ⚠️ Check with MAA |
| AIME (`gneubig/aime-1983-2024`) | CC0 (Public Domain) | ✅ |
| SAT (AGIEval) | MIT | ✅ |

> MAA (Mathematical Association of America) holds copyright on AMC/AIME problems. Educational and non-commercial use is generally permitted. For commercial distribution, contact MAA for licensing.
