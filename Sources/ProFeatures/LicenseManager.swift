import Foundation
import IOKit
import CryptoKit

struct LicenseValidationResponse: Codable {
    let valid: Bool
    let plan: String?
    let expiresAt: String?
    let activationId: String?
    let newlyActivated: Bool?
    let error: String?
    let message: String?
    let max: Int?
    let current: Int?
    
    enum CodingKeys: String, CodingKey {
        case valid, plan, error, message, max, current
        case expiresAt = "expires_at"
        case activationId = "activation_id"
        case newlyActivated = "newly_activated"
    }
}

struct LicenseInfo: Codable {
    var licenseKey: String
    var plan: String
    var expiresAt: Date?
    var activatedAt: Date
    var deviceId: String
    
    var isLifetime: Bool { plan == "lifetime" }
    var isExpired: Bool {
        guard let expires = expiresAt else { return false }
        return expires < Date()
    }
}

@MainActor
class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published private(set) var isValidated: Bool = false
    @Published private(set) var currentLicense: LicenseInfo?
    @Published private(set) var validationError: String?
    @Published private(set) var isValidating: Bool = false
    
    private let supabaseURL = "https://xucsfvyijnjkwdiiquwy.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh1Y3Nmdnlpam5qa3dkaWlxdXd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NzY0NDksImV4cCI6MjA5MDU1MjQ0OX0.hfeGgWqqWdIym6Y4BqlW8nlIZ8y7MDmtWynS3bWQ0BM"
    
    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("SpoofTrap")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("license.json")
    }()
    
    private var heartbeatTimer: Timer?
    
    init() {
        loadStoredLicense()
    }
    
    var deviceId: String {
        getHardwareUUID() ?? "unknown-device"
    }
    
    var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private func getHardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        
        guard service != 0,
              let uuidData = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return nil
        }
        
        let hash = SHA256.hash(data: Data(uuidData.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func activate(licenseKey: String) async -> Bool {
        let normalizedKey = licenseKey.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard isValidKeyFormat(normalizedKey) else {
            validationError = "Invalid license key format"
            return false
        }
        
        isValidating = true
        validationError = nil
        
        defer { isValidating = false }
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/validate_license") else {
            validationError = "Configuration error"
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "p_license_key": normalizedKey,
            "p_device_id": deviceId,
            "p_device_name": deviceName,
            "p_platform": "macos",
            "p_app_version": appVersion,
            "p_os_version": osVersion
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                validationError = "Invalid server response"
                return false
            }
            
            guard httpResponse.statusCode == 200 else {
                validationError = "Server error (\(httpResponse.statusCode))"
                return false
            }
            
            let result = try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
            
            if result.valid {
                let license = LicenseInfo(
                    licenseKey: normalizedKey,
                    plan: result.plan ?? "pro",
                    expiresAt: parseDate(result.expiresAt),
                    activatedAt: Date(),
                    deviceId: deviceId
                )
                
                currentLicense = license
                isValidated = true
                saveLicense(license)
                startHeartbeat()
                
                return true
            } else {
                validationError = mapError(result.error, message: result.message)
                return false
            }
        } catch {
            validationError = "Network error: \(error.localizedDescription)"
            return false
        }
    }
    
    func deactivate() async -> Bool {
        guard let license = currentLicense else { return true }
        
        stopHeartbeat()
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/deactivate_device") else {
            clearLicense()
            return true
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "p_license_key": license.licenseKey,
            "p_device_id": deviceId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // Deactivate locally even if server fails
        }
        
        clearLicense()
        return true
    }
    
    func validateStoredLicense() async {
        guard let license = currentLicense else { return }
        
        if license.isExpired {
            clearLicense()
            validationError = "License has expired"
            return
        }
        
        _ = await activate(licenseKey: license.licenseKey)
    }
    
    private func startHeartbeat() {
        stopHeartbeat()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.sendHeartbeat()
            }
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() async {
        guard let license = currentLicense,
              let url = URL(string: "\(supabaseURL)/rest/v1/rpc/license_heartbeat") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "p_license_key": license.licenseKey,
            "p_device_id": deviceId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let valid = json["valid"] as? Bool, !valid {
                clearLicense()
                validationError = "License no longer valid"
            }
        } catch {
            // Heartbeat failures are silent
        }
    }
    
    private func loadStoredLicense() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let license = try JSONDecoder().decode(LicenseInfo.self, from: data)
            
            if license.deviceId == deviceId && !license.isExpired {
                currentLicense = license
                isValidated = true
                startHeartbeat()
                
                Task {
                    await validateStoredLicense()
                }
            } else {
                try? FileManager.default.removeItem(at: storageURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: storageURL)
        }
    }
    
    private func saveLicense(_ license: LicenseInfo) {
        do {
            let data = try JSONEncoder().encode(license)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Storage failure is non-fatal
        }
    }
    
    private func clearLicense() {
        currentLicense = nil
        isValidated = false
        try? FileManager.default.removeItem(at: storageURL)
    }
    
    private func isValidKeyFormat(_ key: String) -> Bool {
        let pattern = "^ST[A-Z0-9]{3}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$"
        return key.range(of: pattern, options: .regularExpression) != nil
    }
    
    private func parseDate(_ dateString: String?) -> Date? {
        guard let str = dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
    
    private func mapError(_ error: String?, message: String?) -> String {
        switch error {
        case "invalid_key": return "Invalid license key"
        case "revoked": return "License has been revoked"
        case "inactive": return "License is not active"
        case "expired": return "License has expired"
        case "max_activations": return "Maximum devices reached. Deactivate another device first."
        default: return message ?? "Validation failed"
        }
    }
}
