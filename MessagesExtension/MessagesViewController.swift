import UIKit
import SwiftUI
import Messages
import os
import PickerCore

/// Filter Console.app by subsystem "com.chipmullins.forkroad.messages" to follow
/// the extension's launch on a real device (no Xcode attach needed).
let messagesLog = Logger(subsystem: "com.chipmullins.forkroad.messages", category: "lifecycle")

/// Entry point for the ForkRoad iMessage app.
///
/// Every vote message carries the web link to its session
/// (https://<host>/v/<id>). Tapping a vote bubble opens it here; friends
/// without ForkRoad can use the same link in a browser.
final class MessagesViewController: MSMessagesAppViewController {
    private let state = MessagesState()
    private var hosting: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Paint our background first. If the drawer is still the system's light
        // gray after this, the extension never got this far (it failed to launch);
        // if it turns dark but stays empty, the SwiftUI view is the problem.
        view.backgroundColor = UIColor(Theme.night)
        messagesLog.notice("viewDidLoad")
        let firebaseReady = FirebaseSetup.configureIfPossible()
        messagesLog.notice("Firebase configured: \(firebaseReady, privacy: .public)")
        Theme.applyUIKitAppearance()
        state.controller = self

        let root = AnyView(
            MessagesRootView(state: state)
                .font(Theme.body(15))
                .tint(Theme.accentText)
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = UIColor(Theme.night)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hosting = host
        messagesLog.notice("SwiftUI root attached")
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        UsageStats.recordActiveDevice()
        messagesLog.notice("willBecomeActive, style \(self.presentationStyle.rawValue, privacy: .public)")
        state.style = presentationStyle
        state.open(message: conversation.selectedMessage)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        state.style = presentationStyle
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        state.open(message: message)
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        state.open(message: nil)
    }
}

/// UI state for the extension, plus the bridge back to Messages.
@MainActor
@Observable
final class MessagesState {
    var style: MSMessagesAppPresentationStyle = .compact
    private(set) var sessionID: String?

    @ObservationIgnored weak var controller: MSMessagesAppViewController?

    var isExpanded: Bool { style == .expanded }

    func open(message: MSMessage?) {
        sessionID = message?.url.flatMap(GroupLinks.sessionID(from:))
    }

    func showNewVote() { sessionID = nil }

    /// Extensions can't open links directly; ask the host (Messages) to.
    func open(url: URL) { controller?.extensionContext?.open(url) { @Sendable _ in } }

    func expand() { controller?.requestPresentationStyle(.expanded) }
    func collapse() { controller?.requestPresentationStyle(.compact) }

    /// Drops text into the message field (you tap send), e.g. a nudge.
    func insertText(_ text: String) {
        controller?.activeConversation?.insertText(text) { @Sendable _ in }
        collapse()
    }

    /// Puts a new vote bubble in the message field (and optionally the web link
    /// as text, for friends who don't have ForkRoad).
    func insertNewVote(_ session: GroupSession, includeWebLink: Bool) {
        guard let conversation = controller?.activeConversation else { return }
        let message = MSMessage(session: MSSession())
        configure(message, session: session, tally: Tally(options: session.options, votes: []))
        conversation.insert(message) { @Sendable _ in }
        Self.rememberPosted(session)
        if includeWebLink, let url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost) {
            conversation.insertText("No ForkRoad? Vote here: \(url.absoluteString)") { @Sendable _ in }
        }
        collapse()
    }

    /// Sends an updated bubble that replaces the earlier one in the thread.
    func sendUpdate(_ session: GroupSession, tally: Tally, memberCount: Int) {
        guard let conversation = controller?.activeConversation else { return }
        let message = MSMessage(session: conversation.selectedMessage?.session ?? MSSession())
        configure(message, session: session, tally: tally, memberCount: memberCount)
        conversation.send(message) { @Sendable _ in }
        Self.rememberPosted(session)
    }

    // MARK: Is the chat's bubble up to date?

    /// What the bubble shows: open or decided, the winner, and the time.
    private static func bubbleKey(_ session: GroupSession) -> String {
        "\(session.status.rawValue)|\(session.winnerID ?? "")|\(Int(session.meetTime?.timeIntervalSince1970 ?? 0))"
    }

    private static func rememberPosted(_ session: GroupSession) {
        SharedDefaults.store.set(bubbleKey(session), forKey: "bubble.\(session.id)")
    }

    /// True when the group changed (decided in the app, new time…) since this
    /// phone last posted a bubble, so the creator should post the plan.
    static func bubbleIsOutdated(_ session: GroupSession) -> Bool {
        SharedDefaults.store.string(forKey: "bubble.\(session.id)") != bubbleKey(session)
    }

    private func configure(_ message: MSMessage, session: GroupSession, tally: Tally, memberCount: Int = 0) {
        message.url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost)

        let layout = MSMessageTemplateLayout()
        layout.image = VoteBubbleImage.render(session: session, tally: tally)
        if let winner = session.winner {
            layout.caption = "We’re going to \(winner.name)"
            let meet = session.meetTime.map { "Meet \(MeetTimes.phrase(for: $0))" }
            layout.subcaption = session.rsvpOpen
                ? [meet, "Tap to RSVP"].compactMap { $0 }.joined(separator: " · ")
                : meet ?? (session.mode == .spin ? "Picked by the spin · tap for directions" : "Tap for directions")
            message.summaryText = "Picked \(winner.name)"
        } else {
            layout.caption = session.title
            if session.mode == .spin {
                layout.subcaption = "Tap to add your pick to the wheel"
                message.summaryText = "Spin: \(session.title)"
            } else {
                let votes = tally.totalVotes
                layout.subcaption = votes == 0 ? "Tap to vote" : "\(votes) vote\(votes == 1 ? "" : "s") so far · tap to vote"
                message.summaryText = "Vote: \(session.title)"
            }
        }
        message.layout = layout
    }
}
