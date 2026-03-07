//
//  PracticeLibraryView.swift
//  StudyAI
//
//  Main screen for the Practice Library — shows all past sessions with filter/sort,
//  and allows creating new sessions via the "+ New" FAB.
//

import SwiftUI

struct PracticeLibraryView: View {
    @StateObject private var sessionManager = PracticeSessionManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    // Filter & sort
    @State private var selectedSubject: String = "All"
    @State private var sortOrder: SortOrder = .newest

    // Navigation
    @State private var selectedSession: PracticeSession? = nil
    @State private var showingNewPractice: Bool = false

    // Delete confirmation
    @State private var sessionToDelete: PracticeSession? = nil
    @State private var showingDeleteConfirm: Bool = false

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
        sessionManager.loadAllSessionsPublic()
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
        ZStack(alignment: .bottomTrailing) {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                sessionList
            }

            // FAB
            Button(action: { showingNewPractice = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.body.bold())
                    Text(NSLocalizedString("common.new", comment: ""))
                        .font(.subheadline.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(themeManager.accentColor)
                .cornerRadius(28)
                .shadow(color: themeManager.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 28)
        }
        .navigationTitle(NSLocalizedString("practiceLibrary.title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingNewPractice) {
            NewPracticeSheet { session in
                // Push to QuestionSheetView after sheet dismisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    selectedSession = session
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Subject chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(subjectList, id: \.self) { subject in
                        Button(action: { selectedSubject = subject }) {
                            Text(subject == "All" ? NSLocalizedString("practiceLibrary.filterAll", comment: "") : subject)
                                .font(.caption.bold())
                                .foregroundColor(selectedSubject == subject ? .white : themeManager.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(selectedSubject == subject ? themeManager.accentColor : Color.gray.opacity(0.12))
                                .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Sort menu
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
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Session List

    private var sessionList: some View {
        Group {
            if filteredSorted.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSorted) { session in
                            Button(action: { selectedSession = session }) {
                                PracticeSessionCard(session: session) {
                                    sessionToDelete = session
                                    showingDeleteConfirm = true
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 100)
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
