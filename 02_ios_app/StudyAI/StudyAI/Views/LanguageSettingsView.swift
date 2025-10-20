//
//  LanguageSettingsView.swift
//  StudyAI
//
//  Language selection settings
//

import SwiftUI

struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var selectedLanguage: String = "en"
    @State private var showRestartAlert = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(Language.allLanguages) { language in
                        Button(action: {
                            if selectedLanguage != language.code {
                                selectedLanguage = language.code
                                showRestartAlert = true
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(language.nativeName)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(language.englishName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedLanguage == language.code {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .font(.body.weight(.semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Select Language")
                } footer: {
                    Text("Choose your preferred language for the app interface. This will affect all text in the app.")
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Restart Required", isPresented: $showRestartAlert) {
                Button("OK") {
                    // User acknowledged the restart requirement
                }
            } message: {
                Text("Please close and reopen the app for the language change to take full effect.")
            }
        }
    }
}

// MARK: - Language Model

struct Language: Identifiable {
    let id: String
    let code: String
    let englishName: String
    let nativeName: String
    let flag: String

    static let allLanguages: [Language] = [
        Language(
            id: "en",
            code: "en",
            englishName: "English",
            nativeName: "English",
            flag: "🇺🇸"
        ),
        Language(
            id: "zh-Hans",
            code: "zh-Hans",
            englishName: "Chinese (Simplified)",
            nativeName: "简体中文",
            flag: "🇨🇳"
        ),
        Language(
            id: "zh-Hant",
            code: "zh-Hant",
            englishName: "Chinese (Traditional)",
            nativeName: "繁體中文",
            flag: "🇹🇼"
        )
    ]
}

#Preview {
    LanguageSettingsView()
}