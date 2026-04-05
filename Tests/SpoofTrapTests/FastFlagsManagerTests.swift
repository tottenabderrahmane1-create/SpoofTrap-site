import XCTest
@testable import SpoofTrap

@MainActor
final class FastFlagsManagerTests: XCTestCase {
    var sut: FastFlagsManager!
    var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = FastFlagsManager()

        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory
        tempDirectoryURL = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        sut = nil
        try super.tearDownWithError()
    }

    func testApplyToRoblox_WhenDisabled_ReturnsTrueAndDoesNotCreateDirectory() {
        // Arrange
        sut.isEnabled = false

        let clientSettingsPath = (tempDirectoryURL.path as NSString).appendingPathComponent("Contents/MacOS/ClientSettings")

        // Act
        let result = sut.applyToRoblox(appPath: tempDirectoryURL.path)

        // Assert
        XCTAssertTrue(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clientSettingsPath))
    }

    func testApplyToRoblox_WhenNoFlagsEnabled_ReturnsTrueAndDoesNotCreateDirectory() {
        // Arrange
        sut.isEnabled = true
        // Disable all flags
        for i in sut.flags.indices {
            sut.flags[i].isEnabled = false
        }

        let clientSettingsPath = (tempDirectoryURL.path as NSString).appendingPathComponent("Contents/MacOS/ClientSettings")

        // Act
        let result = sut.applyToRoblox(appPath: tempDirectoryURL.path)

        // Assert
        XCTAssertTrue(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clientSettingsPath))
    }

    func testApplyToRoblox_WhenEnabledWithFlags_CreatesJSONFileWithCorrectContent() throws {
        // Arrange
        sut.isEnabled = true
        // Disable all flags first
        for i in sut.flags.indices {
            sut.flags[i].isEnabled = false
        }

        // Add specific flags to test different value types
        sut.addCustomFlag(id: "TestBoolFlag", name: "Test Bool", valueType: .bool, value: "true")
        sut.addCustomFlag(id: "TestIntFlag", name: "Test Int", valueType: .int, value: "42")
        sut.addCustomFlag(id: "TestStringFlag", name: "Test String", valueType: .string, value: "Hello")

        let clientSettingsPath = (tempDirectoryURL.path as NSString).appendingPathComponent("Contents/MacOS/ClientSettings")
        let jsonPath = (clientSettingsPath as NSString).appendingPathComponent("ClientAppSettings.json")

        // Act
        let result = sut.applyToRoblox(appPath: tempDirectoryURL.path)

        // Assert
        XCTAssertTrue(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonPath))

        // Verify JSON Content
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        XCTAssertEqual(jsonObject?["TestBoolFlag"] as? Bool, true)
        XCTAssertEqual(jsonObject?["TestIntFlag"] as? Int, 42)
        XCTAssertEqual(jsonObject?["TestStringFlag"] as? String, "Hello")
    }
}
