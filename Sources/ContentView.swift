import SwiftUI

struct ContentView: View {
    @ObservedObject private var authService = AuthService.shared
    
    // Sign In states
    @State private var loginEmail = ""
    @State private var loginPassword = ""
    @State private var isLoggingIn = false
    
    // Navigation / Presentation states
    @State private var isShowingSignUp = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isSuccessAlert = false
    
    var body: some View {
        if authService.isAuthenticated {
            MainJournalListView()
        } else {
            NavigationStack {
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Beautiful App Header / Logo
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.bottom, 8)
                    
                    VStack(spacing: 8) {
                        Text("My Journal")
                            .font(.system(.largeTitle, design: .serif))
                            .fontWeight(.bold)
                        
                        Text("Capture your thoughts and memories securely.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 16)
                    
                    // Input Fields
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            TextField("Email", text: $loginEmail)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            SecureField("Password", text: $loginPassword)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)
                    
                    // Forgot Password Link
                    HStack {
                        Spacer()
                        Button(action: {
                            performPasswordReset()
                        }) {
                            Text("Forgot Password?")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                        }
                        .disabled(isLoggingIn)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, -8)
                    
                    // Sign In Button
                    VStack(spacing: 12) {
                        Button(action: {
                            performSignIn()
                        }) {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .disabled(isLoggingIn)
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    // Bottom Sign Up Link
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button(action: {
                            isShowingSignUp = true
                        }) {
                            Text("Sign Up")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                        .disabled(isLoggingIn)
                    }
                    .padding(.bottom, 24)
                }
                .sheet(isPresented: $isShowingSignUp) {
                    SignUpView(isPresented: $isShowingSignUp, onSignUpCompleted: { message, success in
                        self.alertMessage = message
                        self.isSuccessAlert = success
                        // Delay to allow sheet dismiss animation to finish before showing the alert
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.showAlert = true
                        }
                    })
                }
                .alert(isPresented: $showAlert) {
                    Alert(
                        title: Text(isSuccessAlert ? "Success" : "Authentication Alert"),
                        message: Text(alertMessage),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
    }
    
    private func performSignIn() {
        isLoggingIn = true
        
        Task { @MainActor in
            do {
                try await AuthService.shared.signIn(email: loginEmail, password: loginPassword)
                // Clear any leftover alert state on success
                alertMessage = ""
                isSuccessAlert = false
                showAlert = false
            } catch {
                alertMessage = error.localizedDescription
                isSuccessAlert = false
                showAlert = true
            }
            isLoggingIn = false
        }
    }
    
    private func performPasswordReset() {
        guard !loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter your email address in the email field above to request a password reset."
            isSuccessAlert = false
            showAlert = true
            return
        }
        
        isLoggingIn = true
        
        Task { @MainActor in
            do {
                try await AuthService.shared.resetPassword(email: loginEmail)
                alertMessage = "A password reset link has been sent to your email address."
                isSuccessAlert = true
                showAlert = true
            } catch {
                alertMessage = error.localizedDescription
                isSuccessAlert = false
                showAlert = true
            }
            isLoggingIn = false
        }
    }
}

// Separate Sheet View for Sign Up
struct SignUpView: View {
    @Binding var isPresented: Bool
    var onSignUpCompleted: (String, Bool) -> Void
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSigningUp = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Create Account")
                        .font(.system(.title, design: .serif))
                        .fontWeight(.bold)
                        .padding(.top, 16)
                    
                    Text("Sign up to start keeping your journal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Email Address", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        SecureField("Password", text: $password)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    HStack {
                        Image(systemName: "lock.rotation")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        SecureField("Confirm Password", text: $confirmPassword)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                }
                
                Button(action: {
                    performSignUp()
                }) {
                    if isSigningUp {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("Register")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .blue.opacity(0.2), radius: 6, x: 0, y: 3)
                    }
                }
                .disabled(isSigningUp || email.isEmpty || password.isEmpty || confirmPassword.isEmpty)
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func performSignUp() {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        
        isSigningUp = true
        errorMessage = ""
        
        Task { @MainActor in
            do {
                try await AuthService.shared.signUp(email: email, password: password)
                isPresented = false
                onSignUpCompleted("Check your email for the confirmation link!", true)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningUp = false
        }
    }
}

#Preview {
    ContentView()
}
