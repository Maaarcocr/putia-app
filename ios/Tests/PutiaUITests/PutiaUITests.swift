import XCTest

/// The main flows, against an in-memory server with a sample wardrobe (-ui-testing). Elements are
/// found by accessibility identifier, never by text, so the same test runs in English and Italian.
/// Screenshots are kept in the result bundle and exported by CI, which is how the app is reviewed
/// without a Mac.
final class PutiaUITests: XCTestCase {
    @MainActor
    func testTheBench() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // The closet, and a piece with a tag an AI suggested.
        let piece = element(app, "closet.piece")
        XCTAssertTrue(piece.waitForExistence(timeout: 30))
        capture("01-closet")
        piece.tap()
        let confirm = element(app, "piece.confirm.material")
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        capture("02-piece")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 30), "the person confirms the suggestion")

        // The piece's photos: the person makes the one an AI found online the main photo.
        let useAsMain = element(app, "photo.useAsMain.00000000-0000-4000-8000-000000000051")
        app.swipeUp()
        XCTAssertTrue(useAsMain.waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, "photos.add.piece").exists)
        capture("02b-photos")
        useAsMain.tap()
        XCTAssertTrue(useAsMain.waitForNonExistence(timeout: 30), "the AI's photo is now the main one")

        // The workbench: an AI's proposal, which the person marks a favourite and edits.
        app.tabBars.buttons.element(boundBy: 1).tap()
        let card = element(app, "outfits.card")
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        capture("03-outfits")
        card.tap()
        let favourite = element(app, "outfit.favourite")
        XCTAssertTrue(favourite.waitForExistence(timeout: 30))
        capture("04-outfit")
        favourite.tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: favourite)
        waitForExpectations(timeout: 30)
        let edit = element(app, "outfit.edit")
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        let save = element(app, "editor.save")
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        capture("04b-edit-outfit")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 30))

        // What's missing: the AI's conclusion and shortlist.
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(element(app, "missing.wish").waitForExistence(timeout: 30))
        capture("05-missing")

        // The bench: photos of the person for try-ons, every change, and connecting an AI.
        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(element(app, "photos.add.person").waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, "history.undo").waitForExistence(timeout: 30))
        capture("06-bench")
        element(app, "bench.connect").tap()
        XCTAssertTrue(element(app, "connect.code").waitForExistence(timeout: 30))
        capture("07-connect")
        XCTAssertTrue(element(app, "connect.connected").waitForExistence(timeout: 30))
        capture("08-connected")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
