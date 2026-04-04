import Foundation
import Combine

@MainActor
final class DiscordRPCManager: ObservableObject {
    @Published var isConnected = false
    @Published var isEnabled = true

    private var socket: Int32 = -1
    private var updateTask: Task<Void, Never>?
    private var nonce = 0
    private let clientId = "1192124994039697408"

    func connect() {
        guard isEnabled else { return }
        Task.detached { [weak self] in
            await self?.doConnect()
        }
    }

    func disconnect() {
        updateTask?.cancel()
        updateTask = nil
        if socket >= 0 {
            close(socket)
            socket = -1
        }
        isConnected = false
    }

    func updatePresence(gameName: String?, placeId: String?, elapsed: TimeInterval) {
        guard isConnected, isEnabled else { return }
        let details = gameName ?? "In Lobby"
        let state = "via SpoofTrap"

        var activity: [String: Any] = [
            "details": details,
            "state": state,
            "timestamps": ["start": Int(Date().timeIntervalSince1970 - elapsed)]
        ]

        if let placeId {
            activity["buttons"] = [
                ["label": "Join Game", "url": "https://www.roblox.com/games/\(placeId)"]
            ]
        }

        activity["assets"] = [
            "large_image": "spooftrap_icon",
            "large_text": "SpoofTrap",
            "small_image": "roblox_icon",
            "small_text": gameName ?? "Roblox"
        ]

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": activity],
            "nonce": "\(nextNonce())"
        ]

        sendFrame(opcode: 1, payload: payload)
    }

    func clearPresence() {
        guard isConnected else { return }
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": ProcessInfo.processInfo.processIdentifier],
            "nonce": "\(nextNonce())"
        ]
        sendFrame(opcode: 1, payload: payload)
    }

    // MARK: - IPC

    private func doConnect() async {
        for i in 0..<10 {
            let path = ipcPath(i)
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = path.utf8CString
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                    for (idx, byte) in pathBytes.enumerated() where idx < 104 {
                        dest[idx] = byte
                    }
                }
            }

            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, addrLen)
                }
            }

            if result == 0 {
                await MainActor.run { self.socket = fd }
                await handshake()
                return
            } else {
                Darwin.close(fd)
            }
        }
    }

    private func handshake() async {
        let payload: [String: Any] = ["v": 1, "client_id": clientId]
        sendFrame(opcode: 0, payload: payload)

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(socket, &buffer, buffer.count)
        if bytesRead > 8 {
            await MainActor.run { self.isConnected = true }
        }
    }

    private func sendFrame(opcode: UInt32, payload: [String: Any]) {
        guard socket >= 0,
              let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var header = [UInt8](repeating: 0, count: 8)
        header.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: UInt32.self, capacity: 2) { intPtr in
                intPtr[0] = opcode.littleEndian
                intPtr[1] = UInt32(jsonData.count).littleEndian
            }
        }

        var frame = Data(header)
        frame.append(jsonData)
        frame.withUnsafeBytes { ptr in
            _ = write(socket, ptr.baseAddress!, frame.count)
        }
    }

    private func ipcPath(_ index: Int) -> String {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"]
            ?? ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"]
            ?? "/tmp"
        return "\(tmpDir)discord-ipc-\(index)"
    }

    private func nextNonce() -> Int {
        nonce += 1
        return nonce
    }
}
