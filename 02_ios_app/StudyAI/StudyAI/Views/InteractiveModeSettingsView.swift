//
//  InteractiveModeSettingsView.swift
//  StudyAI
//
//  Settings UI for Interactive Mode
//  Phase 3: iOS AVAudioEngine Integration
//
//  Allows users to control when real-time synchronized TTS is enabled
//

import SwiftUI

struct InteractiveModeSettingsView: View {
    @State private var settings = InteractiveModeSettings.load()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // Main toggle
                Section {
                    Toggle("Enable Interactive Mode", isOn: $settings.isEnabled)
                        .onChange(of: settings.isEnabled) { _, _ in
                            settings.save()
                            AppLogger.debug("💾 Interactive mode toggled: \(settings.isEnabled)")
                        }
                } header: {
                    Text("Interactive Mode")
                } footer: {
                    Text("When enabled, AI responses will play audio in real-time as text appears. This uses more data and may increase costs slightly.")
                }

                // Auto-enable conditions (only show if enabled)
                if settings.isEnabled {
                    Section {
                        Toggle("Auto-enable for short queries", isOn: $settings.autoEnableForShortQueries)
                            .onChange(of: settings.autoEnableForShortQueries) { _, _ in
                                settings.save()
                            }

                        if settings.autoEnableForShortQueries {
                            HStack {
                                Text("Short query threshold")
                                Spacer()
                                Text("\(settings.shortQueryThreshold) characters")
                                    .foregroundColor(.secondary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(settings.shortQueryThreshold) },
                                    set: { settings.shortQueryThreshold = Int($0) }
                                ),
                                in: 50...500,
                                step: 50
                            )
                            .onChange(of: settings.shortQueryThreshold) { _, _ in
                                settings.save()
                            }
                        }
                    } header: {
                        Text("Auto-Enable")
                    } footer: {
                        Text("Automatically use interactive mode for short queries to provide quick, natural responses.")
                    }

                    // Auto-disable conditions
                    Section {
                        Toggle("Disable for deep thinking mode", isOn: $settings.disableForDeepMode)
                            .onChange(of: settings.disableForDeepMode) { _, _ in
                                settings.save()
                            }

                        Toggle("Disable for image queries", isOn: $settings.disableForImages)
                            .onChange(of: settings.disableForImages) { _, _ in
                                settings.save()
                            }

                        Toggle("Disable for long responses", isOn: $settings.disableForLongResponses)
                            .onChange(of: settings.disableForLongResponses) { _, _ in
                                settings.save()
                            }

                        if settings.disableForLongResponses {
                            HStack {
                                Text("Long response threshold")
                                Spacer()
                                Text("\(settings.longResponseThreshold) characters")
                                    .foregroundColor(.secondary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(settings.longResponseThreshold) },
                                    set: { settings.longResponseThreshold = Int($0) }
                                ),
                                in: 500...2000,
                                step: 100
                            )
                            .onChange(of: settings.longResponseThreshold) { _, _ in
                                settings.save()
                            }
                        }
                    } header: {
                        Text("Auto-Disable")
                    } footer: {
                        Text("Interactive mode will be automatically disabled for:\n• Deep thinking mode (takes too long)\n• Image queries (vision processing delays)\n• Long responses (better to read and study)")
                    }

                    // Information section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(
                                icon: "waveform",
                                title: "Real-time Audio",
                                description: "Hear AI responses as they're being generated"
                            )

                            Divider()

                            InfoRow(
                                icon: "bolt.fill",
                                title: "Low Latency",
                                description: "Typical time-to-first-audio: <800ms"
                            )

                            Divider()

                            InfoRow(
                                icon: "chart.bar.fill",
                                title: "Data Usage",
                                description: "~0.5-1.0 MB audio per interactive session"
                            )

                            Divider()

                            InfoRow(
                                icon: "dollarsign.circle.fill",
                                title: "Cost Impact",
                                description: "~$0.001 per interactive session"
                            )
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("About Interactive Mode")
                    }
                }
            }
            .navigationTitle("Interactive Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    InteractiveModeSettingsView()
}
