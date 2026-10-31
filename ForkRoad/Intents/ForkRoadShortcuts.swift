import AppIntents

/// Siri phrases and Shortcuts app tiles. Every phrase must include the app name.
struct ForkRoadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PickDinnerIntent(),
            phrases: [
                "Pick dinner with \(.applicationName)",
                "Pick lunch with \(.applicationName)",
                "Pick breakfast with \(.applicationName)",
                "What should I eat \(.applicationName)",
                "Pick a restaurant with \(.applicationName)",
                "Where should I eat \(.applicationName)"
            ],
            shortTitle: "Pick a place to eat",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: OpenSpinIntent(),
            phrases: [
                "Spin \(.applicationName)",
                "Spin in \(.applicationName)",
                "Open the spinner in \(.applicationName)"
            ],
            shortTitle: "Spin",
            systemImageName: "sparkles"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .orange
}
