import Foundation
import Combine

@MainActor
final class RobloxLogWatcher: ObservableObject {
    @Published var currentPlaceId: String?
    @Published var currentJobId: String?
    @Published var currentGameName: String?
    @Published var currentServerIP: String?
    @Published var currentRegion: String?
    @Published var currentPing: String?
    @Published var isInGame: Bool = false
    @Published var disconnected: Bool = false

    private var watchTask: Task<Void, Never>?
    private var lastFileOffset: UInt64 = 0
    private var logFileURL: URL?

    private static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Roblox")
    }

    func startWatching() {
        stopWatching()
        logFileURL = Self.findLatestLog()
        lastFileOffset = logFileURL.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.size] as? UInt64 } ?? 0

        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.pollLog()
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func pollLog() {
        guard let url = logFileURL ?? Self.findLatestLog() else { return }
        if logFileURL == nil { logFileURL = url }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        handle.seek(toFileOffset: lastFileOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        lastFileOffset += UInt64(data.count)

        guard let text = String(data: data, encoding: .utf8) else { return }

        text.enumerateLines { line, _ in
            self.parseLine(line)
        }
    }

    private func parseLine(_ line: String) {
        // Detect game join: "[FLog::Output] ! Joining game 'XXXXXXXX-...' place NNNNN"
        if line.contains("Joining game") || line.contains("joining game") {
            if let range = line.range(of: "place (\\d+)", options: .regularExpression) {
                let placeStr = line[range].replacingOccurrences(of: "place ", with: "")
                currentPlaceId = placeStr
                isInGame = true
                disconnected = false
                resolveGameName(placeId: placeStr)
            }
            if let range = line.range(of: "'([0-9a-fA-F\\-]+)'", options: .regularExpression) {
                let raw = String(line[range])
                currentJobId = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            }
        }

        // Detect server IP: "UDMUX Address = X.X.X.X"
        if line.contains("UDMUX") || line.contains("udmux") {
            if let range = line.range(of: "(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})", options: .regularExpression) {
                let ip = String(line[range])
                currentServerIP = ip
                resolveRegion(ip: ip)
            }
        }

        // Detect disconnect
        if line.contains("Disconnected") || line.contains("Connection lost") || line.contains("Kicked") {
            isInGame = false
            disconnected = true
        }

        // Detect successful teleport (re-joining)
        if line.contains("Teleport") && line.contains("Started") {
            disconnected = false
        }
    }

    private func resolveGameName(placeId: String) {
        Task {
            guard let url = URL(string: "https://games.roblox.com/v1/games/multiget-place-details?placeIds=\(placeId)") else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = json.first,
                  let name = first["name"] as? String else { return }
            await MainActor.run { self.currentGameName = name }
        }
    }

    private func resolveRegion(ip: String) {
        Task {
            guard let url = URL(string: "http://ip-api.com/json/\(ip)?fields=country,regionName,city,query,lat,lon") else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let region = json["regionName"] as? String ?? ""
            let city = json["city"] as? String ?? ""
            let country = json["country"] as? String ?? ""

            let display = [city, region, country].filter { !$0.isEmpty }.joined(separator: ", ")
            await MainActor.run {
                self.currentRegion = display.isEmpty ? "Unknown" : display
            }
        }
    }

    private static func findLatestLog() -> URL? {
        let dir = logDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        return files
            .filter { $0.pathExtension == "log" || $0.lastPathComponent.hasPrefix("log_") }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return d1 > d2
            }
            .first
    }
}
