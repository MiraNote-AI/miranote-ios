import Foundation

/// A multi-line field takes Return as a new line; the Mira fields treat it
/// as Send instead. Only a Return typed at the end counts: lines pasted in
/// (even ones ending in a new line) or a transcript with a line break stay
/// in the field and are never sent.
enum ReturnKey {
    /// The words before the Return just typed after them; nil unless the
    /// change from `old` to `new` is exactly one new line at the end.
    static func pressed(was old: String, now new: String) -> String? {
        new == old + "\n" ? old : nil
    }
}
