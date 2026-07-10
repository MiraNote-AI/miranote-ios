import Foundation

/// Assistant prose arrives with light markdown -- the journal persona
/// bolds page titles it cites. Bubbles render that as styled text; when
/// parsing fails the raw words still show, never an empty bubble.
public enum ChatMarkdown {
    public static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }
}
