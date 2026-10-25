import UIKit
import SwiftUI
import Messages
import PickerCore

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
        FirebaseSetup.configureIfPossible()
        Theme.applyUIKitAppearance()
        state.controller = self

        let root = AnyView(
            MessagesRootView(state: state)
                .font(Theme.body(15))
                .preferredColorScheme(.dark)
                .tint(Theme.saffron)
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
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
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
    func open(url: URL) { controller?.extensionContext?.open(url, completionHandler: nil) }

    func expand() { controller?.requestPresentationStyle(.expanded) }
    func collapse() { controller?.requestPresentationStyle(.compact) }

    /// Puts a new vote bubble in the message field (and optionally the web link
    /// as text, for friends who don't have ForkRoad).
    func insertNewVote(_ session: GroupSession, includeWebLink: Bool) {
        guard let conversation = controller?.activeConversation else { return }
        let message = MSMessage(session: MSSession())
        configure(message, session: session, tally: Tally(options: session.options, votes: []))
        conversation.insert(message) { _ in }
        if includeWebLink, let url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost) {
            conversation.insertText("No ForkRoad? Vote here: \(url.absoluteString)") { _ in }
        }
        collapse()
    }

    /// Sends an updated bubble that replaces the earlier one in the thread.
    func sendUpdate(_ session: GroupSession, tally: Tally, memberCount: Int) {
        guard let conversation = controller?.activeConversation else { return }
        let message = MSMessage(session: conversation.selectedMessage?.session ?? MSSession())
        configure(message, session: session, tally: tally, memberCount: memberCount)
        conversation.send(message) { _ in }
    }

    private func configure(_ message: MSMessage, session: GroupSession, tally: Tally, memberCount: Int = 0) {
        message.url = GroupLinks.webURL(sessionID: session.id, host: AppConfig.webHost)

        let layout = MSMessageTemplateLayout()
        layout.image = VoteBubbleImage.render(session: session, tally: tally)
        if let winner = session.winner {
            layout.caption = "We’re going to \(winner.name)"
            layout.subcaption = session.meetTime.map { "Meet at \($0.formatted(date: .omitted, time: .shortened))" } ?? "Tap for directions"
            message.summaryText = "Picked \(winner.name)"
        } else {
            layout.caption = session.title
            let votes = tally.totalVotes
            layout.subcaption = votes == 0 ? "Tap to vote" : "\(votes) vote\(votes == 1 ? "" : "s") so far · tap to vote"
            message.summaryText = "Vote: \(session.title)"
        }
        message.layout = layout
    }
}
