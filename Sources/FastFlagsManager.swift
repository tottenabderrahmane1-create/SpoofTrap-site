import Foundation

struct FastFlag: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: Category
    let valueType: ValueType
    var isEnabled: Bool
    var value: String
    let defaultValue: String
    
    enum Category: String, Codable, CaseIterable {
        case graphics = "Graphics"
        case network = "Network"
        case performance = "Performance"
        case debug = "Debug"
    }
    
    enum ValueType: String, Codable {
        case bool
        case int
        case string
    }
    
    var isModified: Bool {
        isEnabled && value != defaultValue
    }
}

enum FastFlagPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case performance = "Performance"
    case quality = "Quality"
    case network = "Network Fix"
    case debug = "Debug"
    
    var id: String { rawValue }
}

@MainActor
final class FastFlagsManager: ObservableObject {
    @Published var flags: [FastFlag] = []
    @Published var selectedPreset: FastFlagPreset = .none
    @Published var isEnabled: Bool = false {
        didSet {
            saveSettings()
        }
    }
    
    private let fileManager = FileManager.default
    
    static let allowedFlags: [FastFlag] = [
        // Graphics
        FastFlag(id: "DFIntTaskSchedulerTargetFps", name: "FPS Unlock", description: "Target frame rate (0 = unlimited)", category: .graphics, valueType: .int, isEnabled: false, value: "9999", defaultValue: "60"),
        FastFlag(id: "FFlagDebugGraphicsPreferVulkan", name: "Prefer Vulkan", description: "Use Vulkan renderer if available", category: .graphics, valueType: .bool, isEnabled: false, value: "true", defaultValue: "false"),
        FastFlag(id: "FFlagDebugGraphicsDisableMetal", name: "Disable Metal", description: "Disable Metal renderer", category: .graphics, valueType: .bool, isEnabled: false, value: "false", defaultValue: "false"),
        FastFlag(id: "DFIntDebugFRMQualityLevelOverride", name: "Quality Override", description: "Force graphics quality (1-10)", category: .graphics, valueType: .int, isEnabled: false, value: "10", defaultValue: "0"),
        FastFlag(id: "FFlagDisablePostFx", name: "Disable PostFX", description: "Disable post-processing effects", category: .graphics, valueType: .bool, isEnabled: false, value: "true", defaultValue: "false"),
        
        // Network
        FastFlag(id: "DFIntConnectionMTUSize", name: "MTU Size", description: "Network packet size", category: .network, valueType: .int, isEnabled: false, value: "1400", defaultValue: "1396"),
        FastFlag(id: "FFlagDebugDisableTimeoutDisconnect", name: "Disable Timeout", description: "Prevent timeout disconnects", category: .network, valueType: .bool, isEnabled: false, value: "true", defaultValue: "false"),
        FastFlag(id: "DFIntRakNetResendBufferArrayLength", name: "Resend Buffer", description: "Network resend buffer size", category: .network, valueType: .int, isEnabled: false, value: "256", defaultValue: "128"),
        
        // Performance
        FastFlag(id: "FFlagEnableInGameMenuChrome", name: "New Menu", description: "Enable new in-game menu", category: .performance, valueType: .bool, isEnabled: false, value: "true", defaultValue: "false"),
        FastFlag(id: "DFFlagTextureQualityOverrideEnabled", name: "Texture Override", description: "Allow texture quality override", category: .performance, valueType: .bool, isEnabled: false, value: "true", defaultValue: "false"),
        FastFlag(id: "DFIntTextureQualityOverride", name: "Texture Quality", description: "Texture quality level (0-3)", category: .performance, valueType: .int, isEnabled: false, value: "3", defaultValue: "0"),
        FastFlag(id: "FFlagFastGPULightCulling3", name: "Fast Light Culling", description: "Faster GPU light processing", category: .performance, valueType: .bool, isEnabled: false, value: "true", defaultValue: "false"),
        
        // Debug
        FastFlag(id: "FFlagDebugDisplayFPS", name: "Show FPS", description: "Display FPS counter", category: .debug, valueType: .bool, isEnabled: false, value: "true", defaultValue: "false"),
        FastFlag(id: "DFIntDebugPerfMode", name: "Perf Mode", description: "Performance debug mode", category: .debug, valueType: .int, isEnabled: false, value: "1", defaultValue: "0"),
        FastFlag(id: "FFlagDebugDisplayUnthemedInstances", name: "Debug Instances", description: "Show unthemed UI instances", category: .debug, valueType: .bool, isEnabled: false, value: "false", defaultValue: "false"),
    ]
    
    init() {
        flags = Self.allowedFlags
        loadSettings()
    }
    
    var enabledCount: Int {
        flags.filter { $0.isEnabled }.count
    }
    
    var modifiedCount: Int {
        flags.filter { $0.isModified }.count
    }
    
    func toggleFlag(_ flag: FastFlag) {
        guard let index = flags.firstIndex(where: { $0.id == flag.id }) else { return }
        flags[index].isEnabled.toggle()
        selectedPreset = .none
        saveSettings()
    }
    
    func setFlagValue(_ flag: FastFlag, value: String) {
        guard let index = flags.firstIndex(where: { $0.id == flag.id }) else { return }
        flags[index].value = value
        selectedPreset = .none
        saveSettings()
    }
    
    func addCustomFlag(id: String, name: String, valueType: FastFlag.ValueType, value: String) {
        guard !flags.contains(where: { $0.id == id }) else { return }
        let flag = FastFlag(
            id: id, name: name, description: "Custom flag",
            category: .debug, valueType: valueType,
            isEnabled: true, value: value, defaultValue: value
        )
        flags.append(flag)
        saveSettings()
    }

    func removeFlag(_ flag: FastFlag) {
        flags.removeAll { $0.id == flag.id }
        saveSettings()
    }

    var isCustomFlag: (FastFlag) -> Bool {
        { flag in !Self.allowedFlags.contains(where: { $0.id == flag.id }) }
    }

    func applyPreset(_ preset: FastFlagPreset) {
        selectedPreset = preset
        
        for i in flags.indices {
            flags[i].isEnabled = false
        }
        
        switch preset {
        case .none:
            break
            
        case .performance:
            enableFlag("DFIntTaskSchedulerTargetFps", value: "9999")
            enableFlag("FFlagDisablePostFx", value: "true")
            enableFlag("FFlagFastGPULightCulling3", value: "true")
            enableFlag("DFFlagTextureQualityOverrideEnabled", value: "true")
            enableFlag("DFIntTextureQualityOverride", value: "1")
            
        case .quality:
            enableFlag("DFIntDebugFRMQualityLevelOverride", value: "10")
            enableFlag("DFFlagTextureQualityOverrideEnabled", value: "true")
            enableFlag("DFIntTextureQualityOverride", value: "3")
            
        case .network:
            enableFlag("DFIntConnectionMTUSize", value: "1400")
            enableFlag("FFlagDebugDisableTimeoutDisconnect", value: "true")
            enableFlag("DFIntRakNetResendBufferArrayLength", value: "256")
            
        case .debug:
            enableFlag("FFlagDebugDisplayFPS", value: "true")
            enableFlag("DFIntDebugPerfMode", value: "1")
        }
        
        saveSettings()
    }
    
    private func enableFlag(_ id: String, value: String) {
        guard let index = flags.firstIndex(where: { $0.id == id }) else { return }
        flags[index].isEnabled = true
        flags[index].value = value
    }
    
    func resetAll() {
        flags = Self.allowedFlags
        selectedPreset = .none
        isEnabled = false
        saveSettings()
    }
    
    func applyToRoblox(appPath: String) -> Bool {
        guard isEnabled else { return true }
        
        let enabledFlags = flags.filter { $0.isEnabled }
        guard !enabledFlags.isEmpty else { return true }
        
        let clientSettingsPath = (appPath as NSString)
            .appendingPathComponent("Contents/MacOS/ClientSettings")
        let jsonPath = (clientSettingsPath as NSString)
            .appendingPathComponent("ClientAppSettings.json")
        
        do {
            try fileManager.createDirectory(atPath: clientSettingsPath, withIntermediateDirectories: true)
            
            var flagDict: [String: Any] = [:]
            for flag in enabledFlags {
                switch flag.valueType {
                case .bool:
                    flagDict[flag.id] = flag.value.lowercased() == "true"
                case .int:
                    flagDict[flag.id] = Int(flag.value) ?? 0
                case .string:
                    flagDict[flag.id] = flag.value
                }
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: flagDict, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: jsonPath))
            
            return true
        } catch {
            return false
        }
    }
    
    func removeFromRoblox(appPath: String) {
        let clientSettingsPath = (appPath as NSString)
            .appendingPathComponent("Contents/MacOS/ClientSettings")
        let jsonPath = (clientSettingsPath as NSString)
            .appendingPathComponent("ClientAppSettings.json")
        
        try? fileManager.removeItem(atPath: jsonPath)
    }
    
    private var settingsURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseDirectory = appSupport ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        
        return baseDirectory
            .appendingPathComponent("SpoofTrap/fastflags.json")
    }
    
    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
              let saved = try? JSONDecoder().decode(SavedFastFlags.self, from: data) else {
            return
        }
        
        isEnabled = saved.isEnabled
        
        for savedFlag in saved.flags {
            if let index = flags.firstIndex(where: { $0.id == savedFlag.id }) {
                flags[index].isEnabled = savedFlag.isEnabled
                flags[index].value = savedFlag.value
            }
        }
    }
    
    private func saveSettings() {
        let saved = SavedFastFlags(
            isEnabled: isEnabled,
            flags: flags.map { SavedFlag(id: $0.id, isEnabled: $0.isEnabled, value: $0.value) }
        )
        
        do {
            try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(saved)
            try data.write(to: settingsURL)
        } catch {
            print("Failed to save FastFlags: \(error)")
        }
    }
}

private struct SavedFastFlags: Codable {
    let isEnabled: Bool
    let flags: [SavedFlag]
}

private struct SavedFlag: Codable {
    let id: String
    let isEnabled: Bool
    let value: String
}
