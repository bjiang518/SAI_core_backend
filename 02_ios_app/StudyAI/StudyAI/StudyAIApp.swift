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
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    init() {
        setupGoogleSignIn()
        setupLanguage()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: appLanguage))
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }

    private func setupLanguage() {
        // Apply the selected language preference
        UserDefaults.standard.set([appLanguage], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    private func setupGoogleSignIn() {

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
    }
}
