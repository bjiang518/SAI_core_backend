//
//  FocusView.swift
//  StudyAI
//
//  Enhanced focus mode view with theme support and localization
//

import SwiftUI

struct FocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var deepLinkHandler: PomodoroDeepLinkHandler
    @StateObject private var focusService = FocusSessionService.shared
    @StateObject private var musicService = BackgroundMusicService.shared
    @StateObject private var tomatoGarden = TomatoGardenService.shared
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var appState = AppState.shared

    @State private var showMusicSelection = false
    @State private var selectedMusicTrack: BackgroundMusicTrack?
    @State private var selectedPlaylist: MusicPlaylist?
    @State private var showTomatoGarden = false
    @State private var showCalendar = false
    @State private var enableDeepFocus = false
    @State private var showDeepFocusInfo = false
    @State private var showCompletionAnimation = false
    @State private var earnedTomato: Tomato?

    // Drag-to-stop states
    @State private var isDraggingStop = false
    @State private var stopButtonOffset: CGSize = .zero
    @State private var circleCenter: CGPoint = .zero
    @State private var circleRadius: CGFloat = 0
    @State private var isStopButtonInCircle = false

    var body: some View {
        ZStack {
            // Theme-aware background
            themeManager.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer()

                timerCircle
                    .padding(.horizontal, 40)

                Spacer()

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

                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }

            if showCompletionAnimation, let tomato = earnedTomato {
                completionOverlay(tomato: tomato)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showMusicSelection) {
            MusicSelectionSheet(
                selectedTrack: $selectedMusicTrack,
                selectedPlaylist: $selectedPlaylist
            )
        }
        .sheet(isPresented: $showTomatoGarden) {
            TomatoPokedexView()
        }
        .sheet(isPresented: $showCalendar) {
            PomodoroCalendarView()
        }
        .alert(NSLocalizedString("deepFocus.title", comment: ""), isPresented: $showDeepFocusInfo) {
            Button(NSLocalizedString("deepFocus.gotIt", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("deepFocus.viewGuide", comment: "")) {
                // Show system settings guide
            }
        } message: {
            Text(NSLocalizedString("deepFocus.guide.message", comment: ""))
        }
        .onAppear {
            if deepLinkHandler.shouldShowPomodoro && deepLinkHandler.shouldAutoStart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startSession()
                    deepLinkHandler.resetState()
                }
            }
            enableDeepFocus = focusService.isDeepFocusEnabled
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.primaryText)
            }

            Spacer()

            if appState.isPowerSavingMode {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.Colors.Cute.mint)
                    Text(NSLocalizedString("pomodoro.powerSaving", comment: ""))
                        .font(.caption2)
                        .foregroundColor(DesignTokens.Colors.Cute.mint)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(DesignTokens.Colors.Cute.mintLight.opacity(0.3))
                )
                .padding(.trailing, 8)
            }

            Button(action: { showCalendar = true }) {
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundColor(DesignTokens.Colors.Cute.blue)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(DesignTokens.Colors.Cute.blueLight.opacity(0.3))
                    )
            }
            .padding(.trailing, 8)

            Button(action: { showTomatoGarden = true }) {
                Text("🍅")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(DesignTokens.Colors.Cute.peachLight.opacity(0.3))
                    )
            }
            .padding(.trailing, 8)

            Button(action: {
                if !focusService.isRunning {
                    enableDeepFocus.toggle()
                } else {
                    focusService.toggleDeepFocus()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(
                            (enableDeepFocus || focusService.isDeepFocusEnabled) ?
                                LinearGradient(
                                    colors: [DesignTokens.Colors.Cute.lavender, DesignTokens.Colors.Cute.lavenderLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [themeManager.cardBackground.opacity(0.5), themeManager.cardBackground],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: (enableDeepFocus || focusService.isDeepFocusEnabled) ? "moon.fill" : "moon")
                        .font(.system(size: 20))
                        .foregroundColor((enableDeepFocus || focusService.isDeepFocusEnabled) ? .white : themeManager.secondaryText)
                }
            }
        }
    }

    // MARK: - Timer Circle

    private var timerCircle: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .stroke(
                        themeManager.cardBackground.opacity(0.3),
                        lineWidth: 20
                    )
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.Cute.blue,
                                DesignTokens.Colors.Cute.lavender,
                                DesignTokens.Colors.Cute.pink
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: focusService.elapsedTime)
                    .shadow(
                        color: isStopButtonInCircle ? DesignTokens.Colors.Cute.peach.opacity(0.6) : Color.clear,
                        radius: isStopButtonInCircle ? 20 : 0
                    )
                    .animation(.easeInOut(duration: 0.3), value: isStopButtonInCircle)

                VStack(spacing: 0) {
                    Text(formattedTime)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Colors.Cute.blue,
                                    DesignTokens.Colors.Cute.lavender,
                                    DesignTokens.Colors.Cute.pink
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: DesignTokens.Colors.Cute.blue.opacity(0.3), radius: 20)
                        .padding(.bottom, size * 0.15)

                    if focusService.isRunning {
                        Button(action: togglePauseResume) {
                            Image(systemName: focusService.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: size * 0.12, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: focusService.isPaused ? [
                                            DesignTokens.Colors.Cute.mint,
                                            DesignTokens.Colors.Cute.mintLight
                                        ] : [
                                            DesignTokens.Colors.Cute.yellow,
                                            DesignTokens.Colors.Cute.yellowLight
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .scaleEffect(focusService.isPaused ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: focusService.isPaused)
                        }
                    } else {
                        Text(statusText)
                            .font(.title3)
                            .foregroundColor(themeManager.secondaryText)
                    }
                }
                .onAppear {
                    circleCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    circleRadius = size / 2
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Enhanced Music Player

    private var enhancedMusicPlayer: some View {
        VStack(spacing: 12) {
            if let track = musicService.currentTrack, track.id != "no_music" {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("focus.music.nowPlaying", comment: ""))
                        .font(.caption.weight(.medium))
                        .foregroundColor(themeManager.secondaryText)

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.Cute.lavenderLight.opacity(0.3))
                                .frame(width: 50, height: 50)

                            Image(systemName: musicService.isPlaying ? "waveform" : "music.note")
                                .font(.system(size: 20))
                                .foregroundColor(DesignTokens.Colors.Cute.lavender)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.name)
                                .font(.body.weight(.semibold))
                                .foregroundColor(themeManager.primaryText)

                            Text(track.category.displayName)
                                .font(.caption)
                                .foregroundColor(themeManager.secondaryText)
                        }

                        Spacer()

                        HStack(spacing: 16) {
                            if musicService.currentPlaylist != nil {
                                Button(action: { musicService.playPrevious() }) {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(themeManager.primaryText)
                                }
                            }

                            Button(action: { musicService.togglePlayPause() }) {
                                Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(DesignTokens.Colors.Cute.lavender)
                            }

                            if musicService.currentPlaylist != nil {
                                Button(action: { musicService.playNext() }) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(themeManager.primaryText)
                                }
                            }
                        }
                    }

                    if let nextTrack = musicService.nextTrack {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryText.opacity(0.6))

                            Text(String(format: NSLocalizedString("focus.music.nextTrack", comment: ""), nextTrack.name))
                                .font(.caption)
                                .foregroundColor(themeManager.secondaryText)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(themeManager.cardBackground)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
            }
        }
        .animation(.easeInOut, value: musicService.currentTrack)
    }

    // MARK: - Music Control Section

    private var musicControlSection: some View {
        Button(action: { showMusicSelection = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.Cute.lavenderLight.opacity(0.3))
                        .frame(width: 44, height: 44)

                    Image(systemName: musicService.isPlaying ? "music.note" : "music.note.list")
                        .font(.system(size: 18))
                        .foregroundColor(DesignTokens.Colors.Cute.lavender)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("focus.music.select", comment: ""))
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryText)

                    Text(currentMusicTitle)
                        .font(.body.weight(.medium))
                        .foregroundColor(themeManager.primaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.secondaryText)
            }
            .padding(16)
            .background(themeManager.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
        }
        .disabled(focusService.isRunning && !focusService.isPaused)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !focusService.isRunning {
                Button(action: startSession) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                        Text(NSLocalizedString("focus.session.start", comment: ""))
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.Cute.blue,
                                DesignTokens.Colors.Cute.blueLight
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: DesignTokens.Colors.Cute.blue.opacity(0.3), radius: 12, y: 6)
                }
            } else {
                draggableStopButton
            }
        }
    }

    // MARK: - Draggable Stop Button

    private var draggableStopButton: some View {
        VStack(spacing: 20) {
            if isDraggingStop {
                Text(NSLocalizedString("pomodoro.dragToStop", comment: ""))
                    .font(.caption)
                    .foregroundColor(DesignTokens.Colors.Cute.peach)
                    .transition(.opacity)
            }

            ZStack {
                if isDraggingStop {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Colors.Cute.peach.opacity(0.8),
                                    DesignTokens.Colors.Cute.peach.opacity(0.3),
                                    DesignTokens.Colors.Cute.peach.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(1.5)
                        .opacity(0.6)
                }

                Text(NSLocalizedString("pomodoro.stop", comment: ""))
                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDraggingStop ? [
                                DesignTokens.Colors.Cute.peach,
                                DesignTokens.Colors.Cute.peachLight
                            ] : [
                                themeManager.secondaryText,
                                themeManager.secondaryText.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isDraggingStop ? DesignTokens.Colors.Cute.peach.opacity(0.5) : .clear, radius: 10)
            }
            .offset(stopButtonOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingStop {
                            isDraggingStop = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }

                        stopButtonOffset = value.translation
                        let draggedUpDistance = -value.translation.height
                        let minimumDragDistance: CGFloat = 200
                        let wasInCircle = isStopButtonInCircle
                        isStopButtonInCircle = draggedUpDistance >= minimumDragDistance

                        UIImpactFeedbackGenerator(style: .light).impactOccurred()

                        if isStopButtonInCircle && !wasInCircle {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        }
                    }
                    .onEnded { value in
                        let draggedUpDistance = -value.translation.height
                        let minimumDragDistance: CGFloat = 200

                        if draggedUpDistance >= minimumDragDistance {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)

                            withAnimation(.spring()) {
                                stopButtonOffset = .zero
                                isDraggingStop = false
                                isStopButtonInCircle = false
                            }

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                endSession()
                            }
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)

                            withAnimation(.spring()) {
                                stopButtonOffset = .zero
                                isDraggingStop = false
                                isStopButtonInCircle = false
                            }
                        }
                    }
            )
        }
    }

    // MARK: - Completion Overlay

    private func completionOverlay(tomato: Tomato) -> some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(tomato.type.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .scaleEffect(showCompletionAnimation ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCompletionAnimation)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("focus.session.congratulations", comment: ""))
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text(String(format: NSLocalizedString("focus.session.earnedTomato", comment: ""), tomato.type.displayName))
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)

                    Text(tomato.type.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    HStack(spacing: 24) {
                        StatItem(
                            icon: "clock.fill",
                            value: tomato.formattedDuration,
                            label: NSLocalizedString("focus.session.duration", comment: "").replacingOccurrences(of: ": %@", with: "")
                        )

                        StatItem(
                            icon: "star.fill",
                            value: "+\(Int(tomato.focusDuration / 60 / 5))",
                            label: NSLocalizedString("focus.session.pointsEarned", comment: "").replacingOccurrences(of: "+%d points earned", with: "Points")
                        )
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)

                Button(action: {
                    showCompletionAnimation = false
                    earnedTomato = nil
                    showTomatoGarden = true
                }) {
                    HStack(spacing: 8) {
                        Text("🍅")
                            .font(.system(size: 20))
                        Text(NSLocalizedString("focus.session.viewGarden", comment: ""))
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [DesignTokens.Colors.Cute.peach, DesignTokens.Colors.Cute.peachLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)

                Button(action: {
                    showCompletionAnimation = false
                    earnedTomato = nil
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
        let progress = focusService.elapsedTime / focusService.pomodoroDuration
        return min(CGFloat(progress), 1.0)
    }

    private var formattedTime: String {
        let seconds = Int(focusService.remainingTime)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private var statusText: String {
        if focusService.isCompleted {
            return NSLocalizedString("focus.session.completed", comment: "")
        } else if focusService.isPaused {
            return NSLocalizedString("focus.session.paused", comment: "")
        } else if focusService.isRunning {
            return NSLocalizedString("focus.session.active", comment: "")
        } else {
            return NSLocalizedString("pomodoro.focusMode", comment: "")
        }
    }

    private var currentMusicTitle: String {
        if let playlist = selectedPlaylist {
            return "\(playlist.name) (\(playlist.trackCount) \(NSLocalizedString("focus.music.tracks", comment: "tracks")))"
        } else if let track = selectedMusicTrack {
            return track.name
        }
        return NSLocalizedString("focus.music.noMusic", comment: "")
    }

    // MARK: - Actions

    private func startSession() {
        if let playlist = selectedPlaylist {
            musicService.playPlaylist(playlist)
            focusService.startSession(withMusic: playlist.id, enableDeepFocus: enableDeepFocus)
        } else if let track = selectedMusicTrack {
            if track.id != "no_music" {
                musicService.play(track: track)
            }
            focusService.startSession(withMusic: track.id, enableDeepFocus: enableDeepFocus)
        } else {
            focusService.startSession(enableDeepFocus: enableDeepFocus)
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

            let tomato = tomatoGarden.addTomato(from: completedSession)
            earnedTomato = tomato

            withAnimation {
                showCompletionAnimation = true
            }
        }
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
