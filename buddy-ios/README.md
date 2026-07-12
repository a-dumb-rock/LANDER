# LANDER Buddy — iOS App

> Weekly knee readiness monitoring for sports teams. Native SwiftUI app.

## Setup

### Prerequisites
- Xcode 15+ 
- iOS 17+ target
- A Supabase project (free tier works)

### Steps

1. Open `buddy-ios/` in Xcode (open the `Package.swift` or drag folder into Xcode)
2. Wait for Swift Package Manager to resolve dependencies (Supabase, DGCharts)
3. Edit `LANDERBuddy/Services/Config.swift`:
   - Set your `supabaseURL`
   - Set your `supabaseAnonKey`
   - Set `useMockModel = true` (or point to your LANDER server)
4. Run the SQL from `buddy/supabase/schema.sql` (parent directory) in your Supabase SQL Editor
5. Build & Run on iOS Simulator or device

### Mock Mode

The app ships with a realistic **mock CV model** — no Python server needed. It generates plausible biomechanics data with appropriate variance between fresh and fatigued states.

To use the real LANDER model:
1. Run `server.py` from the LANDER repo root: `uvicorn server:app --port 8000`
2. Set `Config.useMockModel = false` and `Config.cvModelURL = "http://localhost:8000"`

## Architecture

```
LANDERBuddy/
├── App/
│   ├── LANDERBuddyApp.swift   — App entry point
│   ├── AppState.swift          — Central observable state
│   ├── MainTabView.swift       — Tab navigation
│   └── Theme.swift             — Colors & status helpers
├── Models/
│   └── Models.swift            — All data types
├── Engine/
│   ├── DeltaEngine.swift       — Baseline, deltas, trends, readiness
│   └── CVModelService.swift    — Mock + real model API
├── Services/
│   ├── Config.swift            — App configuration
│   ├── AuthManager.swift       — Auth state management
│   └── SupabaseManager.swift   — Database operations
└── Views/
    ├── Auth/                   — Login, SignUp
    ├── Dashboard/              — Readiness Board (home)
    ├── Capture/                — New capture session flow
    ├── Athlete/                — Athlete profile + charts
    ├── Roster/                 — Roster management
    ├── Sessions/               — Session list + detail
    ├── Settings/               — Thresholds, team config
    └── Components/             — Reusable UI (StatusDot, etc.)
```

## Features

- [x] Auth (Supabase email/password + team creation)
- [x] Readiness Board (Green/Yellow/Red per athlete)
- [x] Capture Flow (video selection, athlete assignment, model processing)
- [x] Delta Engine (rolling baseline, fatigue deltas, trend detection)
- [x] Athlete Profile (mini charts, history, recommendations)
- [x] Roster Management (add/edit/remove)
- [x] Session History
- [x] Settings (tunable thresholds)
- [x] CV Model (mock + real API)
