import CoreText
import UIKit

/// The detail sentence's face: one of Apple's on-demand Chinese fonts
/// (Songti SC or Kaiti SC), fetched through Core Text. Until it has
/// downloaded -- or on a device that never will -- the system font is
/// used, and the next display after the download picks the real one.
enum DetailFont: String, CaseIterable, Sendable {
    case songti
    case kaiti

    /// The default face (handoff 6.11): a handwritten-leaning Kaiti suits a
    /// journal's detail line. `-TRIGGER-DETAIL-FONT songti|kaiti` overrides
    /// it in DEBUG builds, for screenshots.
    static let standard = DetailFont.kaiti

    /// The face in use: the DEBUG launch argument, else the default.
    nonisolated static var current: DetailFont {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-TRIGGER-DETAIL-FONT"), args.indices.contains(index + 1),
           let pick = DetailFont(rawValue: args[index + 1].lowercased()) {
            return pick
        }
        #endif
        return standard
    }

    /// What `TextBlock.fontName` stores and `TextFace.uiFont` resolves.
    var postScriptName: String {
        switch self {
        case .songti: "STSongti-SC-Regular"
        case .kaiti: "STKaitiSC-Regular"
        }
    }

    /// The `fontName` the ending and the canvas draft share.
    nonisolated static var currentName: String { current.postScriptName }

    /// `name` at `size` when this device has it, else the system font:
    /// never nil, never a missing-glyph face.
    nonisolated static func uiFont(named name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
    }

    /// The current face at `size` (system font until downloaded).
    nonisolated static func uiFont(size: CGFloat) -> UIFont {
        uiFont(named: currentName, size: size)
    }

    /// Starts the download if the font is not on the device yet. Safe to
    /// call any number of times; a failure just leaves the system font.
    nonisolated static func prefetch() {
        let name = currentName
        guard UIFont(name: name, size: 12) == nil else { return }
        let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 0)
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(
            [descriptor] as CFArray, nil
        ) { _, _ in true }
    }
}
