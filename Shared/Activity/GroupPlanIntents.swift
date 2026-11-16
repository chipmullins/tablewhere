import AppIntents
import Foundation

// The Lock Screen countdown's buttons (1.1): "I'm on my way", "Late +10",
// "Late +15", "I'm here". Compiled by the app, the iMessage extension, and the
// widget extension (which draws them); as a LiveActivityIntent, iOS runs
// `perform` in the APP's process, the only target built with TABLEWHERE_APP
// (project.yml), where GroupPlanActionRunner shares your arrival time.

enum GroupPlanAction: String {
    case onMyWay, late10, late15, arrived
}

struct GroupPlanActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update your group plan"
    static var description = IntentDescription("Tells your group you're on your way, running late, or there.")
    static var isDiscoverable: Bool = false
    /// Asks for Face ID / passcode first when the phone is locked. While it's
    /// locked, iOS keeps the app's saved sign-in out of reach, and the tap
    /// would act as a brand-new anonymous user (a second "you" in the plan).
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Plan") var sessionID: String
    @Parameter(title: "Action") var action: String

    init() {}

    init(sessionID: String, action: GroupPlanAction) {
        self.sessionID = sessionID
        self.action = action.rawValue
    }

    func perform() async throws -> some IntentResult {
        #if TABLEWHERE_APP
        if let action = GroupPlanAction(rawValue: action) {
            await GroupPlanActionRunner.run(action, sessionID: sessionID)
        }
        #endif
        return .result()
    }
}
