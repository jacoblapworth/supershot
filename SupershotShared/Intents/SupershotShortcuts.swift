import AppIntents

nonisolated struct SupershotShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: CreateGameIntent(),
      phrases: [
        "Create a game in \(.applicationName)",
        "Create a netball game in \(.applicationName)",
        "Create a \(.applicationName) game"
      ],
      shortTitle: "Create Game",
      systemImageName: "plus.circle"
    )
  }
}
