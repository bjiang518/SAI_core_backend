//
//  VoiceSettingsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/8/25.
//

import SwiftUI

struct VoiceSettingsView: View {
    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var tempSettings: VoiceSettings
    @State private var showingPreview = false
    @Environment(\.dismiss) private var dismiss
    
    init() {
        let currentSettings = VoiceInteractionService.shared.voiceSettings
        _tempSettings = State(initialValue: currentSettings)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Voice Type Selection
                    voiceTypeSection
                    
                    // Voice Controls
                    voiceControlsSection
                    
                    // Auto-Speak Settings
                    autoSpeakSection
                    
                    // Voice Preview
                    voicePreviewSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
        }
    }
    
    // MARK: - Voice Type Section
    
    private var voiceTypeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("AI Voice Personality", icon: "person.wave.2.fill")
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(VoiceType.allCases, id: \.self) { voiceType in
                    VoiceTypeCard(
                        voiceType: voiceType,
                        isSelected: tempSettings.voiceType == voiceType,
                        onSelect: {
                            tempSettings.voiceType = voiceType
                            playPreview(for: voiceType)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Voice Controls Section
    
    private var voiceControlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Voice Controls", icon: "slider.horizontal.3")
            
            VStack(spacing: 20) {
                // Speaking Rate
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speaking Speed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text(speedLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "tortoise.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Slider(value: $tempSettings.speakingRate, in: 0.25...1.0) {
                            Text("Speaking Rate")
                        } minimumValueLabel: {
                            EmptyView()
                        } maximumValueLabel: {
                            EmptyView()
                        }
                        .tint(.blue)
                        .onChange(of: tempSettings.speakingRate) { _ in
                            // Provide real-time feedback for rate changes
                            playQuickPreview()
                        }
                        
                        Image(systemName: "hare.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                // Voice Pitch
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Voice Pitch")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text(pitchLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Slider(value: $tempSettings.voicePitch, in: 0.7...1.3) {
                            Text("Voice Pitch")
                        } minimumValueLabel: {
                            EmptyView()
                        } maximumValueLabel: {
                            EmptyView()
                        }
                        .tint(.blue)
                        .onChange(of: tempSettings.voicePitch) { _ in
                            // Provide real-time feedback for pitch changes
                            playQuickPreview()
                        }
                        
                        Image(systemName: "arrow.up")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                
                // Volume
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(tempSettings.volume * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Slider(value: $tempSettings.volume, in: 0.3...1.0) {
                            Text("Volume")
                        } minimumValueLabel: {
                            EmptyView()
                        } maximumValueLabel: {
                            EmptyView()
                        }
                        .tint(.blue)
                        .onChange(of: tempSettings.volume) { _ in
                            // Provide real-time feedback for volume changes
                            playQuickPreview()
                        }
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    // MARK: - Auto-Speak Section
    
    private var autoSpeakSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Auto-Speak Settings", icon: "autostartstop.trianglebadge.exclamationmark")
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-Speak AI Responses")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Automatically read AI responses aloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $tempSettings.autoSpeakResponses)
                        .tint(.blue)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Voice Preview Section
    
    private var voicePreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Voice Preview", icon: "play.circle.fill")
            
            VStack(spacing: 12) {
                Text("Tap to hear how your AI assistant will sound with these settings:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: playCurrentPreview) {
                    HStack {
                        Image(systemName: showingPreview ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        
                        Text(showingPreview ? "Stop Preview" : "Play Preview")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }
                .disabled(!voiceService.isVoiceEnabled)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var speedLabel: String {
        switch tempSettings.speakingRate {
        case 0.25..<0.4:
            return "Very Slow"
        case 0.4..<0.6:
            return "Slow"
        case 0.6..<0.8:
            return "Normal"
        case 0.8..<0.95:
            return "Fast"
        default:
            return "Very Fast"
        }
    }
    
    private var pitchLabel: String {
        switch tempSettings.voicePitch {
        case 0.7..<0.9:
            return "Low"
        case 0.9..<1.1:
            return "Normal"
        case 1.1...1.3:
            return "High"
        default:
            return "Normal"
        }
    }
    
    private var hasChanges: Bool {
        tempSettings.voiceType != voiceService.voiceSettings.voiceType ||
        abs(tempSettings.speakingRate - voiceService.voiceSettings.speakingRate) > 0.01 ||
        abs(tempSettings.voicePitch - voiceService.voiceSettings.voicePitch) > 0.01 ||
        abs(tempSettings.volume - voiceService.voiceSettings.volume) > 0.01 ||
        tempSettings.autoSpeakResponses != voiceService.voiceSettings.autoSpeakResponses
    }
    
    // MARK: - Actions
    
    private func playPreview(for voiceType: VoiceType) {
        let previewText = voiceService.getVoicePreview(for: voiceType)
        let previewSettings = VoiceSettings(
            voiceType: voiceType,
            speakingRate: tempSettings.speakingRate,
            voicePitch: tempSettings.voicePitch,
            autoSpeakResponses: tempSettings.autoSpeakResponses,
            language: tempSettings.language,
            volume: tempSettings.volume,
            useEnhancedVoices: tempSettings.useEnhancedVoices,
            expressiveness: tempSettings.expressiveness
        )
        
        // Stop any current speech first
        voiceService.stopSpeech()
        
        // Use preview settings directly without temporarily changing service settings
        if voiceService.shouldUseEnhancedTTS(for: voiceType) {
            let enhancedTTS = EnhancedTTSService()
            enhancedTTS.speak(previewText, with: previewSettings)
        } else {
            let systemTTS = TextToSpeechService()
            systemTTS.speak(previewText, with: previewSettings)
        }
    }
    
    private func playCurrentPreview() {
        if showingPreview {
            voiceService.stopSpeech()
            showingPreview = false
        } else {
            let previewText = voiceService.getVoicePreview(for: tempSettings.voiceType)
            
            // Stop any current speech first
            voiceService.stopSpeech()
            
            // Use preview settings directly without changing service settings
            if voiceService.shouldUseEnhancedTTS(for: tempSettings.voiceType) {
                let enhancedTTS = EnhancedTTSService()
                enhancedTTS.speak(previewText, with: tempSettings)
            } else {
                let systemTTS = TextToSpeechService()
                systemTTS.speak(previewText, with: tempSettings)
            }
            
            showingPreview = true
            
            // Auto-hide after estimated duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                showingPreview = false
            }
        }
    }
    
    @State private var previewDebounceTask: Task<Void, Never>?
    
    private func playQuickPreview() {
        // Cancel previous debounce task
        previewDebounceTask?.cancel()
        
        // Create new debounced task
        previewDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // Quick preview with short text
                let quickText = "Hello!"
                
                // Stop any current speech
                voiceService.stopSpeech()
                
                // Use current temp settings for immediate feedback
                if voiceService.shouldUseEnhancedTTS(for: tempSettings.voiceType) {
                    let enhancedTTS = EnhancedTTSService()
                    enhancedTTS.speak(quickText, with: tempSettings)
                } else {
                    let systemTTS = TextToSpeechService()
                    systemTTS.speak(quickText, with: tempSettings)
                }
            }
        }
    }
    
    private func saveSettings() {
        voiceService.updateVoiceSettings(tempSettings)
        dismiss()
    }
}

// MARK: - Voice Type Card

struct VoiceTypeCard: View {
    let voiceType: VoiceType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: voiceType.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                
                // Title
                Text(voiceType.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                
                // Description
                Text(voiceType.description)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VoiceSettingsView()
}