import XCTest

final class PTOHubUITests: XCTestCase {
    @MainActor
    func testLaunchesIntoConfiguredOrConfigurationState() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        app.launch()
        let welcome = app.staticTexts["Welcome back"].waitForExistence(timeout: 5)
        let configuration = app.staticTexts["Configuration Required"].waitForExistence(timeout: 2)
        let loading = app.staticTexts["Loading Staff Hub…"].exists
        XCTAssertTrue(welcome || configuration || loading)
    }

    @MainActor
    func testEmployeeDemoOpensLocalDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        app.launch()
        let demo = app.buttons["Demo Employee"]
        XCTAssertTrue(demo.waitForExistence(timeout: 8))
        demo.tap()
        XCTAssertTrue(app.staticTexts["Available PTO"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Welcome back, Maya'")).firstMatch.exists)
    }

    @MainActor
    func testManagerRejectionExplainsRequiredReasonAndCompletes() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-demo"]
        app.launch()

        let demo = app.buttons["Demo Manager"]
        XCTAssertTrue(demo.waitForExistence(timeout: 8))
        demo.tap()

        let requestsTab = app.tabBars.buttons["Requests"]
        XCTAssertTrue(requestsTab.waitForExistence(timeout: 8))
        requestsTab.tap()

        let pendingEmployee = app.staticTexts["Jordan Lee"].firstMatch
        XCTAssertTrue(pendingEmployee.waitForExistence(timeout: 8))
        pendingEmployee.tap()

        let reject = app.buttons["Reject Request"]
        XCTAssertTrue(reject.waitForExistence(timeout: 5))
        reject.tap()
        XCTAssertTrue(
            app.staticTexts["Enter a reason before rejecting this request."].waitForExistence(timeout: 3)
        )

        let reason = app.textFields["Required rejection reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 3))
        reason.typeText("Coverage is unavailable")
        reject.tap()

        XCTAssertTrue(app.staticTexts["Rejected"].waitForExistence(timeout: 8))
    }
}
