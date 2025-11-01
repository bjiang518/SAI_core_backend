//
//  PlaylistEditorView.swift
//  StudyAI
//
//  View for creating and editing music playlists
//

import SwiftUI

struct PlaylistEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var musicService = BackgroundMusicService.shared

    let playlistToEdit: MusicPlaylist?
    let onSave: (MusicPlaylist) -> Void

    @State private var playlistName: String = ""
    @State private var selectedTrackIds: Set<String> = []
    @State private var showNameError = false

    // Initializer for creating new playlist
    init(onSave: @escaping (MusicPlaylist) -> Void) {
        self.playlistToEdit = nil
        self.onSave = onSave
    }

    // Initializer for editing existing playlist
    init(playlist: MusicPlaylist, onSave: @escaping (MusicPlaylist) -> Void) {
        self.playlistToEdit = playlist
        self.onSave = onSave
        _playlistName = State(initialValue: playlist.name)
        _selectedTrackIds = State(initialValue: Set(playlist.trackIds))
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ?
                    Color(red: 0.05, green: 0.05, blue: 0.1) :
                    Color(red: 0.95, green: 0.97, blue: 1.0))
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Playlist Name Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("focus.playlistName", comment: "Playlist Name"))
                                .font(.headline)
                                .foregroundColor(colorScheme == .dark ? .white : .primary)

                            TextField(NSLocalizedString("focus.enterPlaylistName", comment: "Enter playlist name..."), text: $playlistName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(12)
                                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                                .cornerRadius(12)

                            if showNameError {
                                Text(NSLocalizedString("focus.playlistNameRequired", comment: "Playlist name is required"))
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // Track Selection Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(NSLocalizedString("focus.selectTracks", comment: "Select Tracks"))
                                    .font(.headline)
                                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                                Spacer()

                                Text("\(selectedTrackIds.count) " + NSLocalizedString("focus.selected", comment: "selected"))
                                    .font(.subheadline)
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                            }

                            // Tracks by Category
                            ForEach(BackgroundMusicTrack.MusicCategory.allCases, id: \.self) { category in
                                let tracksInCategory = musicService.getTracks(category: category)

                                if !tracksInCategory.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Category Header
                                        HStack(spacing: 8) {
                                            Image(systemName: category.icon)
                                                .foregroundColor(category.color)

                                            Text(category.displayName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .primary)
                                        }

                                        // Tracks in Category
                                        ForEach(tracksInCategory) { track in
                                            TrackSelectionRow(
                                                track: track,
                                                isSelected: selectedTrackIds.contains(track.id),
                                                colorScheme: colorScheme
                                            ) {
                                                toggleTrackSelection(track.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle(playlistToEdit == nil ?
                            NSLocalizedString("focus.createPlaylist", comment: "Create Playlist") :
                            NSLocalizedString("focus.editPlaylist", comment: "Edit Playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.save", comment: "Save")) {
                        savePlaylist()
                    }
                    .foregroundColor(selectedTrackIds.isEmpty ? .gray : .blue)
                    .disabled(selectedTrackIds.isEmpty)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func toggleTrackSelection(_ trackId: String) {
        if selectedTrackIds.contains(trackId) {
            selectedTrackIds.remove(trackId)
        } else {
            selectedTrackIds.insert(trackId)
        }
    }

    private func savePlaylist() {
        guard !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showNameError = true
            return
        }

        guard !selectedTrackIds.isEmpty else { return }

        let finalName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trackIdsArray = Array(selectedTrackIds)

        if let existingPlaylist = playlistToEdit {
            // Edit existing
            var updated = existingPlaylist
            updated.name = finalName
            updated.trackIds = trackIdsArray
            onSave(updated)
        } else {
            // Create new
            let newPlaylist = MusicPlaylist(name: finalName, trackIds: trackIdsArray)
            onSave(newPlaylist)
        }

        dismiss()
    }
}

// MARK: - Track Selection Row

struct TrackSelectionRow: View {
    let track: BackgroundMusicTrack
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? track.category.color : (colorScheme == .dark ? Color.white.opacity(0.3) : Color.gray.opacity(0.3)), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(track.category.color)
                            .frame(width: 16, height: 16)
                    }
                }

                // Track Icon
                ZStack {
                    Circle()
                        .fill((colorScheme == .dark ? track.category.color.opacity(0.2) : track.category.color.opacity(0.1)))
                        .frame(width: 40, height: 40)

                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundColor(track.category.color)
                }

                // Track Name
                Text(track.name)
                    .font(.body)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Spacer()
            }
            .padding(12)
            .background(
                isSelected ?
                    (colorScheme == .dark ? track.category.color.opacity(0.15) : track.category.color.opacity(0.05)) :
                    (colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? track.category.color.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct PlaylistEditorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PlaylistEditorView { _ in }
                .preferredColorScheme(.light)

            PlaylistEditorView { _ in }
                .preferredColorScheme(.dark)
        }
    }
}
