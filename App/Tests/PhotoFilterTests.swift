import CoreImage
import XCTest
@testable import MiraNote

/// The temperature direction is easy to invert (CITemperatureAndTint
/// warms toward LOWER Kelvin targets): render a grey pixel and check
/// which way the tint actually went.
final class PhotoFilterTests: XCTestCase {
    private func renderedRGB(after filter: PhotoFilter) -> (red: CGFloat, blue: CGFloat) {
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let output = filter.apply(to: grey)
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return (CGFloat(pixel[0]), CGFloat(pixel[2]))
    }

    func testWarmFilterTintsWarmNotCool() {
        let rgb = renderedRGB(after: .warm)
        XCTAssertGreaterThan(rgb.red, rgb.blue, "Warm must tint toward amber, not blue")
    }

    func testMatchPageTintsGentlyWarm() {
        let rgb = renderedRGB(after: .match)
        XCTAssertGreaterThan(rgb.red, rgb.blue, "Match page leans into the warm paper")
    }

    func testOriginalLeavesGreyAlone() {
        let rgb = renderedRGB(after: .none)
        XCTAssertEqual(rgb.red, rgb.blue, accuracy: 1, "Original never tints")
    }
}
