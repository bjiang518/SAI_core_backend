//
//  SessionHistoryView.swift
//  StudyAI
//
//  Created by Claude Code on 8/31/25.
//

import SwiftUI

struct SessionHistoryView: View {
    @StateObject private var railwayService = RailwayArchiveService.shared
    @State private var sessions: [SessionSummary] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var selectedViewMode: ViewMode = .list
    @State private var selectedSubject: SubjectCategory?
    @State private var searchText = ""
    
    private func colorForSubject(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "brown": return .brown
        case "teal": return .teal
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }
    
    enum ViewMode: String, CaseIterable {
        case list = "List"
        case calendar = "Calendar"
        case subjects = "Subjects"
        
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .calendar: return "calendar"
            case .subjects: return "books.vertical"
            }
        }
    }
    
    var filteredSessions: [SessionSummary] {
        var filtered = sessions
        
        // Filter by subject if selected
        if let selectedSubject = selectedSubject {
            filtered = filtered.filter { $0.subject == selectedSubject.rawValue }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { session in
                session.title.localizedCaseInsensitiveContains(searchText) ||
                session.subject.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // View Mode Picker
                Picker("View Mode", selection: $selectedViewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selected view mode
                if isLoading {
                    Spacer()
                    ProgressView("Loading sessions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessions.isEmpty && !errorMessage.isEmpty {
                    ErrorView(message: errorMessage) {
                        Task {
                            await loadSessions()
                        }
                    }
                } else if sessions.isEmpty {
                    EmptySessionsView()
                } else {
                    switch selectedViewMode {
                    case .list:
                        SessionListView(
                            sessions: filteredSessions,
                            searchText: $searchText,
                            selectedSubject: $selectedSubject
                        )
                    case .calendar:
                        SessionCalendarView(sessions: filteredSessions)
                    case .subjects:
                        SubjectCodebookView(sessions: sessions)
                    }
                }
            }
            .navigationTitle("Mistake Notebook")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadSessions()
            }
            .onAppear {
                if sessions.isEmpty {
                    Task {
                        await loadSessions()
                    }
                }
            }
        }
    }
    
    private func loadSessions() async {
        isLoading = true
        errorMessage = ""
        
        do {
            let loadedSessions = try await railwayService.fetchArchivedSessions()
            await MainActor.run {
                sessions = loadedSessions
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Session List View

struct SessionListView: View {
    let sessions: [SessionSummary]
    @Binding var searchText: String
    @Binding var selectedSubject: SubjectCategory?
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and Filter Bar
            VStack(spacing: 12) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search sessions...", text: $searchText)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                // Subject Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        SubjectFilterChip(
                            title: "All",
                            isSelected: selectedSubject == nil,
                            action: { selectedSubject = nil }
                        )
                        
                        ForEach(SubjectCategory.allCases, id: \.self) { subject in
                            let count = sessions.filter { $0.subject == subject.rawValue }.count
                            if count > 0 {
                                SubjectFilterChip(
                                    title: "\(subject.rawValue) (\(count))",
                                    isSelected: selectedSubject == subject,
                                    action: { selectedSubject = subject }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            
            // Sessions List
            if sessions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No sessions match your filters")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Button("Clear filters") {
                        searchText = ""
                        selectedSubject = nil
                    }
                    .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sessions) { session in
                    NavigationLink(destination: SessionDetailView(sessionId: session.id)) {
                        SessionListCard(session: session)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

// MARK: - Session List Card

struct SessionListCard: View {
    let session: SessionSummary
    
    private func colorForSubject(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "brown": return .brown
        case "teal": return .teal
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Subject Icon
                if let category = SubjectCategory(rawValue: session.subject) {
                    Image(systemName: category.icon)
                        .foregroundColor(colorForSubject(category.color))
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    Text(session.subject)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text(session.sessionDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Statistics
            HStack(spacing: 20) {
                StatItem(
                    icon: "questionmark.circle",
                    value: "\(session.questionCount)",
                    label: "Questions"
                )
                
                StatItem(
                    icon: "checkmark.seal",
                    value: "\(Int(session.overallConfidence * 100))%",
                    label: "Confidence"
                )
                
                StatItem(
                    icon: "eye",
                    value: "\(session.reviewCount)",
                    label: "Reviews"
                )
                
                Spacer()
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Subject Filter Chip

struct SubjectFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.blue)
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Empty Sessions View

struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "archivebox")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Sessions Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your archived homework sessions will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Complete homework parsing and tap 'Save' to add sessions to your mistake notebook")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error Loading Sessions")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                retry()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Placeholder Views

struct SessionCalendarView: View {
    let sessions: [SessionSummary]
    @State private var selectedMonth = Date()
    @State private var selectedDate: Date?
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    // Group sessions by date
    private var sessionsByDate: [Date: [SessionSummary]] {
        Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.sessionDate)
        }
    }
    
    // Get days for the current month
    private var monthDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return []
        }
        
        let startOfMonth = monthInterval.start
        let endOfMonth = monthInterval.end
        
        // Find the first day of the week containing the start of the month
        let startWeekday = calendar.component(.weekday, from: startOfMonth)
        let daysFromStartOfWeek = startWeekday - calendar.firstWeekday
        let firstDayOfCalendar = calendar.date(byAdding: .day, value: -daysFromStartOfWeek, to: startOfMonth)!
        
        var days: [Date] = []
        var currentDate = firstDayOfCalendar
        
        // Generate 42 days (6 weeks * 7 days) for consistent grid
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private var sessionsForSelectedDate: [SessionSummary] {
        guard let selectedDate = selectedDate else { return [] }
        return sessionsByDate[calendar.startOfDay(for: selectedDate)] ?? []
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(dateFormatter.string(from: selectedMonth))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            // Weekday headers
            HStack {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(monthDays, id: \.self) { date in
                    CalendarDayView(
                        date: date,
                        selectedMonth: selectedMonth,
                        selectedDate: selectedDate,
                        sessions: sessionsByDate[calendar.startOfDay(for: date)] ?? [],
                        onTap: { selectedDate = date }
                    )
                }
            }
            .padding(.horizontal)
            
            // Sessions for selected date
            if !sessionsForSelectedDate.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sessions on \(selectedDate!, style: .date)")
                            .font(.headline)
                            .foregroundColor(.black)
                        Spacer()
                        Text("\(sessionsForSelectedDate.count) session(s)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(sessionsForSelectedDate) { session in
                                NavigationLink(destination: SessionDetailView(sessionId: session.id)) {
                                    SessionListCard(session: session)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            Spacer()
        }
    }
    
    private func previousMonth() {
        selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
    }
    
    private func nextMonth() {
        selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
    }
}

// MARK: - Calendar Day View

struct CalendarDayView: View {
    let date: Date
    let selectedMonth: Date
    let selectedDate: Date?
    let sessions: [SessionSummary]
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    private func colorForSubject(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "brown": return .brown
        case "teal": return .teal
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }
    
    private var isInCurrentMonth: Bool {
        calendar.isDate(date, equalTo: selectedMonth, toGranularity: .month)
    }
    
    private var isSelected: Bool {
        if let selectedDate = selectedDate {
            return calendar.isDate(date, inSameDayAs: selectedDate)
        }
        return false
    }
    
    private var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    private var dayNumber: String {
        String(calendar.component(.day, from: date))
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(dayNumber)
                    .font(.system(size: 16, weight: isToday ? .bold : .medium))
                    .foregroundColor(textColor)
                
                // Session indicators
                HStack(spacing: 2) {
                    ForEach(0..<min(sessions.count, 3), id: \.self) { index in
                        Circle()
                            .fill(subjectColor(for: sessions[index]))
                            .frame(width: 4, height: 4)
                    }
                    
                    if sessions.count > 3 {
                        Text("+")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                }
                .frame(height: 8)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 0)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var textColor: Color {
        if !isInCurrentMonth {
            return .gray.opacity(0.5)
        } else if isToday {
            return .blue
        } else {
            return .black
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue.opacity(0.1)
        } else if isToday {
            return .blue.opacity(0.05)
        } else if !sessions.isEmpty {
            return .green.opacity(0.05)
        } else {
            return .clear
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return .blue
        } else {
            return .clear
        }
    }
    
    private func subjectColor(for session: SessionSummary) -> Color {
        if let category = SubjectCategory(rawValue: session.subject) {
            return colorForSubject(category.color)
        }
        return .gray
    }
}

struct SubjectCodebookView: View {
    let sessions: [SessionSummary]
    @State private var selectedSubject: SubjectCategory?
    
    private func colorForSubject(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "brown": return .brown
        case "teal": return .teal
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }
    
    // Group sessions by subject
    private var sessionsBySubject: [SubjectCategory: [SessionSummary]] {
        var grouped: [SubjectCategory: [SessionSummary]] = [:]
        
        for session in sessions {
            let category = SubjectCategory(rawValue: session.subject) ?? .other
            grouped[category, default: []].append(session)
        }
        
        // Sort sessions within each subject by date (newest first)
        for category in grouped.keys {
            grouped[category] = grouped[category]?.sorted { $0.sessionDate > $1.sessionDate }
        }
        
        return grouped
    }
    
    // Get subjects that have sessions, sorted by session count
    private var availableSubjects: [SubjectCategory] {
        sessionsBySubject.keys.sorted { category1, category2 in
            let count1 = sessionsBySubject[category1]?.count ?? 0
            let count2 = sessionsBySubject[category2]?.count ?? 0
            return count1 > count2
        }
    }
    
    private var selectedSubjectSessions: [SessionSummary] {
        guard let selectedSubject = selectedSubject else { return [] }
        return sessionsBySubject[selectedSubject] ?? []
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Subject list (left sidebar)
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("Subjects")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                
                // Subject list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(availableSubjects, id: \.self) { subject in
                            SubjectCodebookRow(
                                subject: subject,
                                sessionCount: sessionsBySubject[subject]?.count ?? 0,
                                isSelected: selectedSubject == subject,
                                onTap: {
                                    selectedSubject = selectedSubject == subject ? nil : subject
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(width: 160)
            .background(Color.gray.opacity(0.05))
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1)
            
            // Sessions for selected subject (right content)
            if let selectedSubject = selectedSubject {
                VStack(alignment: .leading, spacing: 16) {
                    // Subject header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: selectedSubject.icon)
                                .foregroundColor(colorForSubject(selectedSubject.color))
                                .font(.title2)
                            
                            Text(selectedSubject.rawValue)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Spacer()
                        }
                        
                        Text("\(selectedSubjectSessions.count) sessions")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Sessions list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(selectedSubjectSessions) { session in
                                SubjectSessionCard(session: session)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    Spacer()
                }
            } else {
                // No subject selected
                VStack(spacing: 20) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Select a Subject")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                    
                    Text("Choose a subject from the left to view your sessions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Auto-select the subject with the most sessions
            if selectedSubject == nil && !availableSubjects.isEmpty {
                selectedSubject = availableSubjects.first
            }
        }
    }
}

// MARK: - Subject Codebook Row

struct SubjectCodebookRow: View {
    let subject: SubjectCategory
    let sessionCount: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    private func colorForSubject(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "brown": return .brown
        case "teal": return .teal
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Subject icon
                Image(systemName: subject.icon)
                    .foregroundColor(colorForSubject(subject.color))
                    .font(.title3)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(subject.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                        .lineLimit(1)
                    
                    Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Subject Session Card

struct SubjectSessionCard: View {
    let session: SessionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundColor(.black)
                        .lineLimit(2)
                    
                    Text(session.sessionDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Quick stats
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("\(session.questionCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(Int(session.overallConfidence * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                    }
                }
            }
            
            // Review info
            if session.reviewCount > 0 {
                HStack {
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Reviewed \(session.reviewCount) time\(session.reviewCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    SessionHistoryView()
}