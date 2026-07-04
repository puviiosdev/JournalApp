import Foundation
import Supabase

/// A thread-safe in-memory auth storage to bypass Keychain storage permission restrictions in the Simulator.
final class InMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.puvi.InMemoryStorage", attributes: .concurrent)
    private var storage: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        queue.async(flags: .barrier) {
            self.storage[key] = value
        }
    }

    func retrieve(key: String) -> Data? {
        queue.sync {
            self.storage[key]
        }
    }

    func remove(key: String) throws {
        queue.async(flags: .barrier) {
            self.storage.removeValue(forKey: key)
        }
    }
}

final class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let supabaseURL = URL(string: urlString) else {
            fatalError("SUPABASE_URL not configured in Info.plist / Build settings")
        }
        
        guard let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            fatalError("SUPABASE_ANON_KEY not configured in Info.plist / Build settings")
        }
        
        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(
                    storage: InMemoryStorage()
                )
            )
        )
    }
}
