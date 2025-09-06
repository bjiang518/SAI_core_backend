//
//  LoginView.swift
//  StudyAI
//
//  Created by Claude Code on 8/31/25.
//

import SwiftUI

struct LoginView: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingRegister = false
    
    var onLoginSuccess: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // App Logo and Title
                VStack(spacing: 16) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("StudyAI")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Your AI-Powered Homework Helper")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Login Form
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button(action: performLogin) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text("Sign In")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    
                    Button("Don't have an account? Sign Up") {
                        showingRegister = true
                    }
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Version Info
                Text("Version 1.0 • Powered by OpenAI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
        }
        .sheet(isPresented: $showingRegister) {
            RegisterView(onRegisterSuccess: onLoginSuccess)
        }
    }
    
    private func performLogin() {
        guard !email.isEmpty && !password.isEmpty else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            let result = await networkService.login(email: email, password: password)
            
            await MainActor.run {
                isLoading = false
                
                if result.success {
                    // Store authentication token if provided
                    if let token = result.token {
                        UserDefaults.standard.set(token, forKey: "auth_token")
                        UserDefaults.standard.set(email, forKey: "user_email")
                    }
                    onLoginSuccess()
                } else {
                    errorMessage = result.message
                }
            }
        }
    }
}

struct RegisterView: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    var onRegisterSuccess: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Full Name")
                            .font(.headline)
                        TextField("Enter your full name", text: $name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                        SecureField("Create a password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.headline)
                        SecureField("Confirm your password", text: $confirmPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                .padding(.horizontal)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: performRegister) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text("Create Account")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isLoading || !isFormValid)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !name.isEmpty && !email.isEmpty && !password.isEmpty && 
        password == confirmPassword && password.count >= 6
    }
    
    private func performRegister() {
        guard isFormValid else {
            errorMessage = "Please fill all fields correctly"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            // For now, we'll use a simplified registration that just calls the login endpoint
            // In a real app, you'd call a proper registration endpoint
            let result = await networkService.login(email: email, password: password)
            
            await MainActor.run {
                isLoading = false
                
                if result.success {
                    UserDefaults.standard.set(result.token, forKey: "auth_token")
                    UserDefaults.standard.set(email, forKey: "user_email")
                    UserDefaults.standard.set(name, forKey: "user_name")
                    
                    presentationMode.wrappedValue.dismiss()
                    onRegisterSuccess()
                } else {
                    errorMessage = result.message
                }
            }
        }
    }
}

#Preview {
    LoginView(onLoginSuccess: {})
}