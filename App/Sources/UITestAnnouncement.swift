#if DEBUG
/// -UITEST probe: the last words the app announced to VoiceOver, shown on
/// the debug state probe -- a test cannot hear an announcement.
enum UITestAnnouncement {
    // Set and read on the main thread (actions, view bodies); a test
    // record, not state.
    nonisolated(unsafe) static var last = ""
}
#endif
