//
//  FocusView.swift
//  StudyAI
//
//  Enhanced focus mode view with dark mode support and playlist integration
//

import SwiftUI

struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme  // Dark mode detection
    @StateObject private var focusService = FocusSessionService.shared
    @StateObject private var musicService = BackgroundMusicService.shared
    @StateObject private var gardenService = FocusTreeGardenService.shared

    @State private var showMusicSelection = false
    @State private var selectedMusicTrack: BackgroundMusicTrack?
    @State private var selectedPlaylist: MusicPlaylist?
    @State private var showGarden = false
    @State private var showCompletionAnimation = false
    @State private var earnedTree: FocusTree?

    var body: some View {
        ZStack {
            // Adaptive Background
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark ? [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ] : [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.90, green: 0.95, blue: 0.98)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer()

                // Timer Circle
                timerCircle
                    .padding(.horizontal, 40)

                Spacer()

                // Enhanced Music Player
                if focusService.isRunning || focusService.isPaused {
                    enhancedMusicPlayer
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    musicControlSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }

                // Action Buttons
                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }

            // Completion Animation Overlay
            if showCompletionAnimation, let tree = earnedTree {
                completionOverlay(tree: tree)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showMusicSelection) {
            MusicSelectionSheet(
                selectedTrack: $selectedMusicTrack,
                selectedPlaylist: $selectedPlaylist
            )
        }
        .sheet(isPresented: $showGarden) {
            MyGardenView()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Back Button
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text(NSLocalizedString("common.close", comment: "Close"))
                        .font(.body)
                }
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .primary)
            }

            Spacer()

            // My Garden Button
            Button(action: { showGarden = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 16))
                    Text(NSLocalizedString("focus.garden.title", comment: "My Garden"))
                        .font(.body.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: colorScheme == .dark ? [
                            Color.green.opacity(0.8),
                            Color.green.opacity(0.6)
                        ] : [
                            Color.green,
                            Color.green.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(20)
                .shadow(
                    color: Color.green.opacity(colorScheme == .dark ? 0.2 : 0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
        }
    }

    // MARK: - Timer Circle

    private var timerCircle: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Background Circle
                Circle()
                    .stroke(
                        colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.gray.opacity(0.15),
                        lineWidth: 20
                    )
                    .frame(width: size, height: size)

                // Progress Circle
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark ? [
                                Color.cyan.opacity(0.8),
                                Color.blue.opacity(0.6)
                            ] : [
                                Color.blue,
                                Color.purple.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: focusService.elapsedTime)

                // Center Content
                VStack(spacing: 16) {
                    // Status Text
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)

                    // Time Display
                    Text(formattedTime)
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Enhanced Music Player (During Session)

    private var enhancedMusicPlayer: some View {
        VStack(spacing: 12) {
            // Current Track Display
            if let track = musicService.currentTrack, track.id != "no_music" {
                VStack(spacing: 8) {
                    // Now Playing Header
                    Text(NSLocalizedString("focus.nowPlaying", comment: "Now Playing"))
                        .font(.caption.weight(.medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .secondary)

                    // Track Info
                    HStack(spacing: 12) {
                        // Music Icon
                        ZStack {
                            Circle()
                                .fill(
                                    colorScheme == .dark ?
                                        Color.purple.opacity(0.2) :
                                        Color.purple.opacity(0.1)
                                )
                                .frame(width: 50, height: 50)

                            Image(systemName: musicService.isPlaying ? "waveform" : "music.note")
                                .font(.system(size: 20))
                                .foregroundColor(.purple)
                        }

                        // Track Name
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.name)
                                .font(.body.weight(.semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .primary)

                            Text(track.category.displayName)
                                .font(.caption)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                        }

                        Spacer()

                        // Play Controls
                        HStack(spacing: 16) {
                            // Previous (if playlist)
                            if musicService.currentPlaylist != nil {
                                Button(action: { musicService.playPrevious() }) {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .primary)
                                }
                            }

                            // Play/Pause
                            Button(action: { musicService.togglePlayPause() }) {
                                Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.purple)
                            }

                            // Next (if playlist)
                            if musicService.currentPlaylist != nil {
                                Button(action: { musicService.playNext() }) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .primary)
                                }
                            }
                        }
                    }

                    // Next Track Info (if playlist)
                    if let nextTrack = musicService.nextTrack {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 12))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .secondary.opacity(0.6))

                            Text(String(format: NSLocalizedString("focus.nextTrack", comment: "Next: %@"), nextTrack.name))
                                .font(.caption)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(
                    colorScheme == .dark ?
                        Color.white.opacity(0.05) :
                        Color.white
                )
                .cornerRadius(16)
                .shadow(
                    color: colorScheme == .dark ?
                        Color.white.opacity(0.05) :
                        Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
            }
        }
        .animation(.easeInOut, value: musicService.currentTrack)
    }

    // MARK: - Music Control Section (Before Session)

    private var musicControlSection: some View {
        VStack(spacing: 12) {
            Button(action: { showMusicSelection = true }) {
                HStack(spacing: 12) {
                    // Music Icon
                    ZStack {
                        Circle()
                            .fill(
                                colorScheme == .dark ?
                                    Color.purple.opacity(0.2) :
                                    Color.purple.opacity(0.1)
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: musicService.isPlaying ? "music.note" : "music.note.list")
                            .font(.system(size: 18))
                            .foregroundColor(.purple)
                    }

                    // Music Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("focus.selectMusic", comment: "Select Music"))
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)

                        Text(currentMusicTitle)
                            .font(.body.weight(.medium))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .secondary)
                }
                .padding(16)
                .background(
                    colorScheme == .dark ?
                        Color.white.opacity(0.05) :
                        Color.white
                )
                .cornerRadius(16)
                .shadow(
                    color: colorScheme == .dark ?
                        Color.white.opacity(0.05) :
                        Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
            }
            .disabled(focusService.isRunning && !focusService.isPaused)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !focusService.isRunning {
                // Start Button
                Button(action: startSession) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                        Text(NSLocalizedString("focus.startSession", comment: "Start Focus"))
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark ? [
                                Color.blue.opacity(0.8),
                                Color.blue.opacity(0.6)
                            ] : [
                                Color.blue,
                                Color.blue.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(
                        color: Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.3),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                }
            } else {
                HStack(spacing: 12) {
                    // Pause/Resume Button
                    Button(action: togglePauseResume) {
                        HStack(spacing: 8) {
                            Image(systemName: focusService.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 18))
                            Text(focusService.isPaused ?
                                 NSLocalizedString("focus.resumeSession", comment: "Resume") :
                                 NSLocalizedString("focus.pauseSession", comment: "Pause")
                            )
                            .font(.body.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: colorScheme == .dark ? [
                                    Color.orange.opacity(0.8),
                                    Color.orange.opacity(0.6)
                                ] : [
                                    Color.orange,
                                    Color.orange.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(16)
                    }

                    // End Button
                    Button(action: endSession) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            Text(NSLocalizedString("focus.endSession", comment: "End"))
                                .font(.body.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: colorScheme == .dark ? [
                                    Color.green.opacity(0.8),
                                    Color.green.opacity(0.6)
                                ] : [
                                    Color.green,
                                    Color.green.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(16)
                    }
                }

                // Cancel Button
                Button(action: cancelSession) {
                    Text(NSLocalizedString("focus.cancelSession", comment: "Cancel"))
                        .font(.body)
                        .foregroundColor(colorScheme == .dark ? .red.opacity(0.8) : .red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Completion Overlay

    private func completionOverlay(tree: FocusTree) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Tree Emoji with Animation
                Text(tree.type.emoji)
                    .font(.system(size: 100))
                    .scaleEffect(showCompletionAnimation ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCompletionAnimation)

                // Congratulations Text
                VStack(spacing: 8) {
                    Text(String(format: NSLocalizedString("focus.earnedTree", comment: "You earned a tree!"), tree.type.displayName))
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text(NSLocalizedString("focus.keepGoing", comment: "Keep going to grow bigger trees!"))
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                // Stats
                VStack(spacing: 12) {
                    HStack(spacing: 24) {
                        StatItem(
                            icon: "clock.fill",
                            value: formatDuration(tree.focusDuration),
                            label: NSLocalizedString("focus.focusTime", comment: "Focus Time")
                        )

                        StatItem(
                            icon: "star.fill",
                            value: "+\(Int(tree.focusDuration / 60 / 5))",
                            label: NSLocalizedString("progress.pointsEarned", comment: "Points")
                        )
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)

                // View Garden Button
                Button(action: {
                    showCompletionAnimation = false
                    earnedTree = nil
                    showGarden = true
                }) {
                    Text(NSLocalizedString("focus.garden.title", comment: "View My Garden"))
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)

                // Dismiss Button
                Button(action: {
                    showCompletionAnimation = false
                    earnedTree = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 8)
            }
            .padding(32)
        }
    }

    // MARK: - Helper Views

    private struct StatItem: View {
        let icon: String
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                    Text(value)
                        .font(.title3.weight(.bold))
                }
                .foregroundColor(.white)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Computed Properties

    private var progressFraction: CGFloat {
        let thirtyMinutes: TimeInterval = 30 * 60
        return min(CGFloat(focusService.elapsedTime / thirtyMinutes), 1.0)
    }

    private var formattedTime: String {
        let hours = Int(focusService.elapsedTime) / 3600
        let minutes = (Int(focusService.elapsedTime) % 3600) / 60
        let seconds = Int(focusService.elapsedTime) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var statusText: String {
        if focusService.isPaused {
            return NSLocalizedString("focus.sessionPaused", comment: "Paused")
        } else if focusService.isRunning {
            return NSLocalizedString("focus.sessionActive", comment: "Focusing")
        } else {
            return NSLocalizedString("focus.focusTime", comment: "Focus Time")
        }
    }

    private var currentMusicTitle: String {
        if let playlist = selectedPlaylist {
            return "\(playlist.name) (\(playlist.trackCount) tracks)"
        } else if let track = selectedMusicTrack {
            return track.name
        }
        return NSLocalizedString("focus.noMusic", comment: "No Music")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    // MARK: - Actions

    private func startSession() {
        if let playlist = selectedPlaylist {
            musicService.playPlaylist(playlist)
            focusService.startSession(withMusic: playlist.id)
        } else if let track = selectedMusicTrack {
            if track.id != "no_music" {
                musicService.play(track: track)
            }
            focusService.startSession(withMusic: track.id)
        } else {
            focusService.startSession()
        }
    }

    private func togglePauseResume() {
        if focusService.isPaused {
            focusService.resumeSession()
            if musicService.currentTrack?.id != "no_music" {
                musicService.resume()
            }
        } else {
            focusService.pauseSession()
            musicService.pause()
        }
    }

    private func endSession() {
        if let completedSession = focusService.endSession() {
            musicService.stop()

            // Plant tree in garden
            let tree = gardenService.plantTree(from: completedSession)
            earnedTree = tree

            // Show completion animation
            withAnimation {
                showCompletionAnimation = true
            }
        }
    }

    private func cancelSession() {
        focusService.cancelSession()
        musicService.stop()
    }
}

// MARK: - Preview

struct FocusView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                FocusView()
            }
            .preferredColorScheme(.light)

            NavigationView {
                FocusView()
            }
            .preferredColorScheme(.dark)
        }
    }
}
