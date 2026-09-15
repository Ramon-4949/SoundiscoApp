import Foundation
import Supabase

enum SupabaseConfiguration {
    static let projectURL = URL(string: "https://gsrwfgpyflwozxzizmnv.supabase.co")!
    static let publishableKey = "sb_publishable_96knE5-iEOatPKQKJsgOhQ_096eIdCh"
    static let authCallbackURL = URL(string: "soundisco://auth/callback")!
}

enum SupabaseClientFactory {
    static let shared = makeClient()

    static func makeClient(
        projectURL: URL = SupabaseConfiguration.projectURL,
        publishableKey: String = SupabaseConfiguration.publishableKey
    ) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: publishableKey,
            options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }
}

// Compatibility facade for the authentication and employee features.
enum SupabaseService {
    static let client = SupabaseClientFactory.shared
    static let callback = SupabaseConfiguration.authCallbackURL
}
