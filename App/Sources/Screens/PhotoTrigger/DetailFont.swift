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

    /// PingFang SC ships with iOS and has these faces' line metrics (ascent
    /// 1.06 em, descent 0.34 em; the system font's are lower).
    static let metricsStandIn = "PingFangSC-Regular"

    /// What a text block in `name` is measured with, when `name` is one of
    /// these faces and it has not downloaded yet: the system font it shows
    /// now and PingFang SC, so the box measured now (the taller of the two)
    /// still holds the lines once the face lands -- the canvas grows a box
    /// on open but never shrinks it, and a box shorter than its text cuts
    /// the last line. nil otherwise: measure with the face itself.
    nonisolated static func pendingMeasureFonts(
        named name: String, size: CGFloat, available: (String) -> Bool = { UIFont(name: $0, size: 12) != nil }
    ) -> [UIFont]? {
        guard allCases.contains(where: { $0.postScriptName == name }), !available(name) else { return nil }
        return [UIFont.systemFont(ofSize: size)] + [UIFont(name: metricsStandIn, size: size)].compactMap { $0 }
    }

    /// Starts the downloads of the ending's two faces (this one and the
    /// question's) if they are not on the device yet. Safe to call any
    /// number of times; a failure just leaves the system font.
    nonisolated static func prefetch() {
        for name in [currentName, QuestionFont.postScriptName] where UIFont(name: name, size: 12) == nil {
            let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 0)
            CTFontDescriptorMatchFontDescriptorsWithProgressHandler(
                [descriptor] as CFArray, nil
            ) { _, _ in true }
        }
    }
}

/// The ending question's face (decision 11-05): Weibei SC, an on-demand
/// Apple font like the detail line's, its square brush strokes set apart
/// from the Kaiti detail above it. The system font until it has downloaded.
enum QuestionFont {
    static let postScriptName = "WeibeiSC-Bold"

    nonisolated static func uiFont(size: CGFloat) -> UIFont {
        DetailFont.uiFont(named: postScriptName, size: size)
    }
}
