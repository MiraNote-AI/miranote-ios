import Foundation

/// A multi-line field takes Return as a new line; the Mira fields treat it
/// as Send instead. Only a Return typed at the end counts: lines pasted in
/// (even ones ending in a new line) or a transcript with a line break stay
/// in the field and are never sent.
enum ReturnKey {
    /// The words before the Return just typed after them; nil unless the
    /// change from `old` to `new` ends in a new line and adds no more than
    /// the end of one word before it -- what typing delivers when the last
    /// letters, or an autocorrection, arrive with the Return. A pasted
    /// phrase adds spaces or lines, and is not Return.
    static func pressed(was old: String, now new: String) -> String? {
        guard new.hasSuffix("\n") else { return nil }
        let words = String(new.dropLast())
        let added = words.dropFirst(words.commonPrefix(with: old).count)
        return added.contains(where: \.isWhitespace) ? nil : words
    }
}
