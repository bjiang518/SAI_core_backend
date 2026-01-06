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
    @StateObject private var deepLinkHandler = PomodoroDeepLinkHandler.shared

    init() {
        // ✅ TODO: For cleaner console logs, add to Xcode scheme:
        // Edit Scheme → Run → Arguments → Environment Variables:
        // OS_ACTIVITY_MODE = disable
        //
        // AppLogger.setupConsoleFiltering()  // Uncomment after Xcode reindex

        setupGoogleSignIn()
        setupLanguage()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: appLanguage))
                .environmentObject(deepLinkHandler)
                .onOpenURL { url in
                    // 处理Google登录
                    GIDSignIn.sharedInstance.handle(url)

                    // 处理番茄专注Deep Link
                    if url.scheme == "studyai" {
                        deepLinkHandler.handleDeepLink(url: url)
                    }
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
