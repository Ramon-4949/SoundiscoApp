import Foundation
import Supabase

enum SupabaseService {
    // Publishable key: database access remains controlled by server-side RLS.
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://gsrwfgpyflwozxzizmnv.supabase.co")!,
        supabaseKey: "sb_publishable_96knE5-iEOatPKQKJsgOhQ_096eIdCh",
        options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
    )
    static let callback = URL(string: "soundisco://auth/callback")!
}
