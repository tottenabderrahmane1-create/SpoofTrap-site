import Foundation

@MainActor
final class ProManager: ObservableObject {
    @Published var isPro: Bool = false
    
    let licenseManager = LicenseManager.shared
    
    init() {
        updateProStatus()
        
        Task {
            for await _ in licenseManager.$isValidated.values {
                updateProStatus()
            }
        }
    }
    
    var freePresets: [String] { ["stable", "balanced"] }
    var proPresets: [String] { ["fast", "custom"] }
    
    var canUsePreset: (String) -> Bool {
        { [weak self] preset in
            guard let self else { return false }
            return self.isPro || self.freePresets.contains(preset)
        }
    }
    
    var canEditFastFlags: Bool { isPro }
    var canUseAdvancedSettings: Bool { isPro }
    var canViewDetailedStats: Bool { isPro }
    var canImportCustomMods: Bool { isPro }
    var canUseMultiInstance: Bool { isPro }
    var canUseAutoRejoin: Bool { isPro }
    var canUseCustomThemes: Bool { isPro }
    var canUseUpdateChannel: Bool { isPro }
    var canUseDetailedPresence: Bool { isPro }
    var canViewFullHistory: Bool { isPro }
    var canUseCustomFPS: Bool { isPro }
    var canUseUnlimitedFavorites: Bool { isPro }
    var maxFreeHistory: Int { 5 }
    var maxFreeFavorites: Int { 3 }
    var freeFPSCap: Int { 120 }
    
    func canUseModCategory(_ categoryId: String) -> Bool {
        guard let cat = ModsManager.categories.first(where: { $0.id == categoryId }) else {
            return false
        }
        return !cat.requiresPro || isPro
    }
    
    var currentPlan: String {
        licenseManager.currentLicense?.plan ?? "free"
    }
    
    var licenseKey: String? {
        licenseManager.currentLicense?.licenseKey
    }
    
    func activate(key: String) async -> Bool {
        let success = await licenseManager.activate(licenseKey: key)
        updateProStatus()
        return success
    }
    
    func deactivate() async {
        _ = await licenseManager.deactivate()
        updateProStatus()
    }
    
    private func updateProStatus() {
        isPro = licenseManager.isValidated
        objectWillChange.send()
    }
}
