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
    /// The organizer's group filters don't allow it ("no fast food").
    case notAllowed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Group plans aren’t available right now."
        case .sessionNotFound: return "This group plan has ended or doesn’t exist."
        case .notOwner: return "Only the person who started this pick can lock it in."
        case .alreadyAdded: return "That place is already in the vote."
        case .optionsFull: return "This pick already has 12 places, the most it can hold."
        case .alreadyPicked: return "You’ve already added your pick. Everyone gets one."
        case .closed: return "This pick is locked in, so places can’t be added or changed."
        case .notAllowed(let rule): return "That place isn’t allowed in this group (\(rule))."
        }
    }
}

/// Reads and writes group sessions in Firestore.
///
/// Layout:
///   sessions/{id}                 the GroupSession
///   sessions/{id}/members/{uid}   who's in
///   sessions/{id}/votes/{uid}     one vote per person
///   sessions/{id}/rsvps/{uid}     one RSVP per person ("I'll pick" plans)
///   sessions/{id}/devices/{uid}   this phone's Lock Screen settings and push
///                                 tokens (only you and the server read it; 1.1)
///   sessions/{id}/eta/{uid}       "On my way": arrival time and status (1.1)
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

    /// Starts a group. An "I'll pick" plan (`.plan`) starts decided on its one
    /// place, with `meetTime` (required), the note, and the RSVP settings.
    func createSession(title: String, mode: GroupMode, options: [GroupOption],
                       closesInMinutes: Int?, displayName: String,
                       area: GroupArea? = nil,
                       meetTime: Date? = nil, note: String? = nil,
                       asksRSVP: Bool = false, rsvpBy: Date? = nil,
                       surprise: Bool = false, expectedCount: Int? = nil,
                       groupFilters: GroupFilters? = nil) async throws -> GroupSession {
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
            status: mode == .plan ? .decided : .open,
            options: options,
            winnerID: mode == .plan ? options.first?.id : nil,
            // Any mode can have a date & time; "I'll pick" requires one.
            meetTime: meetTime,
            // A spin creator's starting place is their one pick.
            // ("Surprise us" fills the wheel itself; nobody has a pick.)
            picksBy: mode == .spin && !surprise ? options.first.map { [uid: $0.id] } : nil,
            note: Self.cleanNote(note),
            area: area,
            asksRSVP: mode == .plan && asksRSVP ? true : nil,
            rsvpBy: mode == .plan && asksRSVP ? rsvpBy : nil,
            surprise: mode == .spin && surprise ? true : nil,
            expectedCount: Self.clampedExpected(expectedCount, mode: mode, surprise: surprise),
            groupFilters: Self.cleanFilters(groupFilters, mode: mode, surprise: surprise)
        )
        var data = try Firestore.Encoder().encode(session)
        if mode == .plan { data["announced"] = true }
        // The server's "Meet at…" pushes read this label (it doesn't know time zones).
        if let time = session.meetTime { data["meetTimeLabel"] = MeetTimes.label(for: time) }
        try await ref.setData(data)
        // joinCodes/{code} → session, so codes can be looked up without
        // letting anyone list every session.
        try await joinCodeRef(code).setData(["sessionId": session.id, "createdBy": uid])
        try await join(sessionID: session.id, displayName: displayName)
        switch mode {
        case .vote: UsageStats.record(.groupsVote)
        case .spin: UsageStats.record(.groupsSpin)
        case .plan: UsageStats.record(.groupsPlan)
        }
        return session
    }

    /// Group filters only apply where friends add picks (Vote, Spin our
    /// picks), and only when one is on.
    nonisolated static func cleanFilters(_ filters: GroupFilters?, mode: GroupMode, surprise: Bool) -> GroupFilters? {
        guard let filters, filters.isActive, mode == .vote || (mode == .spin && !surprise) else { return nil }
        return filters
    }

    /// The organizer changes the group filters while it's open (creator only).
    func setGroupFilters(sessionID: String, filters: GroupFilters) async throws {
        let value: Any = filters.isActive
            ? ["noFastFood": filters.noFastFood, "noCoffeeSweets": filters.noCoffeeSweets]
            : FieldValue.delete()
        try await sessionRef(sessionID).updateData(["groupFilters": value])
    }

    /// Only for plans that wait on everyone, within the allowed range.
    nonisolated static func clampedExpected(_ count: Int?, mode: GroupMode, surprise: Bool) -> Int? {
        guard let count, mode == .vote || (mode == .spin && !surprise) else { return nil }
        let range = GroupSession.expectedCountRange
        return min(max(count, range.lowerBound), range.upperBound)
    }

    /// "How many are eating?" (creator only). Nil clears it: back to counting joins.
    func setExpectedCount(sessionID: String, count: Int?) async throws {
        let range = GroupSession.expectedCountRange
        let value: Any = count.map { min(max($0, range.lowerBound), range.upperBound) } ?? FieldValue.delete()
        try await sessionRef(sessionID).updateData(["expectedCount": value])
    }

    /// iMessage: the creator opened the plan in a chat with this many people
    /// (counting them). Raises the expected count, never lowers it.
    func raiseExpectedCount(sessionID: String, to count: Int) async {
        guard let uid = try? await userID() else { return }
        let ref = sessionRef(sessionID)
        let target = min(count, GroupSession.expectedCountRange.upperBound)
        _ = try? await db.runTransaction { transaction, errorPointer in
            guard let snap = try? transaction.getDocument(ref), let data = snap.data(),
                  data["createdBy"] as? String == uid, data["status"] as? String == "open" else { return nil }
            let current = (data["expectedCount"] as? NSNumber)?.intValue ?? 0
            if target > current, target >= GroupSession.expectedCountRange.lowerBound {
                transaction.updateData(["expectedCount": target], forDocument: ref)
            }
            return nil
        }
    }

    private static func cleanNote(_ note: String?) -> String? {
        let text = String((note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(GroupSession.maxNoteLength))
        return text.isEmpty ? nil : text
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
        // Two Sams in one group become "Sam" and "Sam 2", so votes are clear.
        let name = await uniqueName(displayName, sessionID: sessionID, uid: uid)
        SharedDefaults.store.set(name, forKey: Self.nameKey(sessionID))
        var data: [String: Any] = [
            "id": uid,
            "name": name,
            "joinedAt": FieldValue.serverTimestamp()
        ]
        // The app saves this device's push token here (also readable by the iMessage extension).
        if let token = SharedDefaults.store.string(forKey: "fcmToken") { data["fcmToken"] = token }
        // Your blacklist, scrambled for this group, so blocked places can't win.
        data["blockedHashes"] = GroupBlacklist.hashes(placeIDs: SharedCache.blockedPlaceIDs(), sessionID: sessionID)
        // Merge, so joining again never wipes a saved push token.
        try await sessionRef(sessionID).collection("members").document(uid).setData(data, merge: true)
        SharedCache.rememberSession(sessionID)
        await saveDevice(sessionID: sessionID)
    }

    // MARK: This phone's Lock Screen settings (1.1)

    /// Copies the Live Activity settings and push-to-start token to this
    /// plan, so the server can start the countdown at the right time.
    /// Private: only you (and the server) can read sessions/{id}/devices/{uid}.
    func saveDevice(sessionID: String) async {
        guard let uid = try? await userID() else { return }
        var data: [String: Any] = [
            "leadMinutes": LiveActivitySettings.leadHours * 60,
            "removeWhen": LiveActivitySettings.removal.rawValue,
            "apnsEnv": LiveActivitySettings.apnsEnvironment,
            "countdownOn": LiveActivitySettings.countdownOn,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if LiveActivitySettings.serverStartsIt, let token = LiveActivitySettings.startToken {
            data["startToken"] = token
        } else {
            data["startToken"] = FieldValue.delete()
        }
        try? await sessionRef(sessionID).collection("devices").document(uid).setData(data, merge: true)
    }

    /// After a settings change or a new push-to-start token: every recent plan.
    func saveDeviceEverywhere() async {
        for id in SharedCache.recentSessionIDs() { await saveDevice(sessionID: id) }
    }

    /// The running activity's own push token (for updates and the end push),
    /// and which meet time it's for, so the server doesn't start a second one.
    func saveActivityToken(sessionID: String, token: String?, meetTime: Date) async {
        guard let uid = try? await userID() else { return }
        var data: [String: Any] = ["activityMeet": Timestamp(date: meetTime), "updatedAt": FieldValue.serverTimestamp()]
        if let token { data["updateToken"] = token }
        try? await sessionRef(sessionID).collection("devices").document(uid).setData(data, merge: true)
    }

    /// This phone's leave-by time, so a countdown the server starts shows it.
    /// (A time, not a location. Only you and the server can read it.)
    func saveLeavePlan(sessionID: String, leaveAt: Date, travelMinutes: Int, meetTime: Date) async {
        guard let uid = try? await userID() else { return }
        try? await sessionRef(sessionID).collection("devices").document(uid).setData([
            "leaveAt": Timestamp(date: leaveAt),
            "travelMinutes": travelMinutes,
            "planMeet": Timestamp(date: meetTime),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    /// Groups this device has joined since launch (so `joinIfNeeded` checks once).
    private var joinedSessions: Set<String> = []

    /// Joins with your saved name, unless you're already in the group. Used by
    /// the iMessage app, which joins only when you vote or add a place, so just
    /// opening a bubble doesn't make the group wait on you.
    func joinIfNeeded(sessionID: String) async throws {
        guard !joinedSessions.contains(sessionID), let name = Identity.displayName else { return }
        let uid = try await userID()
        let member = try? await sessionRef(sessionID).collection("members").document(uid).getDocument()
        if member?.exists != true {
            try await join(sessionID: sessionID, displayName: name)
        } else {
            await shareBlacklist(sessionID: sessionID)
        }
        joinedSessions.insert(sessionID)
    }

    nonisolated private static func nameKey(_ sessionID: String) -> String { "groupName.\(sessionID)" }

    /// The name you go by in this group ("Sam 2"), else `fallback`.
    nonisolated static func name(in sessionID: String, fallback: String) -> String {
        SharedDefaults.store.string(forKey: nameKey(sessionID)) ?? fallback
    }

    /// `name`, or "name 2", "name 3"… if someone else in the group already uses it.
    /// If the members can't be read, keeps the name as is.
    private func uniqueName(_ name: String, sessionID: String, uid: String) async -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let docs = try? await sessionRef(sessionID).collection("members").getDocuments().documents else {
            return trimmed
        }
        let taken = Set(docs.filter { $0.documentID != uid }
            .compactMap { ($0.data()["name"] as? String)?.lowercased() })
        guard taken.contains(trimmed.lowercased()) else { return trimmed }
        for number in 2...20 where !taken.contains("\(trimmed) \(number)".lowercased()) {
            return "\(trimmed) \(number)"
        }
        return trimmed
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
            "voterName": Self.name(in: sessionID, fallback: displayName),
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
        option.addedBy = Self.name(in: sessionID, fallback: option.addedBy)
        let data = try Firestore.Encoder().encode(option)
        let optionID = option.id
        let name = option.name, lat = option.latitude, lon = option.longitude
        let category = option.category
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                guard snapshot.exists, let fields = snapshot.data() else { throw GroupError.sessionNotFound }
                guard fields["status"] as? String == GroupStatus.open.rawValue else { throw GroupError.closed }
                // The organizer may have turned a filter on after the picker opened.
                if let filters = fields["groupFilters"] as? [String: Any] {
                    let rules = GroupFilters(noFastFood: filters["noFastFood"] as? Bool ?? false,
                                             noCoffeeSweets: filters["noCoffeeSweets"] as? Bool ?? false)
                    if let rule = rules.rule(name: name, category: category) { throw GroupError.notAllowed(rule) }
                }
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

    // MARK: RSVPs ("I'll pick" plans)

    /// Answers a plan: in (with guests) or can't make it. Joins the group too,
    /// so you get "change of plans" pushes. Answering again replaces it.
    func rsvp(sessionID: String, going: Bool, guests: Int, displayName: String) async throws {
        let uid = try await userID()
        if (try? await sessionRef(sessionID).collection("members").document(uid).getDocument().exists) != true {
            try await join(sessionID: sessionID, displayName: displayName)
        }
        let answer = GroupRSVP(userID: uid, name: Self.name(in: sessionID, fallback: displayName),
                               going: going, guests: guests)
        try await sessionRef(sessionID).collection("rsvps").document(uid).setData([
            "userID": uid,
            "name": String(answer.name.prefix(40)),
            "going": answer.going,
            "guests": answer.guests,
            "answeredAt": FieldValue.serverTimestamp()
        ])
        UsageStats.record(.rsvps)
    }

    func removeRSVP(sessionID: String) async throws {
        let uid = try await userID()
        try await sessionRef(sessionID).collection("rsvps").document(uid).delete()
    }

    /// The creator turns RSVPs on or off, or changes the reply-by time.
    func setRSVP(sessionID: String, asks: Bool, by date: Date?) async throws {
        _ = try await userID()
        let rsvpBy: Any
        if !asks { rsvpBy = FieldValue.delete() }
        else if let date { rsvpBy = Timestamp(date: date) }
        else { rsvpBy = NSNull() }
        try await sessionRef(sessionID).updateData([
            "asksRSVP": asks,
            "rsvpBy": rsvpBy,
            // A new reply-by time gets its own "RSVPs are closed" push.
            "rsvpClosedNotified": FieldValue.delete()
        ])
    }

    /// The creator moves an "I'll pick" plan to a different place.
    func changePlanPlace(sessionID: String, to place: Place, displayName: String) async throws {
        let uid = try await userID()
        let option = GroupOption(place: place, addedBy: displayName, addedByID: uid)
        try await sessionRef(sessionID).updateData([
            "options": [try Firestore.Encoder().encode(option)],
            "winnerID": option.id
        ])
    }

    // MARK: Owner actions

    /// Locks in the result. Votes: most votes wins, with a fair tie-break.
    /// Spin: a fair random pick among all options.
    /// Places someone in the group blacklisted (`ruledOut`) can't win.
    /// `announce: false` holds the "It's decided!" push until `announce(_:)`
    /// (a spin while its wheel plays, or iMessage until you tap Send).
    func decide(session: GroupSession, votes: [GroupVote], ruledOut: Set<String> = [],
                announce: Bool = true) async throws -> String? {
        let uid = try await userID()
        guard session.isOwned(by: uid) else { throw GroupError.notOwner }
        guard let winner = session.pickWinner(votes: votes, ruledOut: ruledOut) else { return nil }
        var update: [String: Any] = [
            "status": GroupStatus.decided.rawValue,
            "winnerID": winner,
            "announced": announce
        ]
        // When it was held: the server shares it anyway after 10 minutes.
        update["heldAt"] = announce ? FieldValue.delete() : FieldValue.serverTimestamp()
        // A time set days ago read "Tomorrow 7:00 PM"; the "It's decided!" push
        // uses this label, so make it right for today.
        if let meet = session.meetTime { update["meetTimeLabel"] = MeetTimes.label(for: meet) }
        try await sessionRef(session.id).updateData(update)
        return winner
    }

    /// Shares a held result: the server sends "It's decided!" now.
    func announce(sessionID: String) async throws {
        _ = try await userID()
        try await sessionRef(sessionID).updateData(["announced": true, "heldAt": FieldValue.delete()])
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
        // Reopening also clears the timer, so a vote whose time ran out isn't
        // stuck refusing every vote.
        try await sessionRef(session.id).updateData([
            "status": GroupStatus.open.rawValue,
            "winnerID": FieldValue.delete(),
            "closesAt": FieldValue.delete(),
            "announced": FieldValue.delete(),
            "heldAt": FieldValue.delete(),
            // A new round: "Everyone's in" and "closes soon" can go out again.
            "readyNotifiedFor": FieldValue.delete(),
            "closingNudged": FieldValue.delete()
        ])
    }

    /// A message people can act on, instead of Firebase's raw error text.
    nonisolated static func message(for error: Error) -> String {
        if let groupError = error as? GroupError, let text = groupError.errorDescription { return text }
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode.Code(rawValue: nsError.code) {
            case .permissionDenied:
                return "That didn’t go through. Voting may have closed, or the group changed. Pull down to refresh."
            case .unavailable, .deadlineExceeded:
                return "You’re offline. Check your connection and try again."
            case .notFound:
                return GroupError.sessionNotFound.errorDescription ?? "This group plan has ended."
            default: break
            }
        }
        return "Something went wrong. Try again in a moment."
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
        for name in ["votes", "rsvps", "eta", "devices", "members"] {
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
        try? await ref.collection("rsvps").document(uid).delete()
        try? await ref.collection("eta").document(uid).delete()
        // The server ends your Lock Screen countdown when this goes.
        try? await ref.collection("devices").document(uid).delete()
        try await ref.collection("members").document(uid).delete()
        // Voting again after leaving has to join again.
        joinedSessions.remove(sessionID)
        SharedCache.forgetSession(sessionID)
    }

    func setMeetTime(sessionID: String, date: Date) async throws {
        _ = try await userID()
        // The label ("7:00 PM") is formatted here because the server doesn't
        // know anyone's time zone; it's used in the "Meet at…" push.
        try await sessionRef(sessionID).updateData([
            "meetTime": Timestamp(date: date),
            "meetTimeLabel": MeetTimes.label(for: date)
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
