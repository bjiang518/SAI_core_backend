//
//  CameraSessionManager.swift
//  StudyAI
//
//  Enhanced camera session management to prevent camera errors
//

import Foundation
import AVFoundation
import UIKit
import os.log
import Combine

class CameraSessionManager: NSObject, ObservableObject {
    static let shared = CameraSessionManager()
    
    private let logger = Logger(subsystem: "com.studyai", category: "CameraSession")
    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    // Camera state tracking
    @Published var isCameraAvailable = false
    @Published var cameraAuthStatus: AVAuthorizationStatus = .notDetermined
    
    // Error recovery and session tracking
    private var errorCount = 0
    private let maxErrorRetries = 3
    private var sessionCreationTime: Date?
    private var sessionId = UUID()
    
    // Debug tracking for error analysis
    private var lastErrorCode: Int?
    private var lastErrorTime: Date?
    private var consecutiveErrors = 0
    
    override init() {
        super.init()
        checkCameraAuthorization()
        setupSessionNotifications()
    }
    
    // MARK: - Camera Authorization
    
    func checkCameraAuthorization() {
        cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch cameraAuthStatus {
        case .authorized:
            isCameraAvailable = true
            logger.info("Camera access authorized")
        case .notDetermined:
            requestCameraPermission()
        case .denied, .restricted:
            isCameraAvailable = false
            logger.warning("Camera access denied or restricted")
        @unknown default:
            isCameraAvailable = false
            logger.error("Unknown camera authorization status")
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.cameraAuthStatus = granted ? .authorized : .denied
                self?.isCameraAvailable = granted
                
                if granted {
                    self?.logger.info("Camera permission granted")
                } else {
                    self?.logger.warning("Camera permission denied")
                }
            }
        }
    }
    
    // MARK: - Session Management
    
    private func setupSessionNotifications() {
        // NOTE: We intentionally do NOT register for AVCaptureSession notifications
        // with object: nil here. When using VNDocumentCameraViewController, we don't
        // own the AVCaptureSession — the native scanner manages its own. Listening to
        // all sessions (object: nil) would intercept the scanner's internal events,
        // trigger error recovery / @Published updates, cause SwiftUI re-renders, and
        // block touch events on the native Save/Keep buttons.
        //
        // If we ever create our own AVCaptureSession, register observers scoped to
        // that specific session instance (object: captureSession).
    }
    
    @objc private func sessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            logger.error("🚨 Camera runtime error notification with no error object")
            return
        }
        
        let errorCode = error.code.rawValue
        let now = Date()
        
        // Enhanced debug logging for error analysis
        logger.error("🚨 === CAMERA SESSION RUNTIME ERROR ===")
        logger.error("🔍 Session ID: \(self.sessionId.uuidString.prefix(8))")
        logger.error("🔍 Error Code: \(errorCode) (\(String(describing: error.code)))")
        logger.error("🔍 Error Description: \(error.localizedDescription)")
        logger.error("🔍 User Info: \(String(describing: error.userInfo))")
        
        if let sessionTime = sessionCreationTime {
            let sessionDuration = now.timeIntervalSince(sessionTime)
            logger.error("🔍 Session Duration: \(String(format: "%.2f", sessionDuration))s")
        }
        
        // Track consecutive errors
        if let lastCode = lastErrorCode, lastCode == errorCode, let lastTime = lastErrorTime {
            let timeSinceLastError = now.timeIntervalSince(lastTime)
            consecutiveErrors += 1
            logger.error("🔍 Consecutive Error #\(self.consecutiveErrors), Time Since Last: \(String(format: "%.2f", timeSinceLastError))s")
        } else {
            consecutiveErrors = 1
        }
        
        lastErrorCode = errorCode
        lastErrorTime = now
        
        // Enhanced error handling with specific logging for known issues
        switch error.code {
        case .deviceInUseByAnotherApplication:
            logger.warning("📱 Camera in use by another app - attempting recovery")
            recoverFromCameraError()
        case .deviceNotConnected:
            logger.error("🔌 Camera device not connected")
        default:
            // Log specific error codes we're tracking
            if errorCode == -17281 {
                logger.error("❌ -17281 ERROR: FigCaptureSource Set(Clock) failed - camera synchronization issue")
                logger.error("🔍 This indicates iOS internal camera framework clock sync failure")
            } else if errorCode == -12710 {
                logger.error("❌ -12710 ERROR: Camera hardware communication failure")
            }
            logger.error("🔄 Attempting error recovery for code \(errorCode)")
            recoverFromCameraError()
        }
        
        logger.error("============================================")
    }
    
    @objc private func sessionWasInterrupted(notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue) else {
            return
        }
        
        logger.info("Camera session interrupted: \(reason.rawValue)")
        
        switch reason {
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
            logger.warning("Camera/audio device in use by another client")
        case .videoDeviceNotAvailableInBackground:
            logger.info("Camera not available in background")
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            logger.warning("Camera not available with multiple foreground apps")
        case .videoDeviceNotAvailableDueToSystemPressure:
            logger.warning("Camera not available due to system pressure")
        case .sensitiveContentMitigationActivated:
            logger.warning("Sensitive content mitigation activated")
        @unknown default:
            logger.warning("Unknown interruption reason")
        }
    }
    
    @objc private func sessionInterruptionEnded(notification: Notification) {
        logger.info("Camera session interruption ended")
        
        // Reset error count on successful recovery
        errorCount = 0
    }
    
    private func recoverFromCameraError() {
        guard errorCount < maxErrorRetries else {
            logger.error("Max camera error retries exceeded")
            return
        }
        
        errorCount += 1
        
        sessionQueue.async { [weak self] in
            // Stop current session
            self?.captureSession?.stopRunning()
            
            // Small delay before retry
            Thread.sleep(forTimeInterval: 0.5)
            
            // Clear session
            self?.captureSession = nil
            
            // Attempt to restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.logger.info("Attempting camera session recovery")
            }
        }
    }
    
    // MARK: - Public Interface
    
    func prepareForCameraUsage() {
        let newSessionId = UUID()
        sessionId = newSessionId
        sessionCreationTime = Date()

        guard isCameraAvailable else {
            logger.warning("❌ Camera not available for usage - auth status: \(self.cameraAuthStatus.rawValue)")
            return
        }

        logger.info("🔄 === PREPARING CAMERA FOR USAGE ===")
        logger.info("🆔 New Session ID: \(newSessionId.uuidString.prefix(8))")

        // OPTIMIZED: Async cleanup without blocking main thread
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if let existingSession = self.captureSession {
                self.logger.info("⚠️ Found existing session - cleaning up")

                if existingSession.isRunning {
                    existingSession.stopRunning()
                }

                // Quick cleanup without detailed logging
                for input in existingSession.inputs {
                    existingSession.removeInput(input)
                }
                for output in existingSession.outputs {
                    existingSession.removeOutput(output)
                }

                self.captureSession = nil
            }

            // Reset error state
            self.errorCount = 0
            self.lastErrorCode = nil
            self.lastErrorTime = nil
            self.consecutiveErrors = 0

            self.logger.info("✅ Camera prepared")
        }
    }
    
    func cleanupAfterCameraUsage() {
        let cleanupStartTime = Date()
        
        logger.info("🧹 === STARTING ENHANCED CAMERA CLEANUP ===")
        logger.info("🆔 Session ID: \(self.sessionId.uuidString.prefix(8))")
        
        if let sessionTime = sessionCreationTime {
            let sessionDuration = Date().timeIntervalSince(sessionTime)
            logger.info("⏱️ Session Duration: \(String(format: "%.2f", sessionDuration))s")
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else {
                Logger(subsystem: "com.studyai", category: "CameraSession").warning("⚠️ Self deallocated during cleanup")
                return
            }
            
            // Force stop any running session with detailed logging
            if let session = self.captureSession {
                self.logger.info("📊 Session state before cleanup:")
                self.logger.info("   - Running: \(session.isRunning)")
                self.logger.info("   - Inputs: \(session.inputs.count)")
                self.logger.info("   - Outputs: \(session.outputs.count)")
                
                if session.isRunning {
                    self.logger.info("⏹️ Stopping running camera session...")
                    session.stopRunning()
                    
                    // Wait for session to fully stop
                    var attempts = 0
                    while session.isRunning && attempts < 10 {
                        Thread.sleep(forTimeInterval: 0.1)
                        attempts += 1
                    }
                    
                    if session.isRunning {
                        self.logger.error("❌ Session still running after \(attempts) attempts")
                    } else {
                        self.logger.info("✅ Session stopped after \(attempts * 100)ms")
                    }
                }
                
                // Remove all inputs and outputs with detailed logging
                let inputCount = session.inputs.count
                let outputCount = session.outputs.count
                
                self.logger.info("🔌 Removing \(inputCount) inputs...")
                for (index, input) in session.inputs.enumerated() {
                    self.logger.info("   [\(index + 1)/\(inputCount)] Removing: \(type(of: input))")
                    session.removeInput(input)
                }
                
                self.logger.info("📤 Removing \(outputCount) outputs...")
                for (index, output) in session.outputs.enumerated() {
                    self.logger.info("   [\(index + 1)/\(outputCount)] Removing: \(type(of: output))")
                    session.removeOutput(output)
                }
                
                self.logger.info("🗑️ All inputs and outputs removed")
            } else {
                self.logger.info("ℹ️ No active session to cleanup")
            }
            
            // Clear session reference
            self.captureSession = nil
            
            // Reset error state with logging
            let previousErrorCount = self.errorCount
            self.errorCount = 0
            self.lastErrorCode = nil
            self.lastErrorTime = nil
            self.consecutiveErrors = 0
            
            self.logger.info("🧹 Error state reset - previous errors: \(previousErrorCount)")
            
            let cleanupDuration = Date().timeIntervalSince(cleanupStartTime)
            
            DispatchQueue.main.async {
                self.logger.info("✅ === ENHANCED CAMERA CLEANUP COMPLETED ===")
                self.logger.info("⏱️ Cleanup Duration: \(String(format: "%.3f", cleanupDuration))s")
                self.logger.info("=================================================")
            }
        }
    }
    
    /// Force immediate session termination when view closes
    func terminateSessionOnViewClose() {
        logger.info("🚪 === VIEW CLOSING - TERMINATING SESSION ===")
        logger.info("🆔 Session ID: \(self.sessionId.uuidString.prefix(8))")
        
        sessionQueue.sync {
            if let session = captureSession {
                logger.info("🛑 FORCE TERMINATING active session")
                
                if session.isRunning {
                    session.stopRunning()
                    logger.info("⏹️ Session stopped immediately")
                }
                
                // Immediate cleanup without delays
                for input in session.inputs {
                    session.removeInput(input)
                }
                for output in session.outputs {
                    session.removeOutput(output)
                }
                
                captureSession = nil
                logger.info("💀 Session terminated and cleared")
            }
        }
        
        // Reset all state
        errorCount = 0
        lastErrorCode = nil
        lastErrorTime = nil
        consecutiveErrors = 0
        sessionCreationTime = nil
        
        logger.info("✅ VIEW CLOSE TERMINATION COMPLETE")
    }
    
    /// Enhanced recovery method for -17281 camera session errors
    func recoverFromSessionError() {
        logger.info("🔄 Attempting recovery from camera session error (-17281)")
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Force complete session teardown
            self.captureSession?.stopRunning()
            self.captureSession = nil
            
            // Wait for session cleanup
            Thread.sleep(forTimeInterval: 0.8)
            
            // Reset error state
            self.errorCount = 0
            
            DispatchQueue.main.async {
                self.logger.info("✅ Camera session recovery completed")
                
                // Recheck availability after recovery
                self.checkCameraAuthorization()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupAfterCameraUsage()
    }
}