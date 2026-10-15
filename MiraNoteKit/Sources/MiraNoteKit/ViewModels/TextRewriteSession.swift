import Foundation

/// The text accessory's AI row (handoff screen 15): Original / Clean up /
/// Expand preview a rewrite of the block in place. Each rewrite is asked for
/// once and cached, so toggling back and forth is instant; Original is the
/// text as it was when the row opened (or as the user last typed it).
public struct TextRewriteSession: Equatable, Sendable {
    public enum Choice: String, CaseIterable, Sendable {
        case original, clean, expand

        /// The backend transform behind a rewrite; nil for Original.
        public var mode: TextTransformMode? {
            switch self {
            case .original: return nil
            case .clean: return .clean
            case .expand: return .expand
            }
        }
    }

    public private(set) var original: String
    /// The version on the canvas.
    public private(set) var selected: Choice = .original
    /// A rewrite asked for and not back yet.
    public private(set) var pending: Choice?
    private var results: [Choice: String] = [:]

    public init(original: String) {
        self.original = original
    }

    /// The words the canvas shows for the selected choice.
    public var shownText: String {
        text(for: selected) ?? original
    }

    public func text(for choice: Choice) -> String? {
        choice == .original ? original : results[choice]
    }

    /// Picks a version. Returns the words to show now, or nil when the
    /// rewrite has to be fetched first (the choice is then `pending`).
    public mutating func select(_ choice: Choice) -> String? {
        if let text = text(for: choice) {
            selected = choice
            pending = nil
            return text
        }
        pending = choice
        return nil
    }

    /// A rewrite of `source` came back: cached when `source` is still the
    /// Original, and shown (returned) only if it is the one the user is
    /// waiting for. A rewrite of words the user has since retyped is dropped.
    public mutating func resolve(_ choice: Choice, of source: String, with text: String) -> String? {
        guard source == original else { return nil }
        results[choice] = text
        guard pending == choice else { return nil }
        pending = nil
        selected = choice
        return text
    }

    /// A rewrite of `source` failed: the selection stays where it was.
    public mutating func fail(_ choice: Choice, of source: String) {
        if source == original, pending == choice { pending = nil }
    }

    /// The user typed. Words that differ from the shown version become the
    /// new Original, and the cached rewrites of the old words are dropped.
    public mutating func adopt(typed text: String) {
        guard text != shownText else { return }
        original = text
        results = [:]
        selected = .original
        pending = nil
    }
}
