import Foundation

/// A multi-line field takes Return as a new line; the Mira fields treat it
/// as Send instead. Only a trailing new line counts: lines pasted in (or a
/// transcript with a line break) stay in the field and are never sent.
enum ReturnKey {
    /// The words without the Return just typed after them; nil when the
    /// text does not end in a new line.
    static func pressed(in words: String) -> String? {
        guard words.hasSuffix("\n") else { return nil }
        return String(words.dropLast())
    }
}
