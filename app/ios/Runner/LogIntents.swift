import AppIntents

// The Action button (and Siri) entry point. iOS will not give a background intent the
// microphone, so this opens the app and leaves a note; the Flutter side reads the note on
// launch or resume and starts listening. The whole voice pipeline -- silence auto-send,
// transcription, the confirm card -- is reused as-is.

let pendingActionKey = "dayby.pendingAction"

@available(iOS 16.0, *)
struct LogByVoiceIntent: AppIntent {
  static var title: LocalizedStringResource = "Log by voice"
  static var description = IntentDescription("Open Dayby and start listening.")

  // Opening is the point: the mic cannot be reached from the background.
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    UserDefaults.standard.set("log_voice", forKey: pendingActionKey)
    return .result()
  }
}

@available(iOS 16.0, *)
struct DaybyShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogByVoiceIntent(),
      phrases: [
        "Log with \(.applicationName)",
        "Record a moment in \(.applicationName)",
      ],
      shortTitle: "Log by voice",
      systemImageName: "mic.fill"
    )
  }
}
