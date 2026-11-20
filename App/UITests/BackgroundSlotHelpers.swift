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

    /// The rows in the Background slot now: one, except mid level change.
    var backgroundSlotRows: XCUIElementQuery {
        descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'background.row.' AND identifier != 'background.row.back'"
        ))
    }
}

extension XCUIElement {
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
        // Typed step by step: one expression of it does not type-check in
        // time on Xcode 26.6.
        let lightness: [Int] = stride(from: 0, to: pixels.count, by: 4).map { index in
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            return red + green + blue
        }
        return (lightness.max() ?? 0) - (lightness.min() ?? 0) > 150
    }
}
