//
//  PracticeLibraryView.swift
//  StudyAI
//
//  Main screen for the Practice Library — shows all past sessions with filter/sort,
//  and allows creating new sessions via the nav-bar "+ New" button.
//

import SwiftUI

struct PracticeLibraryView: View {
    @StateObject private var sessionManager = PracticeSessionManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme

    // Filter & sort
    @State private var selectedSubject: String = "All"
    @State private var selectedStatus: StatusFilter = .all
    @State private var sortOrder: SortOrder = .newest

    // ── Shortcut pre-configuration ──────────────────────────────────────
    /// When set, the New Practice sheet opens immediately with this config.
    struct ShortcutConfig {
        let tab: NewPracticeSheet.Tab
        let subject: String
        let conversationId: String?
    }

    private let shortcutConfig: ShortcutConfig?

    init(initialSubjectFilter: String? = nil, shortcutConfig: ShortcutConfig? = nil) {
        self.shortcutConfig = shortcutConfig
        if let subj = initialSubjectFilter {
            _selectedSubject = State(initialValue: subj)
        }
    }

    enum StatusFilter: CaseIterable {
        case all, ongoing, completed

        var displayName: String {
            switch self {
            case .all:       return NSLocalizedString("practiceLibrary.filterAll", comment: "")
            case .ongoing:   return NSLocalizedString("practiceLibrary.statusOngoing", comment: "")
            case .completed: return NSLocalizedString("practiceLibrary.statusCompleted", comment: "")
            }
        }
    }

    // Navigation
    @State private var selectedSession: PracticeSession? = nil
    @State private var showingNewPractice: Bool = false

    // Delete confirmation
    @State private var sessionToDelete: PracticeSession? = nil
    @State private var showingDeleteConfirm: Bool = false

    @Namespace private var subjectAnimation

    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case scoreHigh = "Score ↓"
        case incompletFirst = "Incomplete First"

        var displayName: String {
            switch self {
            case .newest: return NSLocalizedString("practiceLibrary.sortNewest", comment: "")
            case .oldest: return NSLocalizedString("practiceLibrary.sortOldest", comment: "")
            case .scoreHigh: return NSLocalizedString("practiceLibrary.sortScore", comment: "")
            case .incompletFirst: return NSLocalizedString("practiceLibrary.sortIncomplete", comment: "")
            }
        }
    }

    private var allSessions: [PracticeSession] {
        sessionManager.allSessionsPublished
    }

    private var subjectList: [String] {
        var subjects = ["All"]
        let unique = Set(allSessions.map { PracticeSessionManager.normalizeSubject($0.subject) }).sorted()
        subjects.append(contentsOf: unique)
        return subjects
    }

    private var filteredSorted: [PracticeSession] {
        var list = allSessions

        if selectedSubject != "All" {
            list = list.filter { PracticeSessionManager.normalizeSubject($0.subject) == selectedSubject }
        }

        switch selectedStatus {
        case .ongoing:   list = list.filter { !$0.isCompleted }
        case .completed: list = list.filter {  $0.isCompleted }
        case .all: break
        }

        switch sortOrder {
        case .newest:
            list.sort { $0.createdDate > $1.createdDate }
        case .oldest:
            list.sort { $0.createdDate < $1.createdDate }
        case .scoreHigh:
            list.sort { scoreOf($0) > scoreOf($1) }
        case .incompletFirst:
            list.sort { !$0.isCompleted && $1.isCompleted }
        }

        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter section — warm paper background (no grid)
            VStack(spacing: 0) {
                subjectSelector
                statusFilterBar
                sortBar
            }
            .background(
                colorScheme == .dark ? Color(hex: "2C2A26") : Color(hex: "FAF6EE")
            )

            // Session list — grid paper background, extends to bottom safe area only
            sessionList
                .background(gridPaperBackground.ignoresSafeArea(.all, edges: .bottom))
        }
        .navigationTitle(NSLocalizedString("practiceLibrary.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            sessionManager.updatePublishedState()
            // Open NewPracticeSheet immediately if a shortcut config was provided
            if shortcutConfig != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingNewPractice = true
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewPractice = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                        Text(NSLocalizedString("common.new", comment: ""))
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(themeManager.accentColor)
                }
            }
        }
        .sheet(isPresented: $showingNewPractice) {
            if let config = shortcutConfig {
                NewPracticeSheet(
                    onSessionCreated: { session in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedSession = session
                        }
                    },
                    initialTab: config.tab,
                    initialSubject: config.subject,
                    initialConversationId: config.conversationId
                )
            } else {
                NewPracticeSheet { session in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedSession = session
                    }
                }
            }
        }
        .navigationDestination(item: $selectedSession) { session in
            QuestionSheetView(session: session)
        }
        .alert(NSLocalizedString("practiceLibrary.deleteTitle", comment: ""), isPresented: $showingDeleteConfirm) {
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                if let s = sessionToDelete { sessionManager.deleteSession(id: s.id) }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("practiceLibrary.deleteMessage", comment: ""))
        }
    }

    // MARK: - Subject Selector (CompactSubjectSelector style)

    private var subjectSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(subjectList, id: \.self) { subject in
                        let isSelected = selectedSubject == subject
                        let label = subject == "All"
                            ? NSLocalizedString("practiceLibrary.filterAll", comment: "")
                            : PracticeSessionManager.localizeSubject(subject)

                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedSubject = subject
                                proxy.scrollTo(subject, anchor: .center)
                            }
                        }) {
                            Text(label)
                                .font(isSelected ? .subheadline : .caption)
                                .fontWeight(isSelected ? .bold : .medium)
                                .foregroundColor(isSelected ? themeManager.accentColor : .secondary)
                                .padding(.horizontal, isSelected ? 16 : 12)
                                .padding(.vertical, isSelected ? 10 : 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isSelected ? themeManager.accentColor.opacity(0.1) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(isSelected ? themeManager.accentColor : Color.clear, lineWidth: 1.5)
                                        )
                                )
                                .scaleEffect(isSelected ? 1.05 : 0.9)
                                .opacity(isSelected ? 1.0 : 0.65)
                        }
                        .buttonStyle(.plain)
                        .id(subject)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedSubject) { _, newValue in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(selectedSubject, anchor: .center)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Status Filter Bar

    private var statusFilterBar: some View {
        HStack(spacing: 0) {
            ForEach(StatusFilter.allCases, id: \.self) { status in
                let isSelected = selectedStatus == status
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedStatus = status
                    }
                }) {
                    Text(status.displayName)
                        .font(.caption.bold())
                        .foregroundColor(isSelected ? themeManager.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            isSelected
                                ? themeManager.accentColor.opacity(0.1)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(themeManager.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(action: { sortOrder = order }) {
                        Label(order.displayName, systemImage: sortOrder == order ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text(sortOrder.displayName)
                        .font(.caption)
                }
                .foregroundColor(themeManager.accentColor)
            }
            .padding(.trailing)
        }
        .padding(.bottom, 4)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Session List

    private var sessionList: some View {
        Group {
            if filteredSorted.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredSorted) { session in
                        PracticeSessionCard(session: session)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedSession = session }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    sessionToDelete = session
                                    showingDeleteConfirm = true
                                } label: {
                                    Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    // Bottom padding row
                    Color.clear
                        .frame(height: 80)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    // MARK: - Grid Paper Background (matches SuggestedTodosSection style)

    private var gridPaperBackground: some View {
        ZStack {
            // Warm paper base
            colorScheme == .dark ? Color(hex: "27251F") : Color(hex: "FAF6EE")

            Canvas { ctx, size in
                let spacing: CGFloat = 24
                let lineColor: Color = colorScheme == .dark
                    ? Color(hex: "4A4640").opacity(0.55)
                    : Color(hex: "B8C4C0").opacity(0.55)
                let style = StrokeStyle(lineWidth: 0.5, lineCap: .round)

                // Horizontal lines
                var y: CGFloat = spacing
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(lineColor), style: style)
                    y += spacing
                }

                // Vertical lines
                var x: CGFloat = spacing
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(lineColor), style: style)
                    x += spacing
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.4))
            Text(NSLocalizedString("practiceLibrary.emptyTitle", comment: ""))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(NSLocalizedString("practiceLibrary.emptySubtitle", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { showingNewPractice = true }) {
                Label(NSLocalizedString("practiceLibrary.generateFirst", comment: ""), systemImage: "plus")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.accentColor)
                    .cornerRadius(12)
            }
            Spacer()
        }
    }

    // MARK: - Helper

    private func scoreOf(_ session: PracticeSession) -> Double {
        let correct = session.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        let total = session.completedQuestionIds.count
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }
}
