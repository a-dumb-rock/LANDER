-- ============================================================
-- LANDER Buddy — Supabase Database Schema
-- Run this in your Supabase SQL Editor to set up the database.
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────
-- TEAMS
-- ─────────────────────────────────────────────
create table if not exists teams (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  created_at   timestamptz not null default now(),
  -- Tunable thresholds stored as JSON, with defaults matching LANDER config.py
  thresholds   jsonb not null default '{
    "valgus_yellow_deg": 5,
    "valgus_red_deg": 10,
    "flexion_yellow_deg": 45,
    "flexion_red_deg": 30,
    "delta_yellow_pct": 10,
    "delta_red_pct": 20,
    "baseline_n_sessions": 3
  }'::jsonb
);

-- ─────────────────────────────────────────────
-- USERS (extends Supabase auth.users)
-- ─────────────────────────────────────────────
create table if not exists profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  team_id    uuid references teams(id) on delete set null,
  role       text not null default 'trainer' check (role in ('trainer', 'coach')),
  full_name  text,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- ATHLETES
-- ─────────────────────────────────────────────
create table if not exists athletes (
  id             uuid primary key default gen_random_uuid(),
  team_id        uuid not null references teams(id) on delete cascade,
  name           text not null,
  jersey_number  text not null default '',
  position       text not null default '',
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- SESSIONS
-- ─────────────────────────────────────────────
create table if not exists sessions (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references teams(id) on delete cascade,
  date         date not null,
  state        text not null check (state in ('fresh', 'fatigued')),
  notes        text,
  created_by   uuid references profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- CAPTURES (one per athlete-jump)
-- ─────────────────────────────────────────────
create table if not exists captures (
  id                    uuid primary key default gen_random_uuid(),
  session_id            uuid not null references sessions(id) on delete cascade,
  athlete_id            uuid not null references athletes(id) on delete cascade,
  -- Metrics from the CV model
  knee_valgus_deg       numeric,
  knee_flexion_deg      numeric,
  trunk_lean_deg        numeric,
  less_score            numeric,
  risk_level            text,
  -- Additional from API
  asymmetry_index       numeric,
  vulnerability_score   numeric,
  fatigue_category      text,
  -- Raw model output (full JSON blob for future use)
  raw_metrics           jsonb,
  annotated_frame_url   text,
  video_url             text,
  model_version         text default 'mock',
  created_at            timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────
alter table teams    enable row level security;
alter table profiles enable row level security;
alter table athletes enable row level security;
alter table sessions enable row level security;
alter table captures enable row level security;

-- Profiles: users can only see/edit their own profile
create policy "profiles: own row" on profiles
  for all using (auth.uid() = id);

-- Helper function: get current user's team_id
create or replace function my_team_id()
returns uuid language sql stable security definer as $$
  select team_id from profiles where id = auth.uid()
$$;

-- Teams: users can read/update their own team
create policy "teams: own team" on teams
  for all using (id = my_team_id());

-- Athletes: scoped to user's team
create policy "athletes: own team" on athletes
  for all using (team_id = my_team_id());

-- Sessions: scoped to user's team
create policy "sessions: own team" on sessions
  for all using (team_id = my_team_id());

-- Captures: scoped via sessions to user's team
create policy "captures: own team" on captures
  for all using (
    session_id in (
      select id from sessions where team_id = my_team_id()
    )
  );

-- ─────────────────────────────────────────────
-- AUTO-CREATE PROFILE ON SIGN-UP
-- ─────────────────────────────────────────────
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
