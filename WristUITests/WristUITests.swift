import XCTest

final class WristUITests: XCTestCase {
    @MainActor
    func testCreatePersistSearchAndDeleteCapture() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let unique = "Orchid " + UUID().uuidString.prefix(6)
        let transcript = "Remember to buy \(unique) seeds tomorrow."
        XCTAssertTrue(app.buttons["new-note"].waitForExistence(timeout: 10))
        app.buttons["new-note"].tap()
        let editor = app.textViews["note-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-note"].isEnabled)
        editor.tap()
        editor.typeText(transcript)
        app.buttons["save-note"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memo-' AND label CONTAINS %@", unique)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Capture survives a cold launch")
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(String(unique))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["memo-menu"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Wrist capture detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["memo-menu"].tap()
        app.buttons["delete-memo"].tap()
        XCTAssertTrue(app.buttons["new-note"].waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
        app.terminate()
        app.launch()
        XCTAssertFalse(row.exists, "Deleted capture stays deleted after restart")
    }
}
