import AppKit
import Foundation

struct ModCategory: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let relativePaths: [String]
    let allowedExtensions: [String]
    let requiresPro: Bool
}

struct InstalledMod: Identifiable, Codable, Equatable {
    let id: String
    var categoryId: String
    var name: String
    var isEnabled: Bool
    var isBuiltIn: Bool
    var customFilePath: String?
    var originalBackedUp: Bool
}

@MainActor
final class ModsManager: ObservableObject {
    @Published var installedMods: [InstalledMod] = []
    @Published var isEnabled: Bool = false {
        didSet { saveSettings() }
    }

    private let fileManager = FileManager.default

    static let categories: [ModCategory] = [
        ModCategory(
            id: "death_sound",
            name: "Death Sound",
            description: "Replace the classic 'oof' sound",
            icon: "speaker.wave.2.fill",
            relativePaths: ["content/sounds/ouch.ogg"],
            allowedExtensions: ["ogg"],
            requiresPro: false
        ),
        ModCategory(
            id: "cursor",
            name: "Custom Cursor",
            description: "Replace in-game cursor textures",
            icon: "cursorarrow",
            relativePaths: [
                "content/textures/Cursors/KeyboardMouse/ArrowCursor.png",
                "content/textures/Cursors/KeyboardMouse/ArrowFarCursor.png"
            ],
            allowedExtensions: ["png"],
            requiresPro: false
        ),
        ModCategory(
            id: "app_icon",
            name: "App Icon",
            description: "Swap the Roblox in-game icon",
            icon: "app.badge.fill",
            relativePaths: [
                "content/textures/ui/icon_app-512.png"
            ],
            allowedExtensions: ["png"],
            requiresPro: true
        ),
        ModCategory(
            id: "fonts",
            name: "Custom Fonts",
            description: "Replace default Roblox UI fonts",
            icon: "textformat",
            relativePaths: [
                "content/fonts/BuilderSans-Regular.otf",
                "content/fonts/BuilderSans-Medium.otf",
                "content/fonts/BuilderSans-Bold.otf",
                "content/fonts/BuilderSans-ExtraBold.otf"
            ],
            allowedExtensions: ["otf", "ttf"],
            requiresPro: true
        ),
        ModCategory(
            id: "avatar_bg",
            name: "Avatar Background",
            description: "Change the avatar editor background",
            icon: "person.crop.rectangle.fill",
            relativePaths: [
                "ExtraContent/places/Mobile.rbxl"
            ],
            allowedExtensions: ["rbxl"],
            requiresPro: true
        )
    ]

    init() {
        loadSettings()
    }

    var enabledCount: Int {
        installedMods.filter { $0.isEnabled }.count
    }

    func category(for id: String) -> ModCategory? {
        Self.categories.first { $0.id == id }
    }

    func mods(for categoryId: String) -> [InstalledMod] {
        installedMods.filter { $0.categoryId == categoryId }
    }

    func activeMod(for categoryId: String) -> InstalledMod? {
        installedMods.first { $0.categoryId == categoryId && $0.isEnabled }
    }

    // MARK: - Import custom mod file (PRO)

    func importCustomMod(for categoryId: String) {
        guard let cat = category(for: categoryId) else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose \(cat.name) file"
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        panel.allowedFileTypes = cat.allowedExtensions

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let destDir = modsStorageDir.appendingPathComponent(categoryId)
        try? fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent(url.lastPathComponent)
        try? fileManager.removeItem(at: destURL)

        do {
            try fileManager.copyItem(at: url, to: destURL)
        } catch {
            return
        }

        let newMod = InstalledMod(
            id: UUID().uuidString,
            categoryId: categoryId,
            name: url.deletingPathExtension().lastPathComponent,
            isEnabled: false,
            isBuiltIn: false,
            customFilePath: destURL.path,
            originalBackedUp: false
        )

        installedMods.append(newMod)
        saveSettings()
    }

    func toggleMod(_ mod: InstalledMod) {
        guard let index = installedMods.firstIndex(where: { $0.id == mod.id }) else { return }

        if !mod.isEnabled {
            for i in installedMods.indices where installedMods[i].categoryId == mod.categoryId {
                installedMods[i].isEnabled = false
            }
        }

        installedMods[index].isEnabled.toggle()
        saveSettings()
    }

    func removeMod(_ mod: InstalledMod) {
        guard !mod.isBuiltIn else { return }

        if let path = mod.customFilePath {
            try? fileManager.removeItem(atPath: path)
        }

        installedMods.removeAll { $0.id == mod.id }
        saveSettings()
    }

    // MARK: - Apply mods before Roblox launch

    func applyMods(robloxAppPath: String) -> (applied: Int, failed: Int) {
        guard isEnabled else { return (0, 0) }

        let resourcesBase = (robloxAppPath as NSString).appendingPathComponent("Contents/Resources")
        let macosBase = (robloxAppPath as NSString).appendingPathComponent("Contents/MacOS")
        var applied = 0
        var failed = 0

        for mod in installedMods where mod.isEnabled {
            guard let cat = category(for: mod.categoryId) else { continue }

            let sourceFile: String
            if let custom = mod.customFilePath {
                sourceFile = custom
            } else if mod.isBuiltIn {
                guard let bundled = bundledModPath(for: mod) else {
                    failed += 1
                    continue
                }
                sourceFile = bundled
            } else {
                continue
            }

            guard fileManager.fileExists(atPath: sourceFile) else {
                failed += 1
                continue
            }

            for relPath in cat.relativePaths {
                // app_icon textures live in Contents/MacOS, everything else in Contents/Resources
                let base = cat.id == "app_icon" ? macosBase : resourcesBase
                let targetPath = (base as NSString).appendingPathComponent(relPath)
                let backupPath = backupPathFor(target: targetPath)

                if !fileManager.fileExists(atPath: backupPath) && fileManager.fileExists(atPath: targetPath) {
                    let backupDir = (backupPath as NSString).deletingLastPathComponent
                    try? fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
                    try? fileManager.copyItem(atPath: targetPath, toPath: backupPath)

                    if let idx = installedMods.firstIndex(where: { $0.id == mod.id }) {
                        installedMods[idx].originalBackedUp = true
                    }
                }

                let targetDir = (targetPath as NSString).deletingLastPathComponent
                try? fileManager.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

                do {
                    if fileManager.fileExists(atPath: targetPath) {
                        try fileManager.removeItem(atPath: targetPath)
                    }
                    try fileManager.copyItem(atPath: sourceFile, toPath: targetPath)
                    applied += 1
                } catch {
                    failed += 1
                }
            }
        }

        saveSettings()
        return (applied, failed)
    }

    func restoreOriginals(robloxAppPath: String) {
        let resourcesBase = (robloxAppPath as NSString).appendingPathComponent("Contents/Resources")
        let macosBase = (robloxAppPath as NSString).appendingPathComponent("Contents/MacOS")

        for cat in Self.categories {
            for relPath in cat.relativePaths {
                let base = cat.id == "app_icon" ? macosBase : resourcesBase
                let targetPath = (base as NSString).appendingPathComponent(relPath)
                let backupPath = backupPathFor(target: targetPath)

                if fileManager.fileExists(atPath: backupPath) {
                    try? fileManager.removeItem(atPath: targetPath)
                    try? fileManager.copyItem(atPath: backupPath, toPath: targetPath)
                    try? fileManager.removeItem(atPath: backupPath)
                }
            }
        }

        for i in installedMods.indices {
            installedMods[i].originalBackedUp = false
        }
        saveSettings()
    }

    // MARK: - Storage

    private var modsStorageDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SpoofTrap/Mods")
    }

    private var backupsDir: URL {
        modsStorageDir.appendingPathComponent("Backups")
    }

    private var settingsURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SpoofTrap/mods_settings.json")
    }

    private func backupPathFor(target: String) -> String {
        let hash = target.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(40)
        let ext = (target as NSString).pathExtension
        return backupsDir.appendingPathComponent("\(hash).\(ext)").path
    }

    private func bundledModPath(for mod: InstalledMod) -> String? {
        guard mod.isBuiltIn else { return nil }
        let path = modsStorageDir
            .appendingPathComponent("defaults")
            .appendingPathComponent(mod.categoryId)
            .appendingPathComponent(mod.name)
        return fileManager.fileExists(atPath: path.path) ? path.path : nil
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
              let saved = try? JSONDecoder().decode(SavedModsSettings.self, from: data) else {
            return
        }

        isEnabled = saved.isEnabled
        installedMods = saved.mods
    }

    private func saveSettings() {
        let saved = SavedModsSettings(
            isEnabled: isEnabled,
            mods: installedMods
        )

        do {
            try fileManager.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(saved)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            print("Failed to save mods settings: \(error)")
        }
    }
}

private struct SavedModsSettings: Codable {
    let isEnabled: Bool
    let mods: [InstalledMod]
}
