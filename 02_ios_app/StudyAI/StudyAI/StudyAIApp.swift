//
//  StudyAIApp.swift
//  StudyAI
//
//  Created by Bo Jiang on 8/28/25.
//

import SwiftUI
import GoogleSignIn
import os.log

@main
struct StudyAIApp: App {
    private let startupLogger = Logger(subsystem: "com.studyai", category: "AppStartup")
    
    init() {
        let startTime = CFAbsoluteTimeGetCurrent()
        startupLogger.info("🚀 === APP INITIALIZATION STARTED ===")
        startupLogger.info("🚀 App init() began at: \(startTime)")
        
        // Log critical initialization steps
        setupGoogleSignIn()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let initDuration = endTime - startTime
        startupLogger.info("🚀 App init() completed in: \(initDuration * 1000, privacy: .public) ms")
        startupLogger.info("🚀 === APP INITIALIZATION FINISHED ===")
    }
    
    var body: some Scene {
        startupLogger.info("🏗️ === APP BODY BUILDING ===")
        let bodyStartTime = CFAbsoluteTimeGetCurrent()
        
        return WindowGroup {
            ContentView()
                .onAppear {
                    let totalStartupTime = CFAbsoluteTimeGetCurrent() - bodyStartTime
                    startupLogger.info("📱 === CONTENT VIEW APPEARED ===")
                    startupLogger.info("📱 Total time from body to ContentView.onAppear: \(totalStartupTime * 1000, privacy: .public) ms")
                }
                .onOpenURL { url in
                    startupLogger.info("🔗 Handling URL: \(url.absoluteString)")
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
    
    private func setupGoogleSignIn() {
        let googleStartTime = CFAbsoluteTimeGetCurrent()
        startupLogger.info("🔧 Setting up Google Sign-In...")
        
        // Google Sign-In configuration could be blocking
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
            
            let googleEndTime = CFAbsoluteTimeGetCurrent()
            let googleDuration = googleEndTime - googleStartTime
            startupLogger.info("✅ Google Sign-In setup completed in: \(googleDuration * 1000, privacy: .public) ms")
        } else {
            startupLogger.error("❌ Failed to configure Google Sign-In - GoogleService-Info.plist not found")
        }
    }
}
