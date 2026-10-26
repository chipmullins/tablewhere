import Foundation
import FirebaseAuth
import FirebaseFirestore
import PickerCore

enum GroupError: LocalizedError {
    case notConfigured
    case sessionNotFound
    case notOwner

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Group voting isn’t set up yet. Add Firebase (see the README)."
        case .sessionNotFound: return "No group found with that code."
        case .notOwner: return "Only the person who started this pick can lock it in."
        }
    }
}

/// Reads and writes group sessions in Firestore.
///
/// Layout:
///   sessions/{id}                 the GroupSession
///   sessions/{id}/members/{uid}   who's in
///   sessions/{id}/votes/{uid}     one vote per person
///
/// Everyone signs in anonymously, so there are no accounts or passwords.
@MainActor
final class GroupService {
    static let shared = GroupService()
    private init() {}

    private var db: Firestore { Firestore.firestore() }

    var currentUserID: String? { Auth.auth().currentUser?.uid }

    /// Signs in anonymously if needed and returns the user ID.
    func userID() async throws -> String {
        guard FirebaseSetup.configureIfPossible() else { throw GroupError.notConfigured }
        if let user = Auth.auth().currentUser { return user.uid }
        return try await Auth.auth().signInAnonymously().user.uid
    }

    func sessionRef(_ id: String) -> DocumentReference {
        db.collection("sessions").document(id)
    }

    // MARK: Create & join

    func createSession(title: String, mode: GroupMode, options: [GroupOption],
                       closesInMinutes: Int?, displayName: String) async throws -> GroupSession {
        let uid = try await userID()
        let code = try await unusedJoinCode()
        let ref = db.collection("sessions").document()
        let session = GroupSession(
            id: ref.documentID,
            title: title,
            joinCode: code,
            createdBy: uid,
            createdByName: displayName,
            createdAt: Date(),
            closesAt: closesInMinutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) },
            mode: mode,
            options: options
        )
        try await ref.setData(Firestore.Encoder().encode(session))
        // joinCodes/{code} → session, so codes can be looked up without
        // letting anyone list every session.
        try await joinCodeRef(code).setData(["sessionId": session.id, "createdBy": uid])
        try await join(sessionID: session.id, displayName: displayName)
        return session
    }

    func findSession(joinCode: String) async throws -> GroupSession {
        _ = try await userID()
        let code = JoinCode.normalize(joinCode)
        guard code.count == 6,
              let sessionID = try await joinCodeRef(code).getDocument().data()?["sessionId"] as? String
        else { throw GroupError.sessionNotFound }
        let doc = try await sessionRef(sessionID).getDocument()
        guard doc.exists else { throw GroupError.sessionNotFound }
        return try doc.data(as: GroupSession.self)
    }

    private func joinCodeRef(_ code: String) -> DocumentReference {
        db.collection("joinCodes").document(code)
    }

    /// A join code nobody else is using (collisions are rare, but check anyway).
    private func unusedJoinCode() async throws -> String {
        for _ in 0..<5 {
            let code = JoinCode.make()
            let taken = try await joinCodeRef(code).getDocument().exists
            if !taken { return code }
        }
        return JoinCode.make()
    }

    func join(sessionID: String, displayName: String) async throws {
        let uid = try await userID()
        var data: [String: Any] = [
            "id": uid,
            "name": displayName,
            "joinedAt": FieldValue.serverTimestamp()
        ]
        // The app saves this device's push token here (also readable by the iMessage extension).
        if let token = SharedDefaults.store.string(forKey: "fcmToken") { data["fcmToken"] = token }
        // Merge, so joining again never wipes a saved push token.
        try await sessionRef(sessionID).collection("members").document(uid).setData(data, merge: true)
        SharedCache.rememberSession(sessionID)
    }

    /// Saves a new push token on every group this device is in, so the server
    /// can notify it ("Maya voted", "It's decided").
    func updatePushToken(_ token: String) async {
        guard let uid = try? await userID() else { return }
        for sessionID in SharedCache.recentSessionIDs() {
            try? await sessionRef(sessionID).collection("members").document(uid)
                .setData(["fcmToken": token], merge: true)
        }
    }

    // MARK: Taking part

    func vote(sessionID: String, optionID: String, displayName: String) async throws {
        let uid = try await userID()
        try await sessionRef(sessionID).collection("votes").document(uid).setData([
            "voterID": uid,
            "voterName": displayName,
            "optionID": optionID,
            "votedAt": FieldValue.serverTimestamp()
        ])
    }

    func removeVote(sessionID: String) async throws {
        let uid = try await userID()
        try await sessionRef(sessionID).collection("votes").document(uid).delete()
    }

    func addOption(sessionID: String, option: GroupOption) async throws {
        _ = try await userID()
        let data = try Firestore.Encoder().encode(option)
        try await sessionRef(sessionID).updateData(["options": FieldValue.arrayUnion([data])])
    }

    // MARK: Owner actions

    /// Locks in the result. Votes: most votes wins, with a fair tie-break.
    /// Spin: a fair random pick among all options.
    func decide(session: GroupSession, votes: [GroupVote]) async throws -> String? {
        let uid = try await userID()
        guard session.isOwned(by: uid) else { throw GroupError.notOwner }
        let winner: String?
        switch session.mode {
        case .vote:
            winner = Tally(options: session.options, votes: votes).voteWinner(sessionID: session.id)
                ?? Tally.spinWinner(options: session.options, sessionID: session.id)
        case .spin:
            winner = Tally.spinWinner(options: session.options, sessionID: session.id)
        }
        guard let winner else { return nil }
        try await sessionRef(session.id).updateData(["status": GroupStatus.decided.rawValue, "winnerID": winner])
        return winner
    }

    func reopen(session: GroupSession) async throws {
        let uid = try await userID()
        guard session.isOwned(by: uid) else { throw GroupError.notOwner }
        try await sessionRef(session.id).updateData(["status": GroupStatus.open.rawValue, "winnerID": FieldValue.delete()])
    }

    func setMeetTime(sessionID: String, date: Date) async throws {
        _ = try await userID()
        // The label ("7:00 PM") is formatted here because the server doesn't
        // know anyone's time zone; it's used in the "Meet at…" push.
        try await sessionRef(sessionID).updateData([
            "meetTime": Timestamp(date: date),
            "meetTimeLabel": date.formatted(date: .omitted, time: .shortened)
        ])
    }
}
