import Foundation
import Supabase

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    
    private var authSubscription: Task<Void, Never>?
    
    private init() {
        // Check current session cache synchronously
        self.isAuthenticated = SupabaseManager.shared.client.auth.currentSession != nil
        
        // Listen to auth state changes to dynamically update isAuthenticated
        self.authSubscription = Task { [weak self] in
            guard let self = self else { return }
            do {
                let stream = await SupabaseManager.shared.client.auth.authStateChanges
                for await (event, session) in stream {
                    print("Auth State Change Event: \(event) | Session is active: \(session != nil)")
                    await MainActor.run {
                        self.isAuthenticated = session != nil
                    }
                }
            }
        }
    }
    
    deinit {
        authSubscription?.cancel()
    }
    
    /// Signs up a new user with their email and password.
    func signUp(email: String, password: String) async throws {
        do {
            let response = try await SupabaseManager.shared.client.auth.signUp(
                email: email,
                password: password
            )
            print("Successfully signed up user: \(email)")
            // If email confirmation is enabled, session will be nil. Do not log in yet.
            self.isAuthenticated = response.session != nil
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            self.isAuthenticated = false
            throw error
        }
    }
    
    /// Signs in an existing user with their email and password.
    func signIn(email: String, password: String) async throws {
        do {
            _ = try await SupabaseManager.shared.client.auth.signIn(
                email: email,
                password: password
            )
            print("Successfully signed in user: \(email)")
            self.isAuthenticated = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
            self.isAuthenticated = false
            throw error
        }
    }
    
    /// Sends a password reset email to the specified user.
    func resetPassword(email: String) async throws {
        try await SupabaseManager.shared.client.auth.resetPasswordForEmail(email)
    }
}

