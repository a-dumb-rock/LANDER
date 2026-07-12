import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var fullName = ""
    @State private var teamName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: UserRole = .trainer
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("LANDER")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.brand)
                    Text("Create your account")
                        .font(.title3.bold())
                    Text("Set up your team and start monitoring knee readiness.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Form
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your name").font(.caption).foregroundColor(.secondary)
                        TextField("Jane Smith", text: $fullName)
                            .textContentType(.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Team name").font(.caption).foregroundColor(.secondary)
                        TextField("Wildcats Women's Soccer", text: $teamName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your role").font(.caption).foregroundColor(.secondary)
                        Picker("Role", selection: $role) {
                            Text("Athletic Trainer").tag(UserRole.trainer)
                            Text("Coach").tag(UserRole.coach)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email").font(.caption).foregroundColor(.secondary)
                        TextField("you@team.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password").font(.caption).foregroundColor(.secondary)
                        SecureField("At least 6 characters", text: $password)
                            .textContentType(.newPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    if let error = authManager.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        Task {
                            await authManager.signUp(
                                email: email,
                                password: password,
                                fullName: fullName,
                                teamName: teamName.isEmpty ? "\(fullName)'s Team" : teamName,
                                role: role
                            )
                        }
                    }) {
                        if authManager.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Text("Create Account & Team")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
                    .disabled(email.isEmpty || password.count < 6 || fullName.isEmpty || authManager.isLoading)
                }
                .padding(.horizontal, 32)
            }
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }
}
