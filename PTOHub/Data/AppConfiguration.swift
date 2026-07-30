import Foundation
@preconcurrency import Supabase

struct AppConfiguration: Sendable {
    let supabaseURL: URL
    let publishableKey: String
    let webURL: URL

    static func load(bundle: Bundle = .main) throws -> AppConfiguration {
        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            !urlString.contains("your-project-ref"),
            let key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
            !key.contains("replace_me"),
            !key.contains("your_key")
        else {
            throw ConfigurationError.missingSupabase
        }
        let webString = bundle.object(forInfoDictionaryKey: "PTO_HUB_WEB_URL") as? String ?? "https://example.com"
        return AppConfiguration(supabaseURL: url, publishableKey: key, webURL: URL(string: webString) ?? url)
    }

    func makeClient() -> SupabaseClient {
        SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: publishableKey,
            options: .init(
                auth: .init(
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                ),
                global: .init(headers: ["x-client-info": "staff-hub-ios/1.0"])
            )
        )
    }
}

enum ConfigurationError: LocalizedError, Sendable {
    case missingSupabase

    var errorDescription: String? {
        "Add a Config/Local.xcconfig file with the Supabase project URL and publishable key."
    }
}
