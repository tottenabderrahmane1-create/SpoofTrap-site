import Foundation

struct GameSession: Identifiable, Codable {
    let id: String
    var gameName: String
    var placeId: String
    var startTime: Date
    var duration: TimeInterval
    var serverRegion: String
    var preset: String
}

@MainActor
final class GameHistoryManager: ObservableObject {
    @Published var sessions: [GameSession] = []

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("SpoofTrap", isDirectory: true)
            .appendingPathComponent("game_history.json")
    }

    init() {
        loadHistory()
    }

    func recordSession(gameName: String, placeId: String, serverRegion: String, preset: String, duration: TimeInterval) {
        let session = GameSession(
            id: UUID().uuidString,
            gameName: gameName,
            placeId: placeId,
            startTime: Date().addingTimeInterval(-duration),
            duration: duration,
            serverRegion: serverRegion,
            preset: preset
        )
        sessions.insert(session, at: 0)

        if sessions.count > 100 {
            sessions = Array(sessions.prefix(100))
        }
        saveHistory()
    }

    func clearHistory() {
        sessions.removeAll()
        saveHistory()
    }

    var recentSessions: [GameSession] {
        Array(sessions.prefix(5))
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: storageURL),
              let saved = try? JSONDecoder().decode([GameSession].self, from: data) else { return }
        sessions = saved
    }

    private func saveHistory() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: storageURL, options: .atomic)
        } catch {}
    }
}
