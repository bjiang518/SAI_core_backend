//
//  StudyAIApp.swift
//  StudyAI
//
//  Created by Bo Jiang on 8/28/25.
//

import SwiftUI
import GoogleSignIn
import BackgroundTasks

@main
struct StudyAIApp: App {
    @AppStorage("appLanguage") private var appLanguage: String = LanguageManager.detectedSystemLanguage()
    @StateObject private var deepLinkHandler = PomodoroDeepLinkHandler.shared
    @StateObject private var themeManager = ThemeManager.shared

    init() {
        // ✅ TODO: For cleaner console logs, add to Xcode scheme:
        // Edit Scheme → Run → Arguments → Environment Variables:
        // OS_ACTIVITY_MODE = disable
        //
        // AppLogger.setupConsoleFiltering()  // Uncomment after Xcode reindex

        setupGoogleSignIn()
        LanguageManager.shared.setup()
        registerBackgroundTasks()  // ✅ Register background tasks early
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: appLanguage))
                .environmentObject(deepLinkHandler)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
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

    private func setupGoogleSignIn() {

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
    }

    // MARK: - Background Task Registration

    /// Register background tasks for weakness migration
    /// Must be called before application:didFinishLaunchingWithOptions: completes
    private func registerBackgroundTasks() {
        #if !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.studyai.weaknessmigration",
            using: nil
        ) { task in
            Task {
                await ShortTermStatusService.shared.performDailyWeaknessMigration()
                task.setTaskCompleted(success: true)
            }
            ShortTermStatusService.shared.scheduleNextBackgroundMigration()
        }
        print("✅ [App] Background task registered: com.studyai.weaknessmigration")
        #else
        print("⚠️ [App] Background tasks disabled in simulator")
        #endif
    }
}
