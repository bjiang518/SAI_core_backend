//
//  LocationPickerSheet.swift
//  StudyAI
//

import SwiftUI

/// A searchable full-screen picker for selecting a location item (country or state).
struct LocationPickerSheet: View {
    let title: String
    /// Each item is (key, displayName). For countries: (ISO code, localized name).
    /// For states: (name, name).
    let items: [(key: String, label: String)]
    /// The currently selected key (used to show a checkmark).
    let selectedKey: String
    /// Called when the user taps an item. Passes (key, label).
    let onSelect: (String, String) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [(key: String, label: String)] {
        if searchText.isEmpty { return items }
        return items.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.key) { item in
                Button {
                    onSelect(item.key, item.label)
                } label: {
                    HStack {
                        Text(item.label)
                            .foregroundColor(.primary)
                        Spacer()
                        if item.key == selectedKey {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", value: "Cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
