//
//  MusicSelectionSheet.swift
//  StudyAI
//
//  Enhanced music selection with playlist support and dark mode
//

import SwiftUI

struct MusicSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var musicService = BackgroundMusicService.shared
    @ObservedObject var downloadService = MusicDownloadService.shared

    @Binding var selectedTrack: BackgroundMusicTrack?
    @Binding var selectedPlaylist: MusicPlaylist?

    @State private var selectionMode: SelectionMode = .track
    @State private var showingPlaylistEditor = false
    @State private var playlistToEdit: MusicPlaylist?
    @State private var showingUserMusicPicker = false

    enum SelectionMode: String, CaseIterable {
        case track = "Single Track"
        case playlist = "Playlist"

        var localizedName: String {
            switch self {
            case .track: return NSLocalizedString("focus.singleTrack", comment: "Single Track")
            case .playlist: return NSLocalizedString("focus.playlist", comment: "Playlist")
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ?
                    Color(red: 0.05, green: 0.05, blue: 0.1) :
                    Color(red: 0.95, green: 0.97, blue: 1.0))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerSection
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                    // Volume Control
                    volumeControl
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Mode Selector
                    modeSelector
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // Content
                    ScrollView {
                        if selectionMode == .track {
                            trackListContent
                        } else {
                            playlistContent
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .adaptiveNavigationBar() // iOS 18+ liquid glass / iOS < 18 solid background
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .primary)
                }
            }
        }
        .sheet(isPresented: $showingPlaylistEditor) {
            if let playlist = playlistToEdit {
                PlaylistEditorView(playlist: playlist) { updatedPlaylist in
                    musicService.updatePlaylist(updatedPlaylist)
                    playlistToEdit = nil
                }
            } else {
                PlaylistEditorView { newPlaylist in
                    let created = musicService.createPlaylist(name: newPlaylist.name, trackIds: newPlaylist.trackIds)
                    selectedPlaylist = created
                    selectedTrack = nil
                }
            }
        }
        .sheet(isPresented: $showingUserMusicPicker) {
            UserMusicPickerView()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("focus.selectMusic", comment: "Select Background Music"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(colorScheme == .dark ? .white : .primary)

            Text(NSLocalizedString("focus.selectMusicSubtitle", comment: "Choose music or create a playlist for your focus session"))
                .font(.subheadline)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Volume Control

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)

                Text(NSLocalizedString("focus.volume", comment: "Volume"))
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)

                Spacer()

                Text(String(format: "%.0f%%", musicService.volume * 100))
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
            }

            Slider(value: $musicService.volume, in: 0...1)
                .accentColor(.purple)
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        Picker("Selection Mode", selection: $selectionMode) {
            ForEach(SelectionMode.allCases, id: \.self) { mode in
                Text(mode.localizedName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Track List Content

    private var trackListContent: some View {
        VStack(spacing: 24) {
            // Add from Library Button
            Button(action: { showingUserMusicPicker = true }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.pink.opacity(0.15))
                            .frame(width: 50, height: 50)

                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.pink)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add from My Library")
                            .font(.body.weight(.semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)

                        Text("Use your own music")
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .secondary)
                }
                .padding(16)
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .cornerRadius(16)
                .shadow(
                    color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 20)

            // No Music Option
            TrackRow(
                track: musicService.availableTracks.first(where: { $0.id == "no_music" })!,
                isSelected: selectedTrack?.id == "no_music",
                isPlaying: false,
                colorScheme: colorScheme
            ) {
                handleTrackSelection(musicService.availableTracks.first(where: { $0.id == "no_music" })!)
            }

            // Tracks by Category (only bundled tracks)
            ForEach(BackgroundMusicTrack.MusicCategory.allCases, id: \.self) { category in
                let tracksInCategory = musicService.getTracks(category: category).filter { $0.source == .bundle }

                if !tracksInCategory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        // Category Header
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .foregroundColor(category.color)

                            Text(category.displayName)
                                .font(.headline)
                                .foregroundColor(colorScheme == .dark ? .white : .primary)
                        }
                        .padding(.horizontal, 20)

                        // Tracks in this category
                        ForEach(tracksInCategory) { track in
                            TrackRow(
                                track: track,
                                isSelected: selectedTrack?.id == track.id,
                                isPlaying: musicService.isPlaying && musicService.currentTrack?.id == track.id,
                                colorScheme: colorScheme
                            ) {
                                handleTrackSelection(track)
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }

            // More Section - Remote Downloadable Tracks
            remoteTracksSection
        }
        .padding(.vertical, 8)
    }

    // MARK: - Remote Tracks Section

    private var remoteTracksSection: some View {
        let remoteTracks = musicService.availableTracks.filter { $0.source == .remote }

        return VStack(alignment: .leading, spacing: 12) {
            // "More" Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)

                Text(NSLocalizedString("focus.moreMusic", comment: "More Music"))
                    .font(.headline)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Spacer()

                Text(NSLocalizedString("focus.downloadable", comment: "Downloadable"))
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Remote tracks
            ForEach(remoteTracks) { track in
                RemoteTrackRow(
                    track: track,
                    isSelected: selectedTrack?.id == track.id,
                    isPlaying: musicService.isPlaying && musicService.currentTrack?.id == track.id,
                    isDownloaded: downloadService.isTrackDownloaded(track.id),
                    downloadProgress: downloadService.downloadProgress[track.id],
                    colorScheme: colorScheme,
                    onSelect: {
                        handleTrackSelection(track)
                    },
                    onDownload: {
                        downloadService.downloadTrack(track)
                    },
                    onDelete: {
                        downloadService.deleteTrack(track.id, fileName: track.fileName)
                    },
                    onCancelDownload: {
                        downloadService.cancelDownload(track.id)
                    }
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Playlist Content

    private var playlistContent: some View {
        VStack(spacing: 16) {
            // Create Playlist Button
            Button(action: {
                playlistToEdit = nil
                showingPlaylistEditor = true
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 50, height: 50)

                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("focus.createPlaylist", comment: "Create Playlist"))
                            .font(.body.weight(.semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)

                        Text(NSLocalizedString("focus.createPlaylistDescription", comment: "Combine multiple tracks"))
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .secondary)
                }
                .padding(16)
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .cornerRadius(16)
                .shadow(
                    color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Existing Playlists
            let playlists = musicService.getAllPlaylists()

            if playlists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3))

                    Text(NSLocalizedString("focus.noPlaylists", comment: "No playlists yet"))
                        .font(.subheadline)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)

                    Text(NSLocalizedString("focus.createFirstPlaylist", comment: "Create your first playlist to get started"))
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(playlists) { playlist in
                    PlaylistRow(
                        playlist: playlist,
                        isSelected: selectedPlaylist?.id == playlist.id,
                        colorScheme: colorScheme,
                        onSelect: {
                            selectedPlaylist = playlist
                            selectedTrack = nil
                            dismiss()
                        },
                        onEdit: {
                            playlistToEdit = playlist
                            showingPlaylistEditor = true
                        },
                        onDelete: {
                            musicService.deletePlaylist(id: playlist.id)
                        }
                    )
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helper Methods

    private func handleTrackSelection(_ track: BackgroundMusicTrack) {
        // If selecting "No Music", stop playback
        if track.id == "no_music" {
            musicService.stop()
            selectedTrack = track
            selectedPlaylist = nil
            return
        }

        // If remote track is not downloaded, don't allow selection
        if track.source == .remote && !downloadService.isTrackDownloaded(track.id) {
            print("⚠️ Cannot play remote track: not downloaded yet")
            return
        }

        // If this track is already playing, just select it
        if musicService.currentTrack?.id == track.id && musicService.isPlaying {
            selectedTrack = track
            selectedPlaylist = nil
            return
        }

        // Play the new track
        selectedTrack = track
        selectedPlaylist = nil
        musicService.play(track: track)
    }
}

// MARK: - Track Row Component

struct TrackRow: View {
    let track: BackgroundMusicTrack
    let isSelected: Bool
    let isPlaying: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Track Icon/Status
                ZStack {
                    Circle()
                        .fill(isSelected ?
                            track.category.color.opacity(0.2) :
                            (colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.1)))
                        .frame(width: 44, height: 44)

                    if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundColor(track.category.color)
                            .font(.system(size: 18))
                    } else if track.id == "no_music" {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                            .font(.system(size: 18))
                    } else {
                        Image(systemName: "music.note")
                            .foregroundColor(isSelected ? track.category.color : (colorScheme == .dark ? .white.opacity(0.6) : .secondary))
                            .font(.system(size: 18))
                    }
                }

                // Track Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)

                    if track.id != "no_music" {
                        Text(track.category.displayName)
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                    }
                }

                Spacer()

                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(track.category.color)
                        .font(.system(size: 22))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ?
                        track.category.color.opacity(0.05) :
                        (colorScheme == .dark ? Color.white.opacity(0.02) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Playlist Row Component

struct PlaylistRow: View {
    let playlist: MusicPlaylist
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Playlist Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.purple.opacity(0.2) : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.purple.opacity(0.1)))
                        .frame(width: 50, height: 50)

                    Image(systemName: "music.note.list")
                        .font(.system(size: 20))
                        .foregroundColor(.purple)
                }

                // Playlist Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)

                    Text("\(playlist.trackCount) " + NSLocalizedString("focus.tracks", comment: "tracks"))
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                }

                Spacer()

                // Actions
                HStack(spacing: 12) {
                    // Edit Button
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Delete Button
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 22))
                    }
                }
            }
            .padding(16)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            .cornerRadius(16)
            .shadow(
                color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05),
                radius: 8,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(PlainButtonStyle())
        .alert(NSLocalizedString("focus.deletePlaylist", comment: "Delete Playlist"), isPresented: $showDeleteConfirmation) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("focus.deletePlaylistConfirmation", comment: "Are you sure you want to delete this playlist?"))
        }
    }
}

// MARK: - Remote Track Row Component

struct RemoteTrackRow: View {
    let track: BackgroundMusicTrack
    let isSelected: Bool
    let isPlaying: Bool
    let isDownloaded: Bool
    let downloadProgress: Double?
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onCancelDownload: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: {
            if isDownloaded {
                onSelect()
            }
        }) {
            HStack(spacing: 16) {
                // Track Icon/Status
                ZStack {
                    Circle()
                        .fill(isSelected ?
                            track.category.color.opacity(0.2) :
                            (colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.1)))
                        .frame(width: 50, height: 50)

                    if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundColor(track.category.color)
                            .font(.system(size: 20))
                    } else if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                    } else {
                        Image(systemName: track.source.icon)
                            .foregroundColor(.blue)
                            .font(.system(size: 20))
                    }
                }

                // Track Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(track.name)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)

                    HStack(spacing: 8) {
                        Text(track.category.displayName)
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)

                        if let description = track.description {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .secondary)

                            Text(description)
                                .font(.caption)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                                .lineLimit(1)
                        }
                    }

                    if let fileSize = track.formattedFileSize {
                        Text(fileSize)
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }

                    // Download Progress Bar
                    if let progress = downloadProgress {
                        VStack(spacing: 4) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.2))
                                        .frame(height: 6)

                                    // Progress
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue)
                                        .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                                        .animation(.linear(duration: 0.2), value: progress)
                                }
                            }
                            .frame(height: 6)

                            HStack {
                                Text(String(format: "%.0f%%", progress * 100))
                                    .font(.caption2)
                                    .foregroundColor(.blue)

                                Spacer()

                                Button(action: onCancelDownload) {
                                    Text(NSLocalizedString("common.cancel", comment: "Cancel"))
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Action Button
                if let _ = downloadProgress {
                    // Downloading - show progress spinner
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isDownloaded {
                    // Downloaded - show delete button
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Not downloaded - show download button
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ?
                        track.category.color.opacity(0.05) :
                        (colorScheme == .dark ? Color.white.opacity(0.02) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isDownloaded && downloadProgress == nil)
        .alert(NSLocalizedString("focus.deleteTrack", comment: "Delete Track"), isPresented: $showDeleteConfirmation) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("focus.deleteTrackConfirmation", comment: "Are you sure you want to delete this downloaded track? You can re-download it anytime."))
        }
    }
}

// MARK: - Preview

struct MusicSelectionSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MusicSelectionSheet(
                selectedTrack: .constant(nil),
                selectedPlaylist: .constant(nil)
            )
            .preferredColorScheme(.light)

            MusicSelectionSheet(
                selectedTrack: .constant(nil),
                selectedPlaylist: .constant(nil)
            )
            .preferredColorScheme(.dark)
        }
    }
}
