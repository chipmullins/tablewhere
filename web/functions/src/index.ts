/**
 * Tablewhere push notifications for group picks.
 *
 * Firestore layout (see web/firestore.rules and Shared/Group/GroupService.swift):
 *   sessions/{sessionId}                 the session (title, createdBy, status, options, winnerID, meetTime, meetTimeLabel)
 *   sessions/{sessionId}/members/{uid}   { id, name, joinedAt, fcmToken? }
 *   sessions/{sessionId}/votes/{uid}     { voterID, voterName, optionID, votedAt }
 *   sessions/{sessionId}/rsvps/{uid}     { userID, name, going, guests, answeredAt }  ("I'll pick" plans)
 *   sessions/{sessionId}/devices/{uid}   Lock Screen countdown settings + ActivityKit tokens (1.1, private)
 *   sessions/{sessionId}/eta/{uid}       "On my way": { name, eta, etaLabel, status, lateMinutes, lateNote } (1.1)
 *
 * Every handler catches its own errors: a failed push is logged, never retried or thrown.
 */
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type DocumentData, type DocumentSnapshot } from "firebase-admin/firestore";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { bumpStat } from "./stats";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";
import { APNS_KEY_ID, APNS_KEY_P8 } from "./apns";
import { arrivals, deleteArrivals, endAllNow, endFor, everyoneHere, expectedPeople, liveActivityTick, meetTimeChanged, planDeleted,
  updateAll } from "./liveActivities";

/** Functions that send Live Activity pushes need the APNs key. */
const apnsSecrets = [APNS_KEY_P8, APNS_KEY_ID];

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

initializeApp();
const db = getFirestore();

/** FCM accepts at most 500 tokens per multicast. */
const MULTICAST_LIMIT = 500;
/** Most places a group can hold (GroupSession.maxOptions in the app). */
const MAX_OPTIONS = 12;

/** Error codes meaning the token will never work again. */
const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

// MARK: - Data helpers

interface Recipient {
  uid: string;
  token: string;
}

interface SessionOption {
  id?: string;
  name?: string;
  addedBy?: string;
  addedByID?: string;
}

function optionsOf(session: DocumentData): SessionOption[] {
  const options: unknown = session.options;
  return Array.isArray(options) ? (options as SessionOption[]).filter((o) => o && typeof o.id === "string") : [];
}

function str(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function optionName(session: DocumentData, optionID: unknown): string | undefined {
  if (typeof optionID !== "string") return undefined;
  const options: unknown = session.options;
  if (!Array.isArray(options)) return undefined;
  const match = (options as SessionOption[]).find((o) => o && o.id === optionID);
  return str(match?.name);
}

function sessionTitle(session: DocumentData): string {
  return str(session.title) ?? "Tablewhere";
}

/** Members with a push token, optionally limited to some uids or excluding some. */
async function recipients(
  sessionId: string,
  filter: { only?: string[]; except?: string[] },
): Promise<Recipient[]> {
  const membersRef = db.collection("sessions").doc(sessionId).collection("members");
  let docs: DocumentSnapshot[];
  if (filter.only) {
    if (filter.only.length === 0) return [];
    docs = await Promise.all(filter.only.map((uid) => membersRef.doc(uid).get()));
  } else {
    docs = (await membersRef.get()).docs;
  }
  const except = new Set(filter.except ?? []);
  const seen = new Set<string>();
  const out: Recipient[] = [];
  for (const doc of docs) {
    if (!doc.exists || except.has(doc.id)) continue;
    const token = str(doc.get("fcmToken"));
    if (!token || seen.has(token)) continue;
    seen.add(token);
    out.push({ uid: doc.id, token });
  }
  return out;
}

// MARK: - Sending

interface SendOptions {
  /** Same key = the new push replaces the last one (apns-collapse-id). */
  collapse?: string;
  /** No sound or screen wake (iOS passive interruption level). */
  quiet?: boolean;
}

async function send(
  sessionId: string,
  to: Recipient[],
  title: string,
  body: string,
  opts: SendOptions = {},
): Promise<void> {
  if (to.length === 0) return;
  // Running updates (picks added, RSVPs) replace the previous one on the
  // lock screen instead of piling up, and arrive quietly (no sound or screen
  // wake). Milestones ("Everyone's in", "It's decided!") stay normal.
  const aps: Record<string, unknown> = { "thread-id": `session-${sessionId}` };
  if (opts.quiet) aps["interruption-level"] = "passive";
  else aps.sound = "default";
  for (let i = 0; i < to.length; i += MULTICAST_LIMIT) {
    const chunk = to.slice(i, i + MULTICAST_LIMIT);
    const message: MulticastMessage = {
      tokens: chunk.map((r) => r.token),
      notification: { title, body },
      data: { sessionId },
      apns: {
        ...(opts.collapse ? { headers: { "apns-collapse-id": `${opts.collapse}-${sessionId}`.slice(0, 64) } } : {}),
        payload: { aps },
      },
    };
    try {
      const result = await getMessaging().sendEachForMulticast(message);
      const dead: Recipient[] = [];
      result.responses.forEach((res, idx) => {
        if (res.success) return;
        const code = res.error?.code ?? "unknown";
        if (DEAD_TOKEN_CODES.has(code)) {
          dead.push(chunk[idx]);
        } else {
          logger.warn("Push failed", { sessionId, uid: chunk[idx].uid, code });
        }
      });
      if (dead.length > 0) await removeTokens(sessionId, dead);
      logger.info("Push sent", {
        sessionId,
        success: result.successCount,
        failure: result.failureCount,
        removed: dead.length,
      });
    } catch (err) {
      logger.error("sendEachForMulticast threw", { sessionId, err });
    }
  }
}

/** Deletes `fcmToken` from member docs, but only if it still holds the dead token. */
async function removeTokens(sessionId: string, dead: Recipient[]): Promise<void> {
  const membersRef = db.collection("sessions").doc(sessionId).collection("members");
  await Promise.all(
    dead.map(async ({ uid, token }) => {
      try {
        await db.runTransaction(async (tx) => {
          const ref = membersRef.doc(uid);
          const snap = await tx.get(ref);
          if (snap.exists && snap.get("fcmToken") === token) {
            tx.update(ref, { fcmToken: FieldValue.delete() });
          }
        });
      } catch (err) {
        logger.warn("Could not remove dead token", { sessionId, uid, err });
      }
    }),
  );
}

// MARK: - "Everyone's in" → the session creator

/**
 * Whether everyone (besides the creator) has done their part: voted, or (in a
 * spin) added their pick. `others` is how many people that is. When the
 * creator said how many are eating (`expectedCount`, counting them, or the
 * iMessage chat's size), it waits for that many even if some haven't opened
 * the link yet; more joins than expected count too. This only decides the
 * "everyone's in" push: it never stops the creator from spinning or locking in.
 */
async function everyoneIsIn(sessionId: string, session: DocumentData): Promise<{ ready: boolean; others: number }> {
  const creator = str(session.createdBy);
  const ref = db.collection("sessions").doc(sessionId);
  const members = (await ref.collection("members").get()).docs.map((d) => d.id).filter((id) => id !== creator);
  const expected = typeof session.expectedCount === "number" && Number.isFinite(session.expectedCount)
    ? Math.max(0, Math.floor(session.expectedCount) - 1) : 0;
  const others = Math.max(members.length, expected);
  if (members.length === 0) return { ready: false, others };
  let done: Set<string>;
  // "Surprise us": the wheel is places nearby; nobody adds a pick.
  if (session.surprise === true) return { ready: false, others: members.length };
  if (session.mode === "spin") {
    // A full wheel (12 places) can't take more picks: nobody is left to wait on.
    if (optionsOf(session).length >= MAX_OPTIONS) return { ready: true, others: members.length };
    const picks = session.picksBy && typeof session.picksBy === "object" ? Object.keys(session.picksBy) : [];
    done = new Set([...picks, ...optionsOf(session).map((o) => o.addedByID ?? "")]);
  } else {
    done = new Set((await ref.collection("votes").get()).docs.map((d) => d.id));
  }
  return { ready: members.length >= expected && members.every((id) => done.has(id)), others };
}

/**
 * Claims the "everyone's in" push for this many people, once. If more people
 * join later and they're all in again, it can go out again.
 */
async function claimReady(sessionId: string, others: number): Promise<boolean> {
  const ref = db.collection("sessions").doc(sessionId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.get("status") !== "open") return false;
    const sentFor = snap.get("readyNotifiedFor");
    if (typeof sentFor === "number" && sentFor >= others) return false;
    tx.update(ref, { readyNotifiedFor: others });
    return true;
  });
}

/** Votes no longer push one by one: the creator hears once, when everyone has voted. */
async function notifyCreatorIfEveryoneVoted(sessionId: string, voterUid: string): Promise<void> {
  const session = (await db.collection("sessions").doc(sessionId).get()).data();
  if (!session || session.status !== "open" || session.mode === "spin") return;
  const creator = str(session.createdBy);
  if (!creator || creator === voterUid) return;

  const { ready, others } = await everyoneIsIn(sessionId, session);
  if (!ready || !(await claimReady(sessionId, others))) return;
  const to = await recipients(sessionId, { only: [creator] });
  const who = others === 1 ? "They've" : `All ${others} have`;
  await send(sessionId, to, "Everyone's voted", `${who} voted on ${sessionTitle(session)}. Tap to lock it in.`);
}

export const onVoteCreated = onDocumentCreated(
  "sessions/{sessionId}/votes/{uid}",
  async (event) => {
    try {
      const vote = event.data?.data();
      if (!vote) return;
      await notifyCreatorIfEveryoneVoted(event.params.sessionId, event.params.uid);
    } catch (err) {
      logger.error("onVoteCreated failed", { params: event.params, err });
    }
  },
);

export const onVoteUpdated = onDocumentUpdated(
  "sessions/{sessionId}/votes/{uid}",
  async (event) => {
    try {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      if (!before || !after || before.optionID === after.optionID) return;
      await notifyCreatorIfEveryoneVoted(event.params.sessionId, event.params.uid);
    } catch (err) {
      logger.error("onVoteUpdated failed", { params: event.params, err });
    }
  },
);

// MARK: - Places added → the session creator

/**
 * Someone added a place (a Group Spin pick, or a suggestion in a vote), or
 * swapped theirs. Tells the creator, so they know when the wheel's ready.
 * Places the creator added themselves are skipped.
 */
async function notifyCreatorOfNewPlaces(sessionId: string, before: DocumentData, after: DocumentData): Promise<void> {
  const creator = str(after.createdBy);
  if (!creator) return;
  const oldOptions = optionsOf(before);
  const oldIDs = new Set(oldOptions.map((o) => o.id));
  const added = optionsOf(after).filter((o) => !oldIDs.has(o.id) && o.addedByID !== creator);
  if (added.length === 0) return;

  const to = await recipients(sessionId, { only: [creator] });
  if (to.length === 0) return;

  const isSpin = after.mode === "spin";
  const total = optionsOf(after).length;
  let tally = isSpin ? `${total} on the wheel` : `${total} places in the vote`;
  // The last pick of a spin: say it's time, once.
  let title = sessionTitle(after);
  if (isSpin) {
    const { ready, others } = await everyoneIsIn(sessionId, after);
    if (ready && (await claimReady(sessionId, others))) {
      tally = "everyone's in. Time to spin!";
      title = "Everyone's in";
    }
  }
  for (const option of added) {
    const who = str(option.addedBy) ?? "Someone";
    const place = str(option.name) ?? "a place";
    // Their earlier place is gone: they changed their pick.
    const swapped = !!option.addedByID && oldOptions.some((o) =>
      o.addedByID === option.addedByID && !optionsOf(after).some((n) => n.id === o.id));
    const body = swapped
      ? `${who} changed their pick to ${place} · ${tally}`
      : isSpin
        ? `${who} added ${place} to the wheel · ${tally}`
        : `${who} suggested ${place} · ${tally}`;
    const milestone = title === "Everyone's in";
    await send(sessionId, to, title, body, { collapse: "places", quiet: !milestone });
  }
}

// MARK: - Stats: groups that became real plans

/**
 * A decided plan with a meet time counts once ("Plans with a time" on the
 * stats page), however it got there: decided then timed, timed then decided,
 * or an "I'll pick" plan created with both. `planCountedAt` keeps it to once.
 */
async function countPlan(ref: FirebaseFirestore.DocumentReference, data: DocumentData): Promise<void> {
  if (data.status !== "decided" || !(data.meetTime instanceof Timestamp) || data.planCountedAt) return;
  try {
    const claimed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists || snap.get("planCountedAt")) return false;
      tx.update(ref, { planCountedAt: Timestamp.now() });
      return true;
    });
    if (claimed) await bumpStat("plansWithTime");
  } catch (err) {
    logger.warn("countPlan failed", { sessionId: ref.id, err: String(err) });
  }
}

export const onSessionCreated = onDocumentCreated("sessions/{sessionId}", async (event) => {
  const data = event.data?.data();
  if (data && event.data) await countPlan(event.data.ref, data);
});

// MARK: - Session decided / meeting time → everyone but the creator

export const onSessionUpdated = onDocumentUpdated({ document: "sessions/{sessionId}", secrets: apnsSecrets }, async (event) => {
  try {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const sessionId = event.params.sessionId;
    await liveActivityChanges(event.data!.after.ref, before, after);
    await countPlan(event.data!.after.ref, after);
    const creator = str(after.createdBy);
    const except = creator ? [creator] : [];

    // 0. A place was added while it's still open.
    if (before.status === "open" && after.status === "open") {
      await notifyCreatorOfNewPlaces(sessionId, before, after);
      return;
    }

    const winner = optionName(after, after.winnerID) ?? "the winning pick";
    const label = str(after.meetTimeLabel);

    // 1. Just shared: locked in (older apps), or a held result going out
    //    (after the spin's reveal, or when the creator taps Send in iMessage).
    //    `announced === false` means the creator hasn't shared it yet.
    const nowDecided = before.status !== "decided" && after.status === "decided";
    const released = before.status === "decided" && after.status === "decided"
      && before.announced === false && after.announced === true;
    if ((nowDecided && after.announced !== false) || released) {
      const to = await recipients(sessionId, { except });
      const body = `We're going to ${winner}` + (label ? ` · ${label}` : "");
      await send(sessionId, to, "It's decided!", body);
      return;
    }

    // 2. Meeting time changed while decided. The label is what people read, and the
    //    app writes it with meetTime, so notify when the label changes to a new value.
    //    (A bare meetTime write with no label is skipped, so nobody gets a push twice.)
    if (before.status === "decided" && after.status === "decided") {
      // Still held (the creator is setting the time before sending): the
      // group hears it all at once when it's shared.
      if (after.announced === false) return;
      // An "I'll pick" plan moved to a different place.
      if (before.winnerID !== after.winnerID && after.winnerID) {
        const to = await recipients(sessionId, { except });
        const when = label ? ` · ${label}` : "";
        await send(sessionId, to, "Change of plans", `We're going to ${winner} instead${when}`);
        return;
      }
      if (!label || before.meetTimeLabel === after.meetTimeLabel) return;
      const to = await recipients(sessionId, { except });
      await send(sessionId, to, sessionTitle(after), `Meet: ${label} · ${winner}`);
    }
  } catch (err) {
    logger.error("onSessionUpdated failed", { params: event.params, err });
  }
});

/**
 * Lock Screen countdowns follow the plan: reopened or moved to another place
 * → they all go now (and start fresh when it's decided again); a new meet
 * time → the ones already up follow it.
 */
async function liveActivityChanges(ref: FirebaseFirestore.DocumentReference, before: DocumentData, after: DocumentData) {
  try {
    if (before.status !== "decided") return;
    if (after.status !== "decided" || (after.winnerID && before.winnerID !== after.winnerID)) {
      await endAllNow(ref);
      // Old "On my way" times don't carry over to a reopened plan or a new place.
      // (The deletes trigger onETAWritten, which sends nothing: no push for a
      // removed time, and every countdown was just ended.)
      await deleteArrivals(ref);
      // A new place (or decided again later) is a new night: "Everyone's here" can happen again.
      if (after.everyoneHereAt) await ref.update({ everyoneHereAt: FieldValue.delete() });
      return;
    }
    const oldMeet = before.meetTime instanceof Timestamp ? before.meetTime.toMillis() : undefined;
    const newMeet = after.meetTime instanceof Timestamp ? after.meetTime.toMillis() : undefined;
    if (oldMeet !== undefined && newMeet !== undefined && oldMeet !== newMeet) {
      await meetTimeChanged(ref, oldMeet, newMeet);
      if (after.everyoneHereAt) await ref.update({ everyoneHereAt: FieldValue.delete() });
    }
    if (oldMeet !== undefined && newMeet === undefined) await endAllNow(ref);
  } catch (err) {
    logger.error("liveActivityChanges failed", { sessionId: ref.id, err: String(err) });
  }
}

/** The plan was ended: everyone's countdown goes now, and their private device docs too. */
export const onSessionDeleted = onDocumentDeleted(
  { document: "sessions/{sessionId}", secrets: apnsSecrets },
  async (event) => {
    try {
      await planDeleted(db.collection("sessions").doc(event.params.sessionId));
    } catch (err) {
      logger.error("onSessionDeleted failed", { params: event.params, err: String(err) });
    }
  },
);

/** You left the plan (or it ended): your countdown goes now. */
export const onDeviceDeleted = onDocumentDeleted(
  { document: "sessions/{sessionId}/devices/{uid}", secrets: apnsSecrets },
  async (event) => {
    try {
      const d = event.data?.data();
      if (!d || typeof d.updateToken !== "string") return;
      const started = d.laStartedFor ?? (d.activityMeet instanceof Timestamp ? d.activityMeet.toMillis() : undefined);
      if (started === undefined || d.laEndedFor === started) return;
      await endFor(event.params.sessionId, event.data!.ref, d, undefined, Date.now());
    } catch (err) {
      logger.error("onDeviceDeleted failed", { params: event.params, err: String(err) });
    }
  },
);

// MARK: - "On my way" (1.1): arrival times, never locations

const ETA_PUSH_MIN_CHANGE_MS = 3 * 60 * 1000;

function etaText(eta: DocumentData): string | undefined {
  const label = str(eta.etaLabel);
  if (label) return label;
  const at = eta.eta instanceof Timestamp ? eta.eta.toMillis() : undefined;
  if (at === undefined) return undefined;
  const minutes = Math.max(1, Math.round((at - Date.now()) / 60000));
  return `${minutes} min away`;
}

/**
 * Someone tapped "I'm on my way", is running late, arrived, or their ETA
 * moved. Everyone else hears (sound for on the way / late / arrived, quiet
 * for a new ETA, one notification per person), and their Lock Screen
 * countdowns show it. Arriving takes your own countdown down if you chose
 * "When I arrive".
 */
export const onETAWritten = onDocumentWritten(
  { document: "sessions/{sessionId}/eta/{uid}", secrets: apnsSecrets },
  async (event) => {
    try {
      const { sessionId, uid } = event.params;
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      const sessionRef = db.collection("sessions").doc(sessionId);
      const session = (await sessionRef.get()).data();
      if (!session || session.status !== "decided") return;
      const meet = session.meetTime instanceof Timestamp ? session.meetTime.toMillis() : undefined;

      const statusChanged = !before || !after || before.status !== after.status;
      // The last one in: "Everyone's here" replaces "Sam arrived".
      const allHereNow = after?.status === "arrived" && statusChanged && !session.everyoneHereAt
        && await isEveryoneHere(sessionRef);
      if (after && !allHereNow) {
        const who = str(after.name) ?? "Someone";
        const when = etaText(after);
        let body: string | undefined;
        let quiet = false;
        if (after.status === "arrived") {
          if (statusChanged) body = `${who} arrived`;
        } else if (after.status === "late") {
          const lateChanged = statusChanged || before?.lateMinutes !== after.lateMinutes || before?.lateNote !== after.lateNote;
          if (lateChanged) {
            body = after.lateNote === "text" ? `${who} is running late and will text you`
              : typeof after.lateMinutes === "number" ? `${who} is running ~${after.lateMinutes} min late`
              : `${who} is running late`;
          }
        } else if (statusChanged) {
          body = `${who} is on the way` + (when ? ` · about ${when}` : "");
        } else {
          const oldAt = before?.eta instanceof Timestamp ? before.eta.toMillis() : 0;
          const newAt = after.eta instanceof Timestamp ? after.eta.toMillis() : 0;
          if (Math.abs(newAt - oldAt) >= ETA_PUSH_MIN_CHANGE_MS && when) {
            body = `${who} · now about ${when}`;
            quiet = true;
          }
        }
        if (body) {
          const to = await recipients(sessionId, { except: [uid] });
          await send(sessionId, to, sessionTitle(session), body, { collapse: `eta-${uid}`, quiet });
        }
      }

      // Everyone's here (2+ people expected, all arrived): one "Enjoy!" push
      // to everyone, and the countdowns end with "All 4 here ✓". Once per plan.
      if (allHereNow) {
        const claimed = await db.runTransaction(async (tx) => {
          const snap = await tx.get(sessionRef);
          if (!snap.exists || snap.get("everyoneHereAt")) return false;
          tx.update(sessionRef, { everyoneHereAt: Timestamp.now() });
          return true;
        });
        if (claimed) {
          const place = winnerName(session);
          const to = await recipients(sessionId, { except: [] });
          await send(sessionId, to, sessionTitle(session), `Everyone’s here. Enjoy ${place}!`, { collapse: "everyone-here" });
          await bumpStat("everyoneHere");
          if (meet !== undefined) await everyoneHere(sessionRef, meet, await expectedPeople(sessionRef));
          return;
        }
      }

      if (meet !== undefined) {
        await updateAll(sessionRef, meet, { quiet: !statusChanged, except: uid });
        // Arrived, with "Remove from Lock Screen: When I arrive": your own countdown goes.
        if (after?.status === "arrived" && statusChanged) {
          const device = await sessionRef.collection("devices").doc(uid).get();
          const d = device.data();
          if (d && d.removeWhen === "arrive") await endFor(sessionId, device.ref, d, meet, Date.now());
        }
      }
    } catch (err) {
      logger.error("onETAWritten failed", { params: event.params, err: String(err) });
    }
  },
);

async function isEveryoneHere(sessionRef: FirebaseFirestore.DocumentReference): Promise<boolean> {
  const [expected, all] = await Promise.all([expectedPeople(sessionRef), arrivals(sessionRef)]);
  if (expected.length < 2) return false;
  const here = new Set(all.filter((a) => a.status === "arrived").map((a) => a.uid));
  return expected.every((id) => here.has(id));
}

function winnerName(session: DocumentData): string {
  const options: unknown = session.options;
  if (Array.isArray(options)) {
    const match = options.find((o) => o && o.id === session.winnerID);
    if (match && typeof match.name === "string" && match.name.trim()) return match.name.trim();
  }
  return "your table";
}

// MARK: - Timed votes: a last call for whoever hasn't voted

/**
 * About two minutes before a timed vote closes, nudge members who haven't
 * voted (not the creator). Once per vote.
 */
export const voteClosingSoon = onSchedule("every 1 minutes", async () => {
  try {
    const now = Date.now();
    const due = await db.collection("sessions")
      .where("closesAt", ">", Timestamp.fromMillis(now + 60 * 1000))
      .where("closesAt", "<=", Timestamp.fromMillis(now + 3 * 60 * 1000))
      .get();
    for (const doc of due.docs) {
      const session = doc.data();
      if (session.status !== "open" || session.mode === "spin" || session.closingNudged === true) continue;
      const claimed = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists || fresh.get("closingNudged") === true) return false;
        tx.update(doc.ref, { closingNudged: true });
        return true;
      });
      if (!claimed) continue;
      const voted = (await doc.ref.collection("votes").get()).docs.map((d) => d.id);
      const creator = str(session.createdBy);
      const to = await recipients(doc.id, { except: [...voted, ...(creator ? [creator] : [])] });
      await send(doc.id, to, "Voting closes in 2 minutes", `Pick your spot for ${sessionTitle(session)} before it's locked in.`);
    }
  } catch (err) {
    logger.error("voteClosingSoon failed", { err });
  }
});

// MARK: - Held results nobody sent

/** How long a creator can sit on a result before it's shared for them. */
const HOLD_LIMIT_MS = 10 * 60 * 1000;

/**
 * Every 5 minutes: Lock Screen countdowns (start / end, see liveActivities.ts),
 * then held results.
 *
 * A result the creator held (iMessage: "Send to the group") but never sent.
 * After 10 minutes, share it: setting `announced` fires the usual
 * "It's decided!" push to everyone (onSessionUpdated), and the creator is
 * told why. The iMessage bubble can only be updated by the creator's tap.
 */
export const releaseHeldResults = onSchedule({ schedule: "every 5 minutes", secrets: apnsSecrets }, async () => {
  // Also runs the Lock Screen countdowns (1.1), so there are still three
  // scheduled jobs (Cloud Scheduler charges per job past three).
  try {
    await liveActivityTick();
  } catch (err) {
    logger.error("liveActivityTick failed", { err: String(err) });
  }
  try {
    const cutoff = Timestamp.fromMillis(Date.now() - HOLD_LIMIT_MS);
    const dayAgo = Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
    const due = await db.collection("sessions")
      .where("heldAt", ">", dayAgo)
      .where("heldAt", "<=", cutoff)
      .get();
    for (const doc of due.docs) {
      const released = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists || fresh.get("status") !== "decided" || fresh.get("announced") !== false) return false;
        tx.update(doc.ref, { announced: true, heldAt: FieldValue.delete() });
        return true;
      });
      if (!released) continue;
      const session = doc.data();
      const creator = str(session.createdBy);
      if (!creator) continue;
      const to = await recipients(doc.id, { only: [creator] });
      await send(doc.id, to, sessionTitle(session),
        "We shared the result with the group for you. Open the plan in Messages to send it there with a time.");
    }
  } catch (err) {
    logger.error("releaseHeldResults failed", { err });
  }
});

// MARK: - RSVPs ("I'll pick" plans) → the creator

interface Headcount {
  people: number;
  guests: number;
  cant: number;
}

/** The creator counts as coming unless they said otherwise (same as the app). */
async function headcount(sessionId: string, creator: string | undefined): Promise<Headcount> {
  const snap = await db.collection("sessions").doc(sessionId).collection("rsvps").get();
  let people = 0, guests = 0, cant = 0, creatorAnswered = false;
  for (const doc of snap.docs) {
    const r = doc.data();
    if (doc.id === creator) creatorAnswered = true;
    if (r.going === true) {
      people += 1;
      guests += typeof r.guests === "number" ? Math.max(0, Math.min(4, r.guests)) : 0;
    } else {
      cant += 1;
    }
  }
  if (creator && !creatorAnswered) people += 1;
  return { people, guests, cant };
}

function headcountText(c: Headcount): string {
  let text = `${c.people + c.guests} coming`;
  if (c.guests > 0) text += ` (${c.people} + ${c.guests} guest${c.guests === 1 ? "" : "s"})`;
  if (c.cant > 0) text += ` · ${c.cant} can't make it`;
  return text;
}

export const onRSVPWritten = onDocumentWritten(
  "sessions/{sessionId}/rsvps/{uid}",
  async (event) => {
    try {
      const after = event.data?.after.data();
      if (!after) return;  // taken back: no push
      const before = event.data?.before.data();
      // First answer, or in ↔ out. Guest +/- taps don't each send a push.
      if (before && before.going === after.going) return;

      const sessionId = event.params.sessionId;
      const session = (await db.collection("sessions").doc(sessionId).get()).data();
      if (!session) return;
      const creator = str(session.createdBy);
      if (!creator || creator === event.params.uid) return;
      const to = await recipients(sessionId, { only: [creator] });
      if (to.length === 0) return;

      const who = str(after.name) ?? "Someone";
      const guests = typeof after.guests === "number" && after.guests > 0 ? ` (+${after.guests})` : "";
      const what = after.going === true ? `${who}'s in${guests}` : `${who} can't make it`;
      const count = headcountText(await headcount(sessionId, creator));
      await send(sessionId, to, sessionTitle(session), `${what} · ${count}`, { collapse: "rsvp", quiet: true });
    } catch (err) {
      logger.error("onRSVPWritten failed", { params: event.params, err });
    }
  },
);

/**
 * When a plan's reply-by time passes, tell the creator the final headcount
 * (once). Runs every 15 minutes and looks back a day, so a slow run still
 * catches it. A single-field range query, so no extra index is needed.
 */
export const closeRSVPs = onSchedule("every 15 minutes", async () => {
  try {
    const now = Timestamp.now();
    const dayAgo = Timestamp.fromMillis(now.toMillis() - 24 * 60 * 60 * 1000);
    const due = await db.collection("sessions")
      .where("rsvpBy", ">", dayAgo)
      .where("rsvpBy", "<=", now)
      .get();
    for (const doc of due.docs) {
      const session = doc.data();
      if (session.asksRSVP !== true || session.rsvpClosedNotified === true) continue;
      // Mark first, so two runs never both send it.
      const claimed = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists || fresh.get("rsvpClosedNotified") === true) return false;
        tx.update(doc.ref, { rsvpClosedNotified: true });
        return true;
      });
      if (!claimed) continue;
      const creator = str(session.createdBy);
      if (!creator) continue;
      const to = await recipients(doc.id, { only: [creator] });
      const count = headcountText(await headcount(doc.id, creator));
      await send(doc.id, to, "RSVPs are closed", `${sessionTitle(session)}: ${count}`);
    }
  } catch (err) {
    logger.error("closeRSVPs failed", { err });
  }
});
