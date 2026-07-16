// Auto-generated types for the LANDER Buddy Supabase database.
// Re-generate with: npx supabase gen types typescript --project-id YOUR_ID

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export interface Database {
  public: {
    Tables: {
      teams: {
        Row: {
          id: string;
          name: string;
          created_at: string;
          thresholds: Thresholds;
        };
        Insert: {
          id?: string;
          name: string;
          created_at?: string;
          thresholds?: Thresholds;
        };
        Update: {
          id?: string;
          name?: string;
          thresholds?: Thresholds;
        };
      };
      profiles: {
        Row: {
          id: string;
          team_id: string | null;
          role: "trainer" | "coach";
          full_name: string | null;
          created_at: string;
        };
        Insert: {
          id: string;
          team_id?: string | null;
          role?: "trainer" | "coach";
          full_name?: string | null;
          created_at?: string;
        };
        Update: {
          team_id?: string | null;
          role?: "trainer" | "coach";
          full_name?: string | null;
        };
      };
      athletes: {
        Row: {
          id: string;
          team_id: string;
          name: string;
          jersey_number: string;
          position: string;
          active: boolean;
          created_at: string;
        };
        Insert: {
          id?: string;
          team_id: string;
          name: string;
          jersey_number?: string;
          position?: string;
          active?: boolean;
          created_at?: string;
        };
        Update: {
          name?: string;
          jersey_number?: string;
          position?: string;
          active?: boolean;
        };
      };
      sessions: {
        Row: {
          id: string;
          team_id: string;
          date: string;
          state: "fresh" | "fatigued";
          notes: string | null;
          created_by: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          team_id: string;
          date: string;
          state: "fresh" | "fatigued";
          notes?: string | null;
          created_by?: string | null;
          created_at?: string;
        };
        Update: {
          date?: string;
          state?: "fresh" | "fatigued";
          notes?: string | null;
        };
      };
      captures: {
        Row: {
          id: string;
          session_id: string;
          athlete_id: string;
          knee_valgus_deg: number | null;
          knee_flexion_deg: number | null;
          trunk_lean_deg: number | null;
          less_score: number | null;
          risk_level: string | null;
          asymmetry_index: number | null;
          vulnerability_score: number | null;
          fatigue_category: string | null;
          raw_metrics: Json | null;
          annotated_frame_url: string | null;
          video_url: string | null;
          model_version: string | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          session_id: string;
          athlete_id: string;
          knee_valgus_deg?: number | null;
          knee_flexion_deg?: number | null;
          trunk_lean_deg?: number | null;
          less_score?: number | null;
          risk_level?: string | null;
          asymmetry_index?: number | null;
          vulnerability_score?: number | null;
          fatigue_category?: string | null;
          raw_metrics?: Json | null;
          annotated_frame_url?: string | null;
          video_url?: string | null;
          model_version?: string | null;
          created_at?: string;
        };
        Update: {
          knee_valgus_deg?: number | null;
          knee_flexion_deg?: number | null;
          trunk_lean_deg?: number | null;
          less_score?: number | null;
          risk_level?: string | null;
          asymmetry_index?: number | null;
          vulnerability_score?: number | null;
          fatigue_category?: string | null;
          raw_metrics?: Json | null;
          annotated_frame_url?: string | null;
          model_version?: string | null;
        };
      };
    };
    Views: Record<string, never>;
    Functions: {
      my_team_id: {
        Args: Record<string, never>;
        Returns: string;
      };
    };
    Enums: Record<string, never>;
  };
}

// ─── App-level types ──────────────────────────────────────────────────────────

export type Team = Database["public"]["Tables"]["teams"]["Row"];
export type Profile = Database["public"]["Tables"]["profiles"]["Row"];
export type Athlete = Database["public"]["Tables"]["athletes"]["Row"];
export type Session = Database["public"]["Tables"]["sessions"]["Row"];
export type Capture = Database["public"]["Tables"]["captures"]["Row"];

export interface Thresholds {
  valgus_yellow_deg: number;
  valgus_red_deg: number;
  flexion_yellow_deg: number;
  flexion_red_deg: number;
  delta_yellow_pct: number;
  delta_red_pct: number;
  baseline_n_sessions: number;
}

export type ReadinessStatus = "green" | "yellow" | "red" | "none";
export type Trend = "improving" | "stable" | "worsening" | "unknown";

export interface AthleteReadiness {
  athlete: Athlete;
  status: ReadinessStatus;
  trend: Trend;
  latestValgus: number | null;
  latestFlexion: number | null;
  fatigueDeltaPct: number | null;
  vulnerabilityScore: number | null;
  note: string;
  hasBaseline: boolean;
  weeksOfData: number;
}

export interface CaptureWithSession extends Capture {
  sessions: Session;
}

export interface AthleteWithCaptures extends Athlete {
  captures: CaptureWithSession[];
}

// CV Model API shapes
export interface ModelMetrics {
  knee_valgus_deg: number;
  knee_flexion_deg: number;
  trunk_lean_deg: number;
  less_score: number;
  risk_level: string;
  asymmetry_index: number;
  raw?: Record<string, unknown>;
}

export type SessionItem = {
  file: File;
  athleteId: string;
  athleteName: string;
  status: "pending" | "processing" | "done" | "error";
  metrics: ModelMetrics | null;
  error: string | null;
};
