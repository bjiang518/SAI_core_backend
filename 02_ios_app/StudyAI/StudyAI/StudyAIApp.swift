//
//  StudyAIApp.swift
//  StudyAI
//
//  Created by Bo Jiang on 8/28/25.
//

import SwiftUI
import GoogleSignIn

@main
struct StudyAIApp: App {
    init() {
        setupGoogleSignIn()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // Force light mode globally
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
    
    private func setupGoogleSignIn() {
        
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
    }
}
