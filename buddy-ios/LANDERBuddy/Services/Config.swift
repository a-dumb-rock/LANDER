import Foundation

/// App configuration — set your Supabase credentials here.
enum Config {
    // MARK: - Supabase
    // Get these from https://supabase.com/dashboard → your project → Settings → API
    static let supabaseURL = "https://your-project.supabase.co"
    static let supabaseAnonKey = "your-anon-key-here"
    
    // MARK: - CV Model API
    // The URL where your LANDER Python server is running
    // For local dev with simulator: http://localhost:8000
    static let cvModelURL = "http://localhost:8000"
    
    // Set to true to use the built-in mock (no real server needed)
    static let useMockModel = true
}
