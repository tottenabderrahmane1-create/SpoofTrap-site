import AppKit
import Foundation

@MainActor
final class BypassViewModel: ObservableObject {
    enum BypassState {
        case stopped
        case starting
        case running
        case stopping

        var title: String {
            switch self {
            case .stopped:
                return "Offline"
            case .starting:
                return "Starting"
            case .running:
                return "Live"
            case .stopping:
                return "Stopping"
            }
        }
    }

    enum ProxyPreset: String, CaseIterable, Codable, Identifiable {
        case stable
        case balanced
        case fast
        case custom

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }
    }

    enum ProxyScope: String, CaseIterable, Codable, Identifiable {
        case system
        case app

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app:
                return "App"
            case .system:
                return "System"
            }
        }
        
        var description: String {
            switch self {
            case .app:
                return "Recommended for Roblox"
            case .system:
                return "Sets system-wide proxy"
            }
        }
    }

    private struct StoredSettings: Codable {
        var robloxAppPath: String
        var customSpoofdpiPath: String
        var preset: ProxyPreset
        var proxyScope: ProxyScope
        var hybridLaunch: Bool
        var dnsHttpsURL: String
        var httpsChunkSize: Int
        var httpsDisorder: Bool
        var appLaunchDelay: Int
        var reducedMotion: Bool?
    }

    private struct SystemProxyState {
        var service: String
        var webEnabled: Bool
        var webServer: String
        var webPort: String
        var secureEnabled: Bool
        var secureServer: String
        var securePort: String
    }

    @Published private(set) var state: BypassState = .stopped
    @Published private(set) var logs: [String] = []
    @Published private(set) var robloxAppPath: String = ""
    @Published private(set) var customSpoofdpiPath: String = ""
    @Published private(set) var preset: ProxyPreset = .stable
    @Published private(set) var proxyScope: ProxyScope = .app
    @Published private(set) var hybridLaunch = false
    @Published private(set) var dnsHttpsURL = "https://1.1.1.1/dns-query"
    @Published private(set) var httpsChunkSize = 1
    @Published private(set) var httpsDisorder = true
    @Published private(set) var appLaunchDelay = 0
    @Published private(set) var reducedMotion = false
    @Published private(set) var resolvedBinaryPath: String?
    @Published private(set) var binaryAvailable = false
    @Published var fastFlagsManager = FastFlagsManager()
    
    // Pro Features
    @Published var proManager = ProManager()
    @Published var sessionStats = SessionStats()

    private let proxyAddress = "127.0.0.1:8080"
    private let proxyURL = "http://127.0.0.1:8080"
    private var spoofProcess: Process?
    private var outputPipe: Pipe?
    private var launchTask: Task<Void, Never>?
    private var systemProxyState: [SystemProxyState] = []
    private var isRestoringSettings = false
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init() {
        loadSettings()
        refreshEnvironmentSnapshot()
    }

    var isRunning: Bool {
        state == .running || state == .starting
    }

    var robloxInstalled: Bool {
        FileManager.default.fileExists(atPath: robloxAppPath)
    }

    var robloxDisplayPath: String {
        Self.displayPath(robloxAppPath)
    }

    var binaryDisplayPath: String {
        let path = resolvedBinaryPath ?? customSpoofdpiPath
        if path.isEmpty {
            return "Bundle / ~/Documents / PATH"
        }
        return Self.displayPath(path)
    }

    var selectedBinaryPath: String {
        customSpoofdpiPath
    }

    var actionTitle: String {
        isRunning ? "Stop Session" : "Start Session"
    }

    var actionSubtitle: String {
        isRunning ? "Terminate the proxy and restore normal routing." : "Launch spoofdpi and open Roblox through the selected flow."
    }

    var statusSummary: String {
        switch state {
        case .stopped:
            if !binaryAvailable {
                return "Choose a valid spoofdpi binary before starting."
            }
            if !robloxInstalled {
                return "Choose the Roblox app bundle you want SpoofTrap to open."
            }
            return "Ready to launch Roblox through the selected proxy mode."
        case .starting:
            return "Initializing the proxy and preparing the launch flow."
        case .running:
            return "The proxy is active and Roblox launch steps are running."
        case .stopping:
            return "Stopping the session and restoring the previous state."
        }
    }

    func toggleBypass() {
        if isRunning {
            stopBypass()
        } else {
            startBypass()
        }
    }

    func setRobloxAppPath(_ newValue: String) {
        robloxAppPath = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        persistSettings()
        refreshEnvironmentSnapshot()
    }

    func setCustomSpoofdpiPath(_ newValue: String) {
        customSpoofdpiPath = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        persistSettings()
        refreshEnvironmentSnapshot()
    }

    func resetBinaryPathOverride() {
        setCustomSpoofdpiPath("")
    }

    func applyPreset(_ newPreset: ProxyPreset) {
        preset = newPreset

        switch newPreset {
        case .stable:
            dnsHttpsURL = "https://1.1.1.1/dns-query"
            httpsChunkSize = 1
            httpsDisorder = true
            appLaunchDelay = 0
        case .balanced:
            dnsHttpsURL = "https://1.1.1.1/dns-query"
            httpsChunkSize = 2
            httpsDisorder = true
            appLaunchDelay = 0
        case .fast:
            dnsHttpsURL = "https://1.1.1.1/dns-query"
            httpsChunkSize = 4
            httpsDisorder = false
            appLaunchDelay = 0
        case .custom:
            break
        }

        persistSettings()
    }

    func setProxyScope(_ newScope: ProxyScope) {
        proxyScope = newScope
        persistSettings()
    }

    func setHybridLaunch(_ newValue: Bool) {
        hybridLaunch = newValue
        persistSettings()
    }

    func setLaunchDelay(_ newValue: Int) {
        appLaunchDelay = min(max(newValue, 0), 10)
        markCustomSettings()
    }

    func setDNSHttpsURL(_ newValue: String) {
        dnsHttpsURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        markCustomSettings()
    }

    func setChunkSize(_ newValue: Int) {
        httpsChunkSize = min(max(newValue, 1), 16)
        markCustomSettings()
    }

    func setHTTPSDisorder(_ newValue: Bool) {
        httpsDisorder = newValue
        markCustomSettings()
    }

    func setReducedMotion(_ newValue: Bool) {
        reducedMotion = newValue
        persistSettings()
    }

    func chooseRobloxApp() {
        guard !isRunning else {
            appendLog("Stop the session before changing the Roblox path.")
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Roblox.app"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.applicationBundle]
        } else {
            panel.allowedFileTypes = ["app"]
        }
        
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            panel.directoryURL = documentsURL
        }

        if panel.runModal() == .OK, let url = panel.url {
            setRobloxAppPath(url.path)
            appendLog("Roblox path updated to: \(Self.displayPath(url.path))")
        }
    }

    func chooseSpoofdpiBinary() {
        guard !isRunning else {
            appendLog("Stop the session before changing the spoofdpi binary.")
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose spoofdpi"
        panel.prompt = "Choose Binary"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            setCustomSpoofdpiPath(url.path)
            appendLog("spoofdpi override updated.")
        }
    }

    func revealRobloxInFinder() {
        guard robloxInstalled else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: robloxAppPath)])
    }

    func revealBinaryInFinder() {
        guard let resolvedBinaryPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: resolvedBinaryPath)])
    }

    func copyLogs() {
        let text = logs.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func startBypass() {
        guard !isRunning else { return }

        refreshEnvironmentSnapshot()
        resetConsole()
        state = .starting

        guard robloxInstalled else {
            appendLog("Roblox.app was not found at \(robloxDisplayPath).")
            state = .stopped
            return
        }

        guard binaryAvailable, let resolvedBinaryPath else {
            appendLog("spoofdpi is missing. Set a valid binary path or place it in ~/Documents.")
            state = .stopped
            return
        }

        appendLog("Profile loaded: \(preset.title)")
        appendLog("Proxy mode: \(proxyScope.title.lowercased())")
        appendLog("Using spoofdpi: \(Self.displayPath(resolvedBinaryPath))")
        appendLog("Roblox path: \(robloxDisplayPath)")

        if fastFlagsManager.isEnabled && fastFlagsManager.enabledCount > 0 {
            if fastFlagsManager.applyToRoblox(appPath: robloxAppPath) {
                appendLog("FastFlags applied: \(fastFlagsManager.enabledCount) flags")
            } else {
                appendLog("Warning: Failed to apply FastFlags")
            }
        }
        
        sessionStats.startSession(proxyMode: proxyScope.rawValue, preset: preset.rawValue)

        Task {
            await runPKill()
            await launchSpoofDPI()
        }
    }

    func stopBypass() {
        guard state != .stopped && state != .stopping else { return }

        state = .stopping
        launchTask?.cancel()
        launchTask = nil
        appendLog("Stopping SpoofTrap session.")
        
        sessionStats.endSession()

        if let process = spoofProcess, process.isRunning {
            process.terminate()
            appendLog("Sent terminate signal to spoofdpi.")
        }

        if proxyScope == .system {
            restoreSystemProxyMode()
        }

        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await runPKill()
            spoofProcess = nil
            outputPipe = nil
            state = .stopped
            appendLog("Bypass stopped.")
        }
    }

    nonisolated func forceCleanupForTermination() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "spoofdpi"]
        try? process.run()
        process.waitUntilExit()
    }

    private func launchSpoofDPI() async {
        refreshEnvironmentSnapshot()

        guard let binaryPath = resolvedBinaryPath else {
            appendLog("spoofdpi binary not found.")
            state = .stopped
            return
        }

        let binaryURL = URL(fileURLWithPath: binaryPath)
        let process = Process()
        let pipe = Pipe()

        process.executableURL = binaryURL
        process.currentDirectoryURL = binaryURL.deletingLastPathComponent()
        process.standardOutput = pipe
        process.standardError = pipe

        var arguments = [
            "--listen-addr", proxyAddress,
            "--dns-mode", "https",
            "--dns-https-url", dnsHttpsURL,
            "--https-split-mode", "chunk",
            "--https-chunk-size", String(httpsChunkSize)
        ]

        if httpsDisorder {
            arguments.append("--https-disorder")
        }

        process.arguments = arguments

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                return
            }

            Task { @MainActor [weak self] in
                output
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .filter { !$0.isEmpty }
                    .forEach { self?.appendLog($0) }
            }
        }

        process.terminationHandler = { [weak self] runningProcess in
            Task { @MainActor [weak self] in
                self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self?.appendLog("spoofdpi exited with code \(runningProcess.terminationStatus).")

                if self?.proxyScope == .system {
                    self?.restoreSystemProxyMode()
                }

                if self?.state != .stopping {
                    self?.state = .stopped
                }
            }
        }

        do {
            appendLog("Starting local bypass services...")
            try process.run()
            spoofProcess = process
            outputPipe = pipe
            state = .running
            appendLog("spoofdpi active on \(proxyAddress).")

            if proxyScope == .system {
                applySystemProxyMode()
            }

            scheduleLaunchFlow()
        } catch {
            appendLog("Failed to launch spoofdpi: \(error.localizedDescription)")
            state = .stopped
        }
    }

    private func scheduleLaunchFlow() {
        launchTask?.cancel()
        launchTask = Task { [weak self] in
            guard let self else { return }

            do {
                if self.proxyScope == .system {
                    await MainActor.run {
                        self.appendLog("Waiting for proxy to stabilize...")
                    }
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                }
                
                if self.appLaunchDelay > 0 {
                    await MainActor.run {
                        self.appendLog("Waiting \(self.appLaunchDelay)s before launching Roblox.")
                    }
                    try await Task.sleep(nanoseconds: UInt64(self.appLaunchDelay) * 1_000_000_000)
                }

                guard !Task.isCancelled, self.state == .running else { return }
                await MainActor.run {
                    self.launchRobloxWave(label: "Launching Roblox.app")
                }

                if self.hybridLaunch {
                    await MainActor.run {
                        self.appendLog("Hybrid relaunch enabled. Queuing a second wave in 2 seconds.")
                    }
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled, self.state == .running else { return }
                    await MainActor.run {
                        self.launchRobloxWave(label: "Launching hybrid follow-up wave")
                    }
                }

                await MainActor.run {
                    self.appendLog("Ready. Join flow active.")
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Launch flow cancelled.")
                }
            }
        }
    }

    private func launchRobloxWave(label: String) {
        appendLog(label)
        sessionStats.recordLaunch()

        if proxyScope == .system {
            let result = runTool("/usr/bin/open", ["-n", "-a", robloxAppPath])
            if result.status == 0 {
                appendLog("Roblox launched using system proxy mode.")
                sessionStats.markSuccess()
            } else {
                appendLog("Roblox launch failed: \(result.output.isEmpty ? "open returned \(result.status)." : result.output)")
            }
            return
        }

        let robloxBinaryPath = (robloxAppPath as NSString)
            .appendingPathComponent("Contents/MacOS/RobloxPlayer")
        
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: robloxBinaryPath) else {
            appendLog("RobloxPlayer binary not found at expected path.")
            let fallbackResult = runTool("/usr/bin/open", ["-n", "-a", robloxAppPath])
            if fallbackResult.status == 0 {
                appendLog("Fallback: Roblox launched without proxy injection.")
            } else {
                appendLog("Roblox launch failed.")
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: robloxBinaryPath)
        process.currentDirectoryURL = URL(fileURLWithPath: robloxAppPath).appendingPathComponent("Contents/MacOS")
        
        var environment = ProcessInfo.processInfo.environment
        environment["http_proxy"] = proxyURL
        environment["https_proxy"] = proxyURL
        environment["HTTP_PROXY"] = proxyURL
        environment["HTTPS_PROXY"] = proxyURL
        environment["ALL_PROXY"] = proxyURL
        process.environment = environment

        do {
            try process.run()
            appendLog("Roblox launched with proxy environment (PID: \(process.processIdentifier)).")
            sessionStats.markSuccess()
        } catch {
            appendLog("Failed to launch Roblox: \(error.localizedDescription)")
            let fallbackResult = runTool("/usr/bin/open", ["-n", "-a", robloxAppPath])
            if fallbackResult.status == 0 {
                appendLog("Fallback: Roblox launched via open command.")
                sessionStats.markSuccess()
            }
        }
    }

    private func runPKill() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "spoofdpi"]

        do {
            try process.run()
            process.waitUntilExit()
            appendLog("pkill -f spoofdpi completed with code \(process.terminationStatus).")
        } catch {
            appendLog("Failed to execute pkill: \(error.localizedDescription)")
        }
    }

    private func applySystemProxyMode() {
        let services = listNetworkServices()
        systemProxyState = services.map(captureProxyState)

        var successCount = 0
        for service in services {
            let webResult = runTool("/usr/sbin/networksetup", ["-setwebproxy", service, "127.0.0.1", "8080", "off"])
            let secureResult = runTool("/usr/sbin/networksetup", ["-setsecurewebproxy", service, "127.0.0.1", "8080", "off"])
            _ = runTool("/usr/sbin/networksetup", ["-setwebproxystate", service, "on"])
            _ = runTool("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "on"])
            
            if webResult.status == 0 && secureResult.status == 0 {
                successCount += 1
            }
        }

        if successCount > 0 {
            appendLog("System proxy enabled on \(successCount) service(s).")
        } else {
            appendLog("Warning: Could not set system proxy. Check macOS Privacy settings.")
        }
    }

    private func restoreSystemProxyMode() {
        guard !systemProxyState.isEmpty else { return }

        for state in systemProxyState {
            if state.webEnabled && !state.webServer.isEmpty {
                _ = runTool("/usr/sbin/networksetup", ["-setwebproxy", state.service, state.webServer, state.webPort, "off"])
                _ = runTool("/usr/sbin/networksetup", ["-setwebproxystate", state.service, "on"])
            } else {
                _ = runTool("/usr/sbin/networksetup", ["-setwebproxystate", state.service, "off"])
            }

            if state.secureEnabled && !state.secureServer.isEmpty {
                _ = runTool("/usr/sbin/networksetup", ["-setsecurewebproxy", state.service, state.secureServer, state.securePort, "off"])
                _ = runTool("/usr/sbin/networksetup", ["-setsecurewebproxystate", state.service, "on"])
            } else {
                _ = runTool("/usr/sbin/networksetup", ["-setsecurewebproxystate", state.service, "off"])
            }
        }

        systemProxyState.removeAll(keepingCapacity: false)
        appendLog("System proxy restored.")
    }

    private func listNetworkServices() -> [String] {
        let output = runTool("/usr/sbin/networksetup", ["-listallnetworkservices"]).output
        return output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }
    
    private func listActiveNetworkServices() -> [String] {
        let primaryServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN", "Thunderbolt Ethernet"]
        let allServices = listNetworkServices()
        
        var activeServices: [String] = []
        
        for service in primaryServices {
            if allServices.contains(service) {
                let hardwarePort = runTool("/usr/sbin/networksetup", ["-listallhardwareports"]).output
                if hardwarePort.contains(service) {
                    let ipResult = runTool("/usr/sbin/networksetup", ["-getinfo", service]).output
                    if ipResult.contains("IP address:") && !ipResult.contains("IP address: none") {
                        activeServices.append(service)
                    }
                }
            }
        }
        
        if activeServices.isEmpty {
            for service in allServices {
                if primaryServices.contains(service) || service.lowercased().contains("wi-fi") || service.lowercased().contains("ethernet") {
                    activeServices.append(service)
                }
            }
        }
        
        if activeServices.isEmpty && !allServices.isEmpty {
            if let wifi = allServices.first(where: { $0 == "Wi-Fi" }) {
                activeServices.append(wifi)
            } else {
                activeServices.append(allServices[0])
            }
        }
        
        return activeServices
    }

    private func captureProxyState(for service: String) -> SystemProxyState {
        let web = parseProxyState(from: runTool("/usr/sbin/networksetup", ["-getwebproxy", service]).output)
        let secure = parseProxyState(from: runTool("/usr/sbin/networksetup", ["-getsecurewebproxy", service]).output)

        return SystemProxyState(
            service: service,
            webEnabled: web.enabled,
            webServer: web.server,
            webPort: web.port,
            secureEnabled: secure.enabled,
            secureServer: secure.server,
            securePort: secure.port
        )
    }

    private func parseProxyState(from output: String) -> (enabled: Bool, server: String, port: String) {
        var enabled = false
        var server = ""
        var port = "8080"

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Enabled:") {
                enabled = trimmed.replacingOccurrences(of: "Enabled:", with: "").trimmingCharacters(in: .whitespaces) == "Yes"
            } else if trimmed.hasPrefix("Server:") {
                server = trimmed.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Port:") {
                port = trimmed.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        return (enabled, server, port)
    }

    private func runTool(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (process.terminationStatus, output)
    }

    private func markCustomSettings() {
        if preset != .custom {
            preset = .custom
        }
        persistSettings()
    }

    private func resetConsole() {
        logs.removeAll(keepingCapacity: true)
        appendLog("SpoofTrap initialized.")
    }

    private func refreshEnvironmentSnapshot() {
        resolvedBinaryPath = resolveSpoofDPIBinaryPath()
        binaryAvailable = resolvedBinaryPath != nil
    }

    private func resolveSpoofDPIBinaryPath() -> String? {
        let fileManager = FileManager.default
        let pathEnvironment = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathDirectories = pathEnvironment
            .split(separator: ":")
            .map(String.init)
        let appResourceURL = Bundle.main.resourceURL
        let nestedBundleResourceURL = Self.locateResourceBundle()?.resourceURL

        let candidates = [
            customSpoofdpiPath,
            appResourceURL?.appendingPathComponent("bin/spoofdpi").path ?? "",
            appResourceURL?.appendingPathComponent("spoofdpi").path ?? "",
            nestedBundleResourceURL?.appendingPathComponent("bin/spoofdpi").path ?? "",
            nestedBundleResourceURL?.appendingPathComponent("spoofdpi").path ?? "",
            NSString(string: "~/Documents/spoofdpi").expandingTildeInPath
        ] + pathDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent("spoofdpi").path }

        for candidate in candidates where !candidate.isEmpty && fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    private func loadSettings() {
        isRestoringSettings = true
        defer { isRestoringSettings = false }

        let defaults = Self.defaultSettings()

        guard
            let data = try? Data(contentsOf: settingsURL),
            let stored = try? JSONDecoder().decode(StoredSettings.self, from: data)
        else {
            robloxAppPath = defaults.robloxAppPath
            customSpoofdpiPath = defaults.customSpoofdpiPath
            preset = defaults.preset
            proxyScope = defaults.proxyScope
            hybridLaunch = defaults.hybridLaunch
            dnsHttpsURL = defaults.dnsHttpsURL
            httpsChunkSize = defaults.httpsChunkSize
            httpsDisorder = defaults.httpsDisorder
            appLaunchDelay = defaults.appLaunchDelay
            return
        }

        robloxAppPath = stored.robloxAppPath
        customSpoofdpiPath = stored.customSpoofdpiPath
        preset = stored.preset
        proxyScope = stored.proxyScope
        hybridLaunch = stored.hybridLaunch
        dnsHttpsURL = stored.dnsHttpsURL
        httpsChunkSize = stored.httpsChunkSize
        httpsDisorder = stored.httpsDisorder
        appLaunchDelay = stored.appLaunchDelay
        reducedMotion = stored.reducedMotion ?? false
    }

    private func persistSettings() {
        guard !isRestoringSettings else { return }

        let payload = StoredSettings(
            robloxAppPath: robloxAppPath,
            customSpoofdpiPath: customSpoofdpiPath,
            preset: preset,
            proxyScope: proxyScope,
            hybridLaunch: hybridLaunch,
            dnsHttpsURL: dnsHttpsURL,
            httpsChunkSize: httpsChunkSize,
            httpsDisorder: httpsDisorder,
            appLaunchDelay: appLaunchDelay,
            reducedMotion: reducedMotion
        )

        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            appendLog("Failed to persist settings: \(error.localizedDescription)")
        }
    }

    private var settingsURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDirectory = appSupport
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)

        return baseDirectory
            .appendingPathComponent("SpoofTrap", isDirectory: true)
            .appendingPathComponent("ui-settings.json")
    }

    private static func defaultSettings() -> StoredSettings {
        let robloxCandidates = [
            NSString(string: "~/Documents/Roblox.app").expandingTildeInPath,
            "/Applications/Roblox.app"
        ]

        let robloxPath = robloxCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? robloxCandidates[0]

        return StoredSettings(
            robloxAppPath: robloxPath,
            customSpoofdpiPath: "",
            preset: .stable,
            proxyScope: .system,
            hybridLaunch: false,
            dnsHttpsURL: "https://1.1.1.1/dns-query",
            httpsChunkSize: 1,
            httpsDisorder: true,
            appLaunchDelay: 0
        )
    }

    private static func displayPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func appendLog(_ message: String) {
        let stamped = "[\(timestampFormatter.string(from: Date()))] \(message)"
        logs.append(stamped)
    }

    nonisolated static func locateResourceBundle() -> Bundle? {
        let resourceBundleName = "SpoofTrap_SpoofTrap.bundle"
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let executableDirectory = executableURL.deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName),
            executableDirectory.appendingPathComponent(resourceBundleName),
            executableDirectory.deletingLastPathComponent().appendingPathComponent(resourceBundleName)
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return nil
    }
}
