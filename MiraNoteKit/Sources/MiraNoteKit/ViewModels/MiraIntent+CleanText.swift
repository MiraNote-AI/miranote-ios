import Foundation

// Text hygiene for words that land on the canvas (split from
// MiraIntent.swift for the type-body size cap).
extension MiraIntent {
    /// The model structured a draft (create_note) mid-conversation? On
    /// the canvas that MEANS "these words, on this page" -- land the clean
    /// body; the chatter never touches the paper.
    static func landedDraft(from reply: ChatReply) -> MiraOutcome? {
        guard let draft = reply.pageDraft else { return nil }
        let words = cleanPlacedText(draft.body.isEmpty ? draft.title : draft.body)
        guard !words.isEmpty else { return nil }
        return .textAdded(words, MiraReceipt(
            changed: "Added a few words.",
            kept: "Everything else stayed put."
        ))
    }

    /// Words landing on the CANVAS must be plain prose: markdown line
    /// decorations go, emphasis marks go, and when the reply frames a
    /// quoted suggestion ("how about: '...'"), the quote IS the payload.
    static func cleanPlacedText(_ raw: String) -> String {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                while trimmed.hasPrefix(">") || trimmed.hasPrefix("#") {
                    trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return trimmed
            }
        var kept = lines
        // A lead-in that just announces the payload ("Here's a caption:")
        // is chatter; so is a trailing "feel free to tweak" paragraph.
        while let first = kept.first(where: { !$0.isEmpty }), first.hasSuffix(":"),
              let index = kept.firstIndex(of: first) {
            kept.remove(at: index)
        }
        let metaCues = ["it's ready", "feel free", "let me know", "just say", "hope you",
                        "if you'd like", "want me to", "would you like"]
        while let last = kept.last(where: { !$0.isEmpty }),
              metaCues.contains(where: { last.lowercased().hasPrefix($0) || last.lowercased().contains($0) }),
              let index = kept.lastIndex(of: last) {
            kept.remove(at: index)
        }
        var text = kept.joined(separator: "\n")
        for mark in ["**", "__", "*", "_", "`"] {
            text = text.replacingOccurrences(of: mark, with: "")
        }
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var longestQuote = ""
        for (open, close) in [("\"", "\""), ("\u{201C}", "\u{201D}")] {
            var rest = Substring(text)
            while let start = rest.firstIndex(of: Character(open)) {
                let after = rest.index(after: start)
                guard let end = rest[after...].firstIndex(of: Character(close)) else { break }
                let span = String(rest[after..<end])
                if span.count > longestQuote.count { longestQuote = span }
                rest = rest[rest.index(after: end)...]
            }
        }
        if longestQuote.count >= 20 {
            return longestQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// The part of a conversational reply that is actually meant for the
    /// page: a quoted or emphasized suggestion of real length. Plain
    /// banter has no payload -- the place-on-page chip should not appear
    /// for "I'm good, thanks for asking!".
    static func placeablePayload(_ raw: String) -> String? {
        var longest = ""
        for (open, close) in [
            ("\"", "\""), ("\u{201C}", "\u{201D}"), ("*", "*"), ("_", "_"),
        ] {
            var rest = Substring(raw)
            while let start = rest.firstIndex(of: Character(open)) {
                let after = rest.index(after: start)
                guard let end = rest[after...].firstIndex(of: Character(close)) else { break }
                let span = String(rest[after..<end])
                if span.count > longest.count { longest = span }
                rest = rest[rest.index(after: end)...]
            }
        }
        let cleaned = cleanPlacedText(longest)
        return cleaned.count >= 20 ? cleaned : nil
    }

    /// LLM replies arrive with quotes, trailing periods, or a chatty
    /// second line; a title is one clean line.
    static func cleanTitle(_ raw: String) -> String {
        let firstLine = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let noise = CharacterSet(charactersIn: "\"'`.\u{201C}\u{201D}\u{2018}\u{2019}")
            .union(.whitespacesAndNewlines)
        var title = firstLine.trimmingCharacters(in: noise)
        if title.count > 60 {
            title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces)
        }
        return title
    }
}
