import XCTest

/// The Background tool in the tool slot (#205): one row at a time. The tool
/// opens on Back and the Sets / Color / Paper / Tidy capsules in the tool
/// bar's place; an item's row replaces them with its own Back
/// (`background.row.back`), and the four items' Back (`background.back`)
/// closes the tool.
extension XCUIApplication {
    /// Opens the Background tool on its four items.
    func openBackground(file: StaticString = #filePath, line: UInt = #line) {
        buttons["mode.background"].tap()
        XCTAssertTrue(descendants(matching: .any)["background.row.tools"].waitForExistence(timeout: 5),
                      "the tool's items replaced the tool bar", file: file, line: line)
    }

    /// Opens an item's row (`sets`, `color`, `paper`), opening the tool
    /// first when it is closed.
    func openBackgroundRow(_ row: String, file: StaticString = #filePath, line: UInt = #line) {
        if !buttons["background.back"].exists, !buttons["background.row.back"].exists {
            openBackground(file: file, line: line)
        }
        backToBackgroundItems(file: file, line: line)
        buttons["background.tool.\(row)"].tap()
        XCTAssertTrue(descendants(matching: .any)["background.row.\(row)"].waitForExistence(timeout: 5),
                      "\(row) opened its row", file: file, line: line)
    }

    /// Up to the four items if an item's row is showing.
    func backToBackgroundItems(file: StaticString = #filePath, line: UInt = #line) {
        let back = buttons["background.row.back"]
        guard back.exists else { return }
        back.tap()
        XCTAssertTrue(descendants(matching: .any)["background.row.tools"].waitForExistence(timeout: 5),
                      "back on the four items", file: file, line: line)
    }

    /// Back up every level to the tool bar.
    func closeBackground(file: StaticString = #filePath, line: UInt = #line) {
        backToBackgroundItems(file: file, line: line)
        buttons["background.back"].tap()
        XCTAssertTrue(buttons["mode.background"].waitForExistence(timeout: 5), "the tool bar is back",
                      file: file, line: line)
    }

    /// Types words into the Background tool's Apply and sends them.
    func paintBackground(_ words: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = textFields["background.apply.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        field.tap()
        field.typeText(words)
        buttons["background.apply"].tap()
    }

    /// The canvas's debug probe.
    var canvasProbe: XCUIElement {
        descendants(matching: .any).matching(identifier: "debug.state")
            .matching(NSPredicate(format: "label CONTAINS '\"scene\":\"canvas\"'")).firstMatch
    }

    /// The undo steps the page has, from the probe.
    var undoDepth: Int {
        let label = canvasProbe.label
        guard let range = label.range(of: #""undoDepth":(\d+)"#, options: .regularExpression),
              let depth = Int(label[range].drop { !$0.isNumber }) else { return -1 }
        return depth
    }

    /// The painting's file name the page wears ("" for none), from the probe.
    var backdrop: String {
        let label = canvasProbe.label
        guard let range = label.range(of: #""backdrop":"[^"]*""#, options: .regularExpression) else { return "" }
        return String(label[range].dropFirst(12).dropLast())
    }

    /// The rows in the Background slot now: one, except mid level change.
    var backgroundSlotRows: XCUIElementQuery {
        descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'background.row.' AND identifier != 'background.row.back'"
        ))
    }
}

extension XCUIElement {
    /// Waits for the element to read as chosen.
    func waitForSelection(timeout: TimeInterval = 5) -> Bool {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter().wait(for: [selected], timeout: timeout) == .completed
    }

    /// Something is drawn in the element's frame: its darkest and lightest
    /// pixels differ, as a tool's icon on its capsule does. An element
    /// faded to nothing shows only the plain screen behind it.
    var showsInk: Bool {
        guard let image = screenshot().image.cgImage else { return false }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let lightness = stride(from: 0, to: pixels.count, by: 4).map {
            Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])
        }
        return (lightness.max() ?? 0) - (lightness.min() ?? 0) > 150
    }
}
