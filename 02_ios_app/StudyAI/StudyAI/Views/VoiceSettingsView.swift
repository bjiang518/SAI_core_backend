//
//  VoiceSettingsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/8/25.
//

import SwiftUI
import Lottie

struct VoiceSettingsView: View {
    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var tempSettings: VoiceSettings
    @State private var showingPreview = false
    @State private var interactiveModeSettings = InteractiveModeSettings.load()
    @Environment(\.dismiss) private var dismiss
    
    init() {
        let currentSettings = VoiceInteractionService.shared.voiceSettings
        _tempSettings = State(initialValue: currentSettings)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Audio toggles (enable / sync)
                    audioConfigSection

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
            .navigationTitle(NSLocalizedString("chat.menu.audioConfig", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.save", comment: "")) {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Audio Config Section

    private var audioConfigSection: some View {
        VStack(spacing: 12) {
            // Enable Audio row
            HStack {
                Text(NSLocalizedString("chat.menu.voice", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Picker("", selection: Binding(
                    get: { voiceService.isVoiceEnabled },
                    set: { newValue in
                        if newValue != voiceService.isVoiceEnabled {
                            voiceService.toggleVoiceEnabled()
                        }
                    }
                )) {
                    Text(NSLocalizedString("common.yes", comment: "")).tag(true)
                    Text(NSLocalizedString("common.no", comment: "")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Sync with Text row
            HStack {
                Text(NSLocalizedString("chat.menu.syncWithText", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Picker("", selection: $interactiveModeSettings.isEnabled) {
                    Text(NSLocalizedString("common.yes", comment: "")).tag(true)
                    Text(NSLocalizedString("common.no", comment: "")).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: interactiveModeSettings.isEnabled) { _, _ in
                    interactiveModeSettings.save()
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Voice Type Section

    private var voiceTypeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(NSLocalizedString("chat.menu.aiMate", comment: ""), icon: "person.crop.circle")
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(VoiceType.allCases, id: \.self) { voiceType in
                    VoiceTypeCard(
                        voiceType: voiceType,
                        isSelected: tempSettings.voiceType == voiceType,
                        onSelect: {
                            voiceService.stopSpeech()
                            showingPreview = false
                            tempSettings.voiceType = voiceType
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Voice Controls Section

    private var voiceControlsSection: some View {
        // Assign colors based on voice character
        let voiceColor: Color = {
            switch tempSettings.voiceType {
            case .adam:
                return Color.blue
            case .eva:
                return Color.purple
            case .max:
                return Color.orange
            case .mia:
                return Color.pink
            }
        }()

        return VStack(alignment: .leading, spacing: 16) {
            sectionHeader(NSLocalizedString("voiceSettings.voiceControls", comment: ""), icon: "slider.horizontal.3")

            VStack(spacing: 20) {
                // Speaking Rate
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("voiceSettings.speakingSpeed", comment: ""))
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

                        Slider(value: $tempSettings.speakingRate, in: 0.7...1.2) {
                        Text(NSLocalizedString("voiceSettings.speakingRate", comment: ""))
                        } minimumValueLabel: {
                            EmptyView()
                        } maximumValueLabel: {
                            EmptyView()
                        }
                        .tint(voiceColor)

                        Image(systemName: "hare.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // Stability
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("voiceSettings.stability", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text(stabilityLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "waveform.path")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Slider(value: $tempSettings.stability, in: 0.0...1.0) {
                            Text(NSLocalizedString("voiceSettings.stability", comment: ""))
                        } minimumValueLabel: {
                            EmptyView()
                        } maximumValueLabel: {
                            EmptyView()
                        }
                        .tint(voiceColor)

                        Image(systemName: "waveform")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // Style
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("voiceSettings.style", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text(styleLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "theatermasks")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Slider(value: $tempSettings.style, in: 0.0...1.0) {
                            Text(NSLocalizedString("voiceSettings.style", comment: ""))
                        } minimumValueLabel: {
                            EmptyView()
                        } maximumValueLabel: {
                            EmptyView()
                        }
                        .tint(voiceColor)

                        Image(systemName: "theatermasks.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // Volume
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("voiceSettings.volume", comment: ""))
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
                            Text(NSLocalizedString("voiceSettings.volume", comment: ""))
                        } minimumValueLabel: {
                            EmptyView()
                        } maximumValueLabel: {
                            EmptyView()
                        }
                        .tint(voiceColor)

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
        let voiceColor = tempSettings.voiceType == .adam ? Color.blue : Color.purple

        return VStack(alignment: .leading, spacing: 16) {
            sectionHeader(NSLocalizedString("voiceSettings.autoSpeakSettings", comment: ""), icon: "autostartstop.trianglebadge.exclamationmark")

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("voiceSettings.autoSpeakResponses", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(NSLocalizedString("voiceSettings.autoSpeakDesc", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $tempSettings.autoSpeakResponses)
                        .tint(voiceColor)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Voice Preview Section

    private var voicePreviewSection: some View {
        let voiceColor = tempSettings.voiceType == .adam ? Color.blue : Color.purple

        return VStack(alignment: .leading, spacing: 16) {
            sectionHeader(NSLocalizedString("voiceSettings.voicePreview", comment: ""), icon: "play.circle.fill")

            VStack(spacing: 12) {
                Text(NSLocalizedString("voiceSettings.previewHint", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: playCurrentPreview) {
                    HStack {
                        Image(systemName: showingPreview ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)

                        Text(showingPreview ? NSLocalizedString("voiceSettings.stopPreview", comment: "") : NSLocalizedString("voiceSettings.playPreview", comment: ""))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(voiceColor.opacity(0.1))
                    .foregroundColor(voiceColor)
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
        case 0.7..<0.82:
            return NSLocalizedString("voiceSettings.speed.slow", comment: "")
        case 0.82..<0.95:
            return NSLocalizedString("voiceSettings.speed.normal", comment: "")
        case 0.95..<1.08:
            return NSLocalizedString("voiceSettings.speed.fast", comment: "")
        default:
            return NSLocalizedString("voiceSettings.speed.veryFast", comment: "")
        }
    }

    private var stabilityLabel: String {
        switch tempSettings.stability {
        case 0.0..<0.35: return NSLocalizedString("voiceSettings.stability.variable", comment: "")
        case 0.35..<0.65: return NSLocalizedString("voiceSettings.stability.balanced", comment: "")
        default: return NSLocalizedString("voiceSettings.stability.stable", comment: "")
        }
    }

    private var styleLabel: String {
        switch tempSettings.style {
        case 0.0..<0.15: return NSLocalizedString("voiceSettings.style.neutral", comment: "")
        case 0.15..<0.4: return NSLocalizedString("voiceSettings.style.expressive", comment: "")
        default: return NSLocalizedString("voiceSettings.style.bold", comment: "")
        }
    }

    private var hasChanges: Bool {
        tempSettings.voiceType != voiceService.voiceSettings.voiceType ||
        abs(tempSettings.speakingRate - voiceService.voiceSettings.speakingRate) > 0.01 ||
        abs(tempSettings.volume - voiceService.voiceSettings.volume) > 0.01 ||
        abs(tempSettings.stability - voiceService.voiceSettings.stability) > 0.01 ||
        abs(tempSettings.style - voiceService.voiceSettings.style) > 0.01 ||
        tempSettings.autoSpeakResponses != voiceService.voiceSettings.autoSpeakResponses
    }
    
    // MARK: - Actions
    

    private func playCurrentPreview() {
        if showingPreview {
            voiceService.stopSpeech()
            showingPreview = false
        } else {
            let previewText = voiceService.getVoicePreview(for: tempSettings.voiceType)
            voiceService.previewVoice(text: previewText, with: tempSettings)
            showingPreview = true

            // Auto-reset the play/stop state after estimated duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                showingPreview = false
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

    // Dynamic color based on voice type
    private var cardColor: Color {
        switch voiceType {
        case .adam:
            return Color.blue
        case .eva:
            return Color.purple
        case .max:
            return Color.orange
        case .mia:
            return Color.pink
        }
    }

    // Animation name based on voice type
    private var animationName: String {
        switch voiceType {
        case .adam:
            return "Siri Animation"
        case .eva:
            return "AI Spiral Loading"
        case .max:
            return "Fire"
        case .mia:
            return "Foriday"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Lottie Animation Icon
                LottieView(
                    animationName: animationName,
                    loopMode: .loop,
                    animationSpeed: 1.0
                )
                .frame(width: 80, height: 80)
                .scaleEffect(0.08)
                .clipped()

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
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 140)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? cardColor : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? cardColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VoiceSettingsView()
}