import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) var authManager
    @State private var showSignUp = false
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Brand
                VStack(spacing: 8) {
                    Text("LANDER")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.brand)
                    Text("Buddy")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Sign in to access your team readiness board.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                    
                    if let error = authManager.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    Button(action: {
                        Task { await authManager.logIn(email: email, password: password) }
                    }) {
                        if authManager.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Text("Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
                    .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Sign up link
                Button("Don't have an account? Sign up") {
                    showSignUp = true
                }
                .font(.subheadline)
                .foregroundColor(.brand)
                .padding(.bottom, 24)
            }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
                    .environment(authManager)
            }
        }
    }
}
