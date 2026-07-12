import Foundation

/// App configuration
enum Config {
    // Mock mode — no backend needed
    static let useMockModel = true
    static let cvModelURL = "http://localhost:8000"
    
    // Supabase (not used in demo mode)
    static let supabaseURL = "https://placeholder.supabase.co"
    static let supabaseAnonKey = "placeholder"
}
