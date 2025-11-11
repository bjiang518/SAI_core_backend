//
//  UserMusicPickerView.swift
//  StudyAI
//
//  UI for selecting music from user's library
//

import SwiftUI
import MediaPlayer

struct UserMusicPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var libraryService = MusicLibraryService.shared
    @ObservedObject var musicService = BackgroundMusicService.shared

    @State private var showingMediaPicker = false
    @State private var showingAuthAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ?
                    Color(red: 0.05, green: 0.05, blue: 0.1) :
                    Color(red: 0.95, green: 0.97, blue: 1.0))
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    if libraryService.authorizationStatus == .authorized {
                        authorizedContent
                    } else {
                        unauthorizedContent
                    }
                }
                .padding()
            }
            .navigationTitle("My Music")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .primary)
                }

                if libraryService.authorizationStatus == .authorized {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingMediaPicker = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.pink)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingMediaPicker) {
            MediaPickerWrapper { mediaItem in
                if let track = libraryService.createTrack(from: mediaItem) {
                    libraryService.addUserTrack(track)
                }
                showingMediaPicker = false
            }
        }
        .alert("Music Library Access", isPresented: $showingAuthAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        } message: {
            Text("Please enable music library access in Settings to use your own music.")
        }
    }

    // MARK: - Authorized Content

    private var authorizedContent: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.pink)

                Text("Your Music Library")
                    .font(.title2.bold())
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text("Add songs from your library to use during focus sessions")
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            // User tracks list
            if libraryService.userTracks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(libraryService.userTracks) { track in
                            UserTrackRow(
                                track: track,
                                colorScheme: colorScheme,
                                onPlay: {
                                    musicService.play(track: track)
                                    dismiss()
                                },
                                onDelete: {
                                    libraryService.removeUserTrack(track.id)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Spacer()
        }
    }

    // MARK: - Unauthorized Content

    private var unauthorizedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .gray)

            VStack(spacing: 12) {
                Text("Music Library Access")
                    .font(.title2.bold())
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text("StudyAI needs permission to access your music library to play your own songs during focus sessions.")
                    .font(.body)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: requestAuthorization) {
                HStack {
                    Image(systemName: "music.note")
                    Text("Grant Access")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.pink)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))

            Text("No songs added yet")
                .font(.headline)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)

            Text("Tap the + button to add songs from your library")
                .font(.subheadline)
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Helper Methods

    private func requestAuthorization() {
        libraryService.requestAuthorization { granted in
            if !granted {
                showingAuthAlert = true
            }
        }
    }
}

// MARK: - User Track Row

struct UserTrackRow: View {
    let track: BackgroundMusicTrack
    let colorScheme: ColorScheme
    let onPlay: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Music icon
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(.pink)
            }

            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text("My Music • \(Int(track.duration / 60)):\(String(format: "%02d", Int(track.duration.truncatingRemainder(dividingBy: 60))))")
                    .font(.caption)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.pink)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { showDeleteConfirm = true }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .alert("Delete Song", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Remove \(track.name) from your focus music?")
        }
    }
}

// MARK: - Media Picker Wrapper

struct MediaPickerWrapper: UIViewControllerRepresentable {
    let onSelect: (MPMediaItem) -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onSelect: (MPMediaItem) -> Void

        init(onSelect: @escaping (MPMediaItem) -> Void) {
            self.onSelect = onSelect
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            if let item = mediaItemCollection.items.first {
                onSelect(item)
            }
            mediaPicker.dismiss(animated: true)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            mediaPicker.dismiss(animated: true)
        }
    }
}

// MARK: - Preview

struct UserMusicPickerView_Previews: PreviewProvider {
    static var previews: some View {
        UserMusicPickerView()
    }
}
