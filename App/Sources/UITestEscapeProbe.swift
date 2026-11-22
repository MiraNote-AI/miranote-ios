#if DEBUG
import notify
import UIKit

/// -UITEST only: VoiceOver's two-finger escape, which XCUITest cannot
/// perform. A test posts the Darwin notification `escape.<identifier>` (see
/// `EscapeProbe.prefix`) for where VoiceOver's focus would be; the probe
/// finds that element in the app's accessibility tree and offers it the
/// escape as UIKit does -- the element, then each container and view above
/// it, until one takes it -- and records which one did (`last`, the canvas
/// probe's "escape"). A model of VoiceOver's walk, not VoiceOver itself.
@MainActor
enum EscapeProbe {
    static let prefix = "ai.miranote.uitest.escape."
    /// Where VoiceOver's focus can be in the text and Background tools.
    static let targets = [
        "canvas.textEditor", "writing.ask", "style.mic", "keyboard.done", "style.font", "text.row.back",
        "style.font.Josefin", "style.size.M", "style.color.custom", "style.ai.original", "style.highlight.none",
        "background.back", "background.tool.paper", "background.row.back"
    ]
    /// The last escape: its count, where it started, what took it.
    private(set) static var last = ""
    private static var count = 0
    private static var tokens: [Int32] = []

    static func listen() {
        guard tokens.isEmpty, ProcessInfo.processInfo.arguments.contains("-UITEST") else { return }
        for id in targets {
            var token: Int32 = 0
            notify_register_dispatch(prefix + id, &token, .main) { _ in
                MainActor.assumeIsolated { escape(from: id) }
            }
            tokens.append(token)
        }
    }

    private static func escape(from id: String) {
        count += 1
        let windows = UIApplication.shared.connectedScenes.flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
        var visited = 0
        var seenIDs: [String] = []
        var matches: [NSObject] = []
        for window in windows where matches.isEmpty {
            matches = find(id, in: window, visited: &visited, ids: &seenIDs)
        }
        // The element VoiceOver would focus: of the nodes carrying `id`, the
        // one that is an accessibility element (SwiftUI may also tag the
        // platform view under it).
        guard let element = matches.first(where: \.isAccessibilityElement) ?? matches.last else {
            last = "\(count) \(id): not found in \(visited) nodes of \(windows.count) windows; ids "
                + seenIDs.prefix(30).joined(separator: ",")
            return
        }
        let carriers = matches.map { "\(type(of: $0))\($0.isAccessibilityElement ? "*" : "")" }
            .joined(separator: ",")
        var node: NSObject? = element
        var walked: [String] = []
        let blockGetter = NSSelectorFromString("accessibilityPerformEscapeBlock")
        while let current = node {
            let taken = "\(count) \(id): taken at \(walked.count) by \(type(of: current))"
            if current.accessibilityPerformEscape() {
                last = "\(taken) [\(carriers)]"
                return
            }
            // An escape block the method did not run (not every node knows
            // the property): as the system would, it asks the block.
            if current.responds(to: blockGetter), let block = current.accessibilityPerformEscapeBlock, block() {
                last = "\(taken)'s block alone [\(carriers)]"
                return
            }
            walked.append("\(type(of: current))")
            node = parent(of: current)
        }
        last = "\(count) \(id): not taken by " + walked.joined(separator: " > ") + " [\(carriers)]"
    }

    /// Every node in the tree under `root` carrying `id`.
    private static func find(_ id: String, in root: NSObject, visited: inout Int, ids: inout [String]) -> [NSObject] {
        var queue: [NSObject] = [root]
        var seen = Set<ObjectIdentifier>()
        var found: [NSObject] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            visited += 1
            if let nodeID = identifier(of: node), !nodeID.isEmpty {
                if nodeID == id { found.append(node) } else if ids.count < 60 { ids.append(nodeID) }
            }
            queue += children(of: node)
        }
        return found
    }

    /// SwiftUI's nodes answer `accessibilityIdentifier` without declaring
    /// UIAccessibilityIdentification.
    private static func identifier(of node: NSObject) -> String? {
        if let identified = node as? UIAccessibilityIdentification { return identified.accessibilityIdentifier }
        let getter = NSSelectorFromString("accessibilityIdentifier")
        guard node.responds(to: getter) else { return nil }
        return node.perform(getter)?.takeUnretainedValue() as? String
    }

    private static func children(of node: NSObject) -> [NSObject] {
        var children: [NSObject] = []
        if let elements = node.accessibilityElements {
            children += elements.compactMap { $0 as? NSObject }
        } else {
            let count = node.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                children += (0..<count).compactMap { node.accessibilityElement(at: $0) as? NSObject }
            }
        }
        if let view = node as? UIView { children += view.subviews }
        return children
    }

    private static func parent(of node: NSObject) -> NSObject? {
        let container = NSSelectorFromString("accessibilityContainer")
        if node.responds(to: container), let up = node.perform(container)?.takeUnretainedValue() as? NSObject {
            return up
        }
        return (node as? UIView)?.superview
    }
}
#endif
