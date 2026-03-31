import Foundation

struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var launchCount: Int
    var successful: Bool
    var proxyMode: String
    var preset: String
    
    init(proxyMode: String, preset: String) {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.launchCount = 0
        self.successful = false
        self.proxyMode = proxyMode
        self.preset = preset
    }
    
    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
    
    var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

@MainActor
final class SessionStats: ObservableObject {
    @Published var currentSession: SessionRecord?
    @Published var sessionHistory: [SessionRecord] = []
    @Published private(set) var totalSessions: Int = 0
    @Published private(set) var successfulSessions: Int = 0
    @Published private(set) var totalPlayTime: TimeInterval = 0
    
    private let fileManager = FileManager.default
    private var updateTimer: Timer?
    
    init() {
        loadHistory()
        calculateStats()
    }
    
    var isActive: Bool { currentSession != nil }
    
    var currentDuration: String {
        currentSession?.durationFormatted ?? "—"
    }
    
    var currentLaunches: Int {
        currentSession?.launchCount ?? 0
    }
    
    var successRate: Double {
        totalSessions > 0 ? Double(successfulSessions) / Double(totalSessions) * 100 : 0
    }
    
    var successRateFormatted: String {
        String(format: "%.0f%%", successRate)
    }
    
    var totalPlayTimeFormatted: String {
        formatDuration(totalPlayTime)
    }
    
    var todaySessions: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return sessionHistory.filter { calendar.startOfDay(for: $0.startTime) == today }.count
    }
    
    var todayPlayTime: TimeInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return sessionHistory
            .filter { calendar.startOfDay(for: $0.startTime) == today }
            .reduce(0) { $0 + $1.duration }
    }
    
    var todayPlayTimeFormatted: String {
        formatDuration(todayPlayTime)
    }
    
    var weekSessions: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessionHistory.filter { $0.startTime >= weekAgo }.count
    }
    
    var averageSessionLength: TimeInterval {
        guard totalSessions > 0 else { return 0 }
        return totalPlayTime / Double(totalSessions)
    }
    
    var averageSessionFormatted: String {
        formatDuration(averageSessionLength)
    }
    
    func startSession(proxyMode: String, preset: String) {
        currentSession = SessionRecord(proxyMode: proxyMode, preset: preset)
        
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    
    func recordLaunch() {
        currentSession?.launchCount += 1
    }
    
    func markSuccess() {
        currentSession?.successful = true
    }
    
    func endSession() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        guard var session = currentSession else { return }
        session.endTime = Date()
        sessionHistory.insert(session, at: 0)
        
        if sessionHistory.count > 100 {
            sessionHistory = Array(sessionHistory.prefix(100))
        }
        
        currentSession = nil
        calculateStats()
        saveHistory()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm", minutes)
        } else {
            return "< 1m"
        }
    }
    
    private func calculateStats() {
        totalSessions = sessionHistory.count
        successfulSessions = sessionHistory.filter { $0.successful }.count
        totalPlayTime = sessionHistory.reduce(0) { $0 + $1.duration }
    }
    
    private var settingsURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDirectory = appSupport ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        
        return baseDirectory
            .appendingPathComponent("SpoofTrap/session-history.json")
    }
    
    private func loadHistory() {
        guard let data = try? Data(contentsOf: settingsURL),
              let saved = try? JSONDecoder().decode([SessionRecord].self, from: data) else {
            return
        }
        sessionHistory = saved
    }
    
    private func saveHistory() {
        do {
            try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sessionHistory)
            try data.write(to: settingsURL)
        } catch {
            print("Failed to save session history: \(error)")
        }
    }
}
