import Foundation

/// Assistant prose arrives with light markdown -- the journal persona
/// bolds page titles it cites, and expanded or drafted text may carry
/// "- " list lines. Rendering shows styling and real bullets; when
/// parsing fails the raw words still show, never an empty bubble.
/// Canvas text blocks share this: display renders, editing keeps the
/// raw characters untouched.
public enum ChatMarkdown {
    public static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let bulleted = withBullets(text)
        return (try? AttributedString(markdown: bulleted, options: options))
            ?? AttributedString(bulleted)
    }

    /// Inline-only parsing leaves list markers as literal "- ", so swap
    /// leading markers for a bullet glyph. Indentation survives; dashes
    /// inside a sentence are left alone.
    static func withBullets(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                let rest = line.dropFirst(indent.count)
                guard rest.hasPrefix("- ") || rest.hasPrefix("* ") else {
                    return String(line)
                }
                return indent + "\u{2022}  " + rest.dropFirst(2)
            }
            .joined(separator: "\n")
    }
}
