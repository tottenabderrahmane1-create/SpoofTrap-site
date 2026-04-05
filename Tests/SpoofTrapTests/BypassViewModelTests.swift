import XCTest
@testable import SpoofTrap

@MainActor
final class BypassViewModelTests: XCTestCase {

    func testLaunchMultiInstanceRequiresPro() {
        let viewModel = BypassViewModel()

        // Mock proManager not having pro status
        viewModel.proManager.isPro = false

        let initialLogsCount = viewModel.logs.count

        viewModel.launchMultiInstance()

        XCTAssertEqual(viewModel.logs.count, initialLogsCount + 1, "Should append exactly one log.")
        XCTAssertTrue(viewModel.logs.last?.contains("Multi-instance requires Pro.") ?? false, "Log should indicate that Pro is required.")
    }

    func testLaunchMultiInstanceRobloxNotFound() {
        let viewModel = BypassViewModel()

        // Mock proManager having pro status
        viewModel.proManager.isPro = true

        // Ensure robloxInstalled is false by providing a non-existent path
        let nonExistentPath = "/tmp/nonexistent_roblox_\(UUID().uuidString).app"
        viewModel.setRobloxAppPath(nonExistentPath)

        let initialLogsCount = viewModel.logs.count

        viewModel.launchMultiInstance()

        XCTAssertEqual(viewModel.logs.count, initialLogsCount + 1, "Should append exactly one log.")
        XCTAssertTrue(viewModel.logs.last?.contains("Roblox not found for multi-instance.") ?? false, "Log should indicate that Roblox was not found.")
    }
}
