import Supabase
import SwiftUI

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://ciszaukmnglepvqpulya.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpc3phdWttbmdsZXB2cXB1bHlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjczNTE5MzYsImV4cCI6MjA4MjkyNzkzNn0.XqFaqHS77jPtJv1a34YoWMezTMkEOsJIMMl49b-KSMw",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            redirectToURL: URL(string: "com.googleusercontent.apps.354054312013-rgvhqbp6lf3395scv79jip83iiq330en://")!,
            emitLocalSessionAsInitialSession: true
        )
    )
)
