import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import PickerCore

enum GroupError: LocalizedError {
    case notConfigured
    case sessionNotFound
    case notOwner
    case alreadyAdded
    case optionsFull
    case alreadyPicked
    case closed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Group voting isn’t set up yet. Add Firebase (see the README)."
        case .sessionNotFound: return "This group pick has ended or doesn’t exist."
        case .notOwner: return "Only the person who started this pick can lock it in."
        case .alreadyAdded: return "That place is already in the vote."
        case .optionsFull: return "This pick already has 12 places, the most it can hold."
        case .alreadyPicked: return "You’ve already added your pick. Everyone gets one."
        case .closed: return "This pick is locked in, so places can’t be added or changed."
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
        let options = options.map { option -> GroupOption in
            var option = option
            option.addedByID = uid
            return option
        }
        let session = GroupSession(
            id: ref.documentID,
            title: title,
            joinCode: code,
            createdBy: uid,
            createdByName: displayName,
            createdAt: Date(),
            closesAt: closesInMinutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) },
            mode: mode,
            options: options,
            // A spin creator's starting place is their one pick.
            picksBy: mode == .spin ? options.first.map { [uid: $0.id] } : nil
        )
        try await ref.setData(Firestore.Encoder().encode(session))
        // joinCodes/{code} → session, so codes can be looked up without
        // letting anyone list every session.
        try await joinCodeRef(code).setData(["sessionId": session.id, "createdBy": uid])
        try await join(sessionID: session.id, displayName: displayName)
        UsageStats.record(mode == .spin ? .groupsSpin : .groupsVote)
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
        // Your blacklist, scrambled for this group, so blocked places can't win.
        data["blockedHashes"] = GroupBlacklist.hashes(placeIDs: SharedCache.blockedPlaceIDs(), sessionID: sessionID)
        // Merge, so joining again never wipes a saved push token.
        try await sessionRef(sessionID).collection("members").document(uid).setData(data, merge: true)
        SharedCache.rememberSession(sessionID)
    }

    /// Re-shares your blacklist with a group you're already in (it may have
    /// changed since you joined). Quietly does nothing if you're not a member.
    func shareBlacklist(sessionID: String) async {
        guard let uid = try? await userID() else { return }
        let hashes = GroupBlacklist.hashes(placeIDs: SharedCache.blockedPlaceIDs(), sessionID: sessionID)
        try? await sessionRef(sessionID).collection("members").document(uid).updateData(["blockedHashes": hashes])
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

    /// Adds a place, following the group's limits. One pick each (creator too)
    /// in a spin; in a vote, the creator can add up to 12 and everyone else
    /// can suggest one. If you've already used your pick, this swaps it for
    /// the new place (in the same spot in the list). A transaction, so two
    /// people adding at once can't break the limits.
    func addOption(sessionID: String, option: GroupOption) async throws {
        let uid = try await userID()
        let ref = sessionRef(sessionID)
        var option = option
        option.addedByID = uid
        let data = try Firestore.Encoder().encode(option)
        let optionID = option.id
        let name = option.name, lat = option.latitude, lon = option.longitude
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                guard snapshot.exists, let fields = snapshot.data() else { throw GroupError.sessionNotFound }
                guard fields["status"] as? String == GroupStatus.open.rawValue else { throw GroupError.closed }
                let existing = fields["options"] as? [[String: Any]] ?? []
                let picks = fields["picksBy"] as? [String: String] ?? [:]
                let isOwner = fields["createdBy"] as? String == uid
                let isSpin = fields["mode"] as? String == GroupMode.spin.rawValue
                let usesPick = isSpin || !isOwner
                let oldPick = usesPick ? picks[uid] : nil

                let others = existing.filter { oldPick == nil || $0["id"] as? String != oldPick }
                if others.contains(where: { Self.isSamePlace($0, id: optionID, name: name, latitude: lat, longitude: lon) }) {
                    throw GroupError.alreadyAdded
                }

                if let oldPick, let index = existing.firstIndex(where: { $0["id"] as? String == oldPick }) {
                    // Change my pick: replace it where it was (the rules check
                    // that only your own pick was swapped).
                    var options = existing
                    options[index] = data
                    transaction.updateData(["options": options, "picksBy.\(uid)": optionID], forDocument: ref)
                    return nil
                }
                if existing.count >= GroupSession.maxOptions { throw GroupError.optionsFull }
                var update: [String: Any] = ["options": FieldValue.arrayUnion([data])]
                if usesPick { update["picksBy.\(uid)"] = optionID }
                transaction.updateData(update, forDocument: ref)
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
        UsageStats.record(.groupPicks)
    }

    // MARK: Owner actions

    /// Locks in the result. Votes: most votes wins, with a fair tie-break.
    /// Spin: a fair random pick among all options.
    /// Places someone in the group blacklisted (`ruledOut`) can't win.
    func decide(session: GroupSession, votes: [GroupVote], ruledOut: Set<String> = []) async throws -> String? {
        let uid = try await userID()
        guard session.isOwned(by: uid) else { throw GroupError.notOwner }
        guard let winner = session.pickWinner(votes: votes, ruledOut: ruledOut) else { return nil }
        try await sessionRef(session.id).updateData(["status": GroupStatus.decided.rawValue, "winnerID": winner])
        return winner
    }

    /// The creator takes a place out of an open group. Its votes are cleared,
    /// and whoever added it gets their pick back so they can add another.
    func removeOption(_ optionID: String, from session: GroupSession) async throws {
        let uid = try await userID()
        guard session.isOwned(by: uid) else { throw GroupError.notOwner }
        let ref = sessionRef(session.id)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                guard snapshot.exists, let fields = snapshot.data() else { throw GroupError.sessionNotFound }
                guard fields["status"] as? String == GroupStatus.open.rawValue else { throw GroupError.closed }
                let options = (fields["options"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != optionID }
                var update: [String: Any] = ["options": options]
                let picks = fields["picksBy"] as? [String: String] ?? [:]
                for (person, picked) in picks where picked == optionID {
                    update["picksBy.\(person)"] = FieldValue.delete()
                }
                transaction.updateData(update, forDocument: ref)
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
        // Votes for it no longer count; clear them so people can vote again.
        let stale = try? await ref.collection("votes").whereField("optionID", isEqualTo: optionID).getDocuments()
        for doc in stale?.documents ?? [] { try? await doc.reference.delete() }
    }

    func reopen(session: GroupSession) async throws {
        let uid = try await userID()
        guard session.isOwned(by: uid) else { throw GroupError.notOwner }
        try await sessionRef(session.id).updateData(["status": GroupStatus.open.rawValue, "winnerID": FieldValue.delete()])
    }

    /// Same ID, or the same name within about 150 m. Apple Maps on the web
    /// (friends adding from the vote page) and on iPhone can disagree by a
    /// few meters, which changes the ID. Matches `sameOption` in web/public/app.js.
    nonisolated static func isSamePlace(_ data: [String: Any], id: String, name: String,
                                        latitude: Double, longitude: Double) -> Bool {
        if data["id"] as? String == id { return true }
        guard let otherName = data["name"] as? String,
              otherName.trimmingCharacters(in: .whitespaces).lowercased() == name.trimmingCharacters(in: .whitespaces).lowercased(),
              let otherLat = data["latitude"] as? Double, let otherLon = data["longitude"] as? Double else { return false }
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: otherLat, longitude: otherLon)
        return a.distance(from: b) < 160
    }

    /// Ends a group for everyone: deletes its votes, members, join code, and the session.
    func endSession(_ session: GroupSession) async throws {
        let uid = try await userID()
        guard session.isOwned(by: uid) else { throw GroupError.notOwner }
        let ref = sessionRef(session.id)
        for name in ["votes", "members"] {
            let docs = try await ref.collection(name).getDocuments().documents
            for doc in docs { try await doc.reference.delete() }
        }
        try? await joinCodeRef(session.joinCode).delete()
        try await ref.delete()
        SharedCache.forgetSession(session.id)
    }

    /// Leaves a group: removes your vote and membership, and forgets it on this device.
    func leaveSession(_ sessionID: String) async throws {
        let uid = try await userID()
        let ref = sessionRef(sessionID)
        try? await ref.collection("votes").document(uid).delete()
        try await ref.collection("members").document(uid).delete()
        SharedCache.forgetSession(sessionID)
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

    /// Saves (or clears) the creator's short note sent with the plan.
    /// An extra field, so older app versions simply don't show it.
    func setNote(sessionID: String, note: String) async throws {
        _ = try await userID()
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(GroupSession.maxNoteLength))
        let value: Any = text.isEmpty ? FieldValue.delete() : text
        try await sessionRef(sessionID).updateData(["note": value])
    }
}
