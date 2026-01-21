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
    @EnvironmentObject var deepLinkHandler: PomodoroDeepLinkHandler
    @StateObject private var focusService = FocusSessionService.shared
    @StateObject private var musicService = BackgroundMusicService.shared
    @StateObject private var tomatoGarden = TomatoGardenService.shared
    @ObservedObject private var appState = AppState.shared  // 观察省电模式状态

    @State private var showMusicSelection = false
    @State private var selectedMusicTrack: BackgroundMusicTrack?
    @State private var selectedPlaylist: MusicPlaylist?
    @State private var showTomatoGarden = false
    @State private var showCalendar = false  // 新增：显示日历
    @State private var enableDeepFocus = false  // 新增：深度专注开关
    @State private var showDeepFocusInfo = false  // 新增：深度专注说明
    @State private var showCompletionAnimation = false
    @State private var earnedTomato: Tomato?

    // 拖拽停止相关状态
    @State private var isDraggingStop = false
    @State private var stopButtonOffset: CGSize = .zero
    @State private var circleCenter: CGPoint = .zero
    @State private var circleRadius: CGFloat = 0
    @State private var isStopButtonInCircle = false  // 停止按钮是否在圆环内

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
        .alert(NSLocalizedString("pomodoro.deepFocusAlertTitle", comment: ""), isPresented: $showDeepFocusInfo) {
            Button(NSLocalizedString("pomodoro.gotIt", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("pomodoro.viewSetupGuide", comment: "")) {
                // 显示系统设置指南
            }
        } message: {
            Text(DeepFocusService.shared.getSetupGuide())
        }
        .onAppear {
            // 处理Deep Link自动启动
            if deepLinkHandler.shouldShowPomodoro && deepLinkHandler.shouldAutoStart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startSession()
                    deepLinkHandler.resetState()
                }
            }

            // 同步深度专注状态
            enableDeepFocus = focusService.isDeepFocusEnabled
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Back Button
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .primary)
            }

            Spacer()

            // 省电模式指示器
            if appState.isPowerSavingMode {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text(NSLocalizedString("pomodoro.powerSaving", comment: ""))
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                )
                .padding(.trailing, 8)
            }

            // 日历按钮（仅icon）
            Button(action: { showCalendar = true }) {
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                    )
            }
            .padding(.trailing, 8)

            // 我的番茄园按钮（仅icon）
            Button(action: { showTomatoGarden = true }) {
                Text("🍅")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.1))
                    )
            }
            .padding(.trailing, 8)

            // 深度专注模式按钮（可点亮的icon）
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
                                    colors: [Color.purple, Color.purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: (enableDeepFocus || focusService.isDeepFocusEnabled) ? "moon.fill" : "moon")
                        .font(.system(size: 20))
                        .foregroundColor((enableDeepFocus || focusService.isDeepFocusEnabled) ? .white : .gray)
                }
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
                    // 当停止按钮进入圆环时显示红色发光效果
                    .shadow(
                        color: isStopButtonInCircle ? Color.red.opacity(0.6) : Color.clear,
                        radius: isStopButtonInCircle ? 20 : 0,
                        x: 0,
                        y: 0
                    )
                    .shadow(
                        color: isStopButtonInCircle ? Color.red.opacity(0.4) : Color.clear,
                        radius: isStopButtonInCircle ? 40 : 0,
                        x: 0,
                        y: 0
                    )
                    .animation(.easeInOut(duration: 0.3), value: isStopButtonInCircle)

                // Center Content
                VStack(spacing: 0) {
                    // Time Display (上方，加粗液态玻璃字体)
                    Text(formattedTime)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: colorScheme == .dark ? [
                                    Color.white,
                                    Color.cyan.opacity(0.8),
                                    Color.blue.opacity(0.6)
                                ] : [
                                    Color.blue,
                                    Color.purple,
                                    Color.blue.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: colorScheme == .dark ? .cyan.opacity(0.6) : .blue.opacity(0.4), radius: 20, x: 0, y: 0)
                        .shadow(color: .white.opacity(0.5), radius: 10, x: 0, y: 0)
                        .padding(.bottom, size * 0.15)

                    // 暂停/开始按钮（中心）- No background box
                    if focusService.isRunning {
                        Button(action: togglePauseResume) {
                            Image(systemName: focusService.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: size * 0.12, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: focusService.isPaused ? [
                                            Color.green,
                                            Color.green.opacity(0.7)
                                        ] : [
                                            Color.orange,
                                            Color.orange.opacity(0.7)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .scaleEffect(focusService.isPaused ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: focusService.isPaused)
                        }
                    } else {
                        // 状态文字
                        Text(statusText)
                            .font(.title3)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                    }
                }
                .onAppear {
                    // 保存圆环中心和半径用于拖拽检测
                    circleCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    circleRadius = size / 2
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
                // 拖拽停止按钮
                draggableStopButton
            }
        }
    }

    // MARK: - Draggable Stop Button

    private var draggableStopButton: some View {
        VStack(spacing: 20) {
            // 提示文字（只在拖动时显示）
            if isDraggingStop {
                Text(NSLocalizedString("pomodoro.dragToStop", comment: "Drag button instruction"))
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }

            // 停止按钮
            ZStack {
                // 光圈效果（拖动时显示）
                if isDraggingStop {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.8),
                                    Color.red.opacity(0.3),
                                    Color.red.opacity(0.8)
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

                // 停止文字 (只显示一个，根据语言自动选择)
                Text(NSLocalizedString("pomodoro.stop", comment: "Stop button"))
                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDraggingStop ? [
                                Color.red,
                                Color.red.opacity(0.7)
                            ] : [
                                Color.gray,
                                Color.gray.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isDraggingStop ? .red.opacity(0.5) : .clear, radius: 10, x: 0, y: 0)
            }
            .offset(stopButtonOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDraggingStop {
                            isDraggingStop = true
                            // 开始震动
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }

                        stopButtonOffset = value.translation

                        // 实时检测是否进入圆环（向上拖拽超过200点）
                        let draggedUpDistance = -value.translation.height
                        let minimumDragDistance: CGFloat = 200
                        let wasInCircle = isStopButtonInCircle
                        isStopButtonInCircle = draggedUpDistance >= minimumDragDistance

                        // 持续震动
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()

                        // 进入圆环时额外震动提示
                        if isStopButtonInCircle && !wasInCircle {
                            let strongGenerator = UIImpactFeedbackGenerator(style: .heavy)
                            strongGenerator.impactOccurred()
                        }
                    }
                    .onEnded { value in
                        // 检查是否拖到圆环内（向上拖拽超过200点即认为进入圆环）
                        // 使用translation.height的负值来判断向上拖拽的距离
                        let draggedUpDistance = -value.translation.height
                        let minimumDragDistance: CGFloat = 200  // 最小拖拽距离

                        if draggedUpDistance >= minimumDragDistance {
                            // 拖拽距离足够 - 确认停止
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)

                            withAnimation(.spring()) {
                                stopButtonOffset = .zero
                                isDraggingStop = false
                                isStopButtonInCircle = false  // 重置状态
                            }

                            // 延迟一下再结束session，让动画完成
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                endSession()
                            }
                        } else {
                            // 拖拽距离不够 - 取消
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.warning)

                            withAnimation(.spring()) {
                                stopButtonOffset = .zero
                                isDraggingStop = false
                                isStopButtonInCircle = false  // 重置状态
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
                // Tomato Image with Animation
                Image(tomato.type.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .scaleEffect(showCompletionAnimation ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCompletionAnimation)

                // Congratulations Text
                VStack(spacing: 8) {
                    Text(NSLocalizedString("pomodoro.congratulations", comment: "Congratulations message"))
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text(tomato.type.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)

                    Text(tomato.type.description)
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
                            value: tomato.formattedDuration,
                            label: NSLocalizedString("pomodoro.focusDuration", comment: "Focus duration")
                        )

                        StatItem(
                            icon: "star.fill",
                            value: "+\(Int(tomato.focusDuration / 60 / 5))",
                            label: NSLocalizedString("pomodoro.pointsEarned", comment: "Points earned")
                        )
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)

                // View Garden Button
                Button(action: {
                    showCompletionAnimation = false
                    earnedTomato = nil
                    showTomatoGarden = true
                }) {
                    HStack(spacing: 8) {
                        Text("🍅")
                            .font(.system(size: 20))
                        Text(NSLocalizedString("pomodoro.viewGarden", comment: "View garden button"))
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)

                // Dismiss Button
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
        // 使用剩余时间计算进度（从满到空）
        let progress = focusService.elapsedTime / focusService.pomodoroDuration
        return min(CGFloat(progress), 1.0)
    }

    private var formattedTime: String {
        // 显示剩余时间（倒计时）
        let seconds = Int(focusService.remainingTime)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private var statusText: String {
        if focusService.isCompleted {
            return NSLocalizedString("pomodoro.completed", comment: "Pomodoro completed")
        } else if focusService.isPaused {
            return NSLocalizedString("focus.sessionPaused", comment: "Session paused")
        } else if focusService.isRunning {
            return NSLocalizedString("focus.sessionActive", comment: "Session active")
        } else {
            return NSLocalizedString("pomodoro.focusMode", comment: "Pomodoro focus")
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

    // MARK: - Deep Focus UI Components

    /// 深度专注模式开关（开始前）
    private var deepFocusToggleSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(
                            enableDeepFocus ?
                                LinearGradient(
                                    colors: [Color.purple, Color.purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: enableDeepFocus ? "moon.fill" : "moon")
                        .font(.system(size: 18))
                        .foregroundColor(enableDeepFocus ? .white : .gray)
                }

                // 文字说明
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("pomodoro.deepFocusMode", comment: "Deep focus mode"))
                        .font(.body.weight(.medium))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)

                    Text(NSLocalizedString("pomodoro.autoOptimize", comment: "Auto optimize"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 信息按钮
                Button(action: { showDeepFocusInfo = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .padding(.trailing, 8)

                // Toggle开关
                Toggle("", isOn: $enableDeepFocus)
                    .labelsHidden()
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

            // 提示文字
            if enableDeepFocus {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)

                    Text(NSLocalizedString("pomodoro.deepFocusReady", comment: "Deep focus ready"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: enableDeepFocus)
    }

    /// 深度专注状态指示器（运行中）
    private var deepFocusStatusBanner: some View {
        HStack(spacing: 12) {
            // 图标动画
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: "moon.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
            }

            // 状态文字
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("pomodoro.deepFocusActive", comment: "Deep focus active"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text(NSLocalizedString("pomodoro.deepFocusStatus", comment: "Deep focus status"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 关闭按钮
            Button(action: {
                focusService.toggleDeepFocus()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color.purple.opacity(colorScheme == .dark ? 0.2 : 0.1),
                    Color.purple.opacity(colorScheme == .dark ? 0.1 : 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Original Actions (Updated)

    private func startSession_old() {
        // 旧版本，已更新到上面
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

            // Add tomato to garden
            let tomato = tomatoGarden.addTomato(from: completedSession)
            earnedTomato = tomato

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
