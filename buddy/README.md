# LANDER Buddy

> A weekly knee readiness monitoring app for sports teams, powered by LANDER computer vision.

**Think:** WHOOP/Oura recovery scores, but for the knees, for a whole team — and instead of just a number, it gives the coach a decision ("rest Player 12 this week").

## What It Does

1. **Capture** — Film each athlete's standard jump twice a week (fresh + fatigued)
2. **Measure** — LANDER CV model reads knee mechanics from video
3. **Compare** — The app computes baselines, fatigue deltas, and trends per athlete
4. **Recommend** — Each athlete gets a Green/Yellow/Red readiness status + action
5. **Track** — Trends build across the season so risk is caught early

## Tech Stack

- **Frontend:** Next.js 14 (App Router) + TypeScript + Tailwind CSS
- **Database:** Supabase (Postgres + Auth + RLS)
- **Charts:** Recharts
- **CV Model:** LANDER FastAPI backend (mock included)

## Getting Started

### 1. Clone & Install

```bash
git clone <repo-url>
cd lander-buddy
npm install
```

### 2. Set Up Supabase

1. Create a new project at [supabase.com](https://supabase.com)
2. Run the SQL in `supabase/schema.sql` in your Supabase SQL Editor
3. Copy `.env.local.example` to `.env.local` and fill in your Supabase URL + anon key

### 3. Run

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

### 4. CV Model

By default, the app uses a **realistic mock** (no real model server needed). The mock produces plausible biomechanics values with slight randomness.

To connect to the real LANDER CV model:
1. Run `server.py` from the LANDER repo (`uvicorn server:app --port 8000`)
2. Set in `.env.local`:
   ```
   NEXT_PUBLIC_CV_MODEL_MODE=real
   NEXT_PUBLIC_CV_MODEL_URL=http://localhost:8000
   ```

## Key Screens

| Screen | Description |
|--------|-------------|
| **Readiness Board** | Home — whole roster at a glance: Green/Yellow/Red per athlete |
| **New Capture** | Trainer flow: pick date + fresh/fatigued, upload videos, assign athletes |
| **Athlete Profile** | Individual trend charts, baseline, fatigue delta history |
| **Roster** | Add/edit/remove athletes |
| **Sessions** | Browse past capture sessions |
| **Settings** | Team name, tunable thresholds, model config |

## Core Engine (lib/engine/)

- **`delta.ts`** — Baseline computation, fatigue delta, trend detection, readiness status, recommendations
- **`model.ts`** — CV model mock + real API integration (matches `server.py` contract)

## Thresholds (Tunable in Settings)

| Threshold | Default | Meaning |
|-----------|---------|---------|
| Valgus Yellow | 5° | Caution zone |
| Valgus Red | 10° | High risk |
| Flexion Yellow | 45° | Caution (lower = worse) |
| Flexion Red | 30° | High risk |
| Delta Yellow | 10% | Fatigue worsening |
| Delta Red | 20% | Critical fatigue worsening |
| Baseline N | 3 | Fresh sessions to average |

## Architecture

```
app/
  (auth)/        — Login / Signup pages
  (app)/         — Authenticated app pages
    page.tsx     — Readiness Board (home)
    capture/     — New Capture Session flow
    athlete/[id] — Athlete Profile + charts
    sessions/    — Session list + detail
    settings/    — Team settings + thresholds
    roster/      — Roster management
components/      — Reusable UI components
lib/
  engine/        — Delta engine + model integration
  supabase/      — Supabase client/server/middleware
  types/         — TypeScript types + DB schema
  utils.ts       — Helpers, color mappings
supabase/
  schema.sql     — Database schema (run in SQL Editor)
```

## License

Proprietary — LANDER Inc.
