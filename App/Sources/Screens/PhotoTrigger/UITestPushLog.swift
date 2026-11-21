#if DEBUG
import MiraNoteKit
import SwiftUI

/// `-UITEST-TRIGGER`: the synthetic notification centre with every request
/// it adds noted for `TriggerNotifierProbe`, so a test can see a push handed
/// over and when it would fire. It changes nothing else.
struct UITestPushLog: PushNotificationCenter {
    let base: PushNotificationCenter
    static let handed = HandedRequests()

    func isAllowed() async -> Bool { await base.isAllowed() }
    func requestPermission() async -> Bool { await base.requestPermission() }
    func pending() async -> Set<String> { await base.pending() }
    func removePending(_ identifiers: [String]) async { await base.removePending(identifiers) }
    func removeDelivered(_ identifiers: [String]) async { await base.removeDelivered(identifiers) }

    /// A debug push (no slot) fires `LivePushNotificationCenter.delay` s
    /// after it is added, as the live centre's trigger does; a slot push at
    /// its night.
    func schedule(_ record: PushRecord, identifier: String, at: DateComponents?, relevance: Double) async -> Bool {
        let added = await base.schedule(record, identifier: identifier, at: at, relevance: relevance)
        if added {
            let fires = at == nil ? "\(Int(LivePushNotificationCenter.delay))s" : "slot"
            Self.handed.note("\(identifier):\(fires)@\(Date().timeIntervalSince1970)")
        }
        return added
    }
}

/// The requests added this launch, oldest first.
final class HandedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func note(_ line: String) { lock.withLock { lines.append(line) } }
    var text: String { lock.withLock { lines.joined(separator: ";") } }
}

/// -UITEST-TRIGGER only: the requests the notification centre was handed
/// ("identifier:10s@epoch" for a debug push, ";"-joined).
struct TriggerNotifierProbe: View {
    @State private var text = ""

    var body: some View {
        Text(text.isEmpty ? "empty" : text)
            .font(.system(size: 1))
            .opacity(0.01)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier("debug.triggerNotifier")
            .task {
                while !Task.isCancelled {
                    text = UITestPushLog.handed.text
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
    }
}
#endif
