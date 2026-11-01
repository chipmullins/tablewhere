/**
 * ForkRoad push notifications for group picks.
 *
 * Firestore layout (see web/firestore.rules and Shared/Group/GroupService.swift):
 *   sessions/{sessionId}                 the session (title, createdBy, status, options, winnerID, meetTime, meetTimeLabel)
 *   sessions/{sessionId}/members/{uid}   { id, name, joinedAt, fcmToken? }
 *   sessions/{sessionId}/votes/{uid}     { voterID, voterName, optionID, votedAt }
 *   sessions/{sessionId}/rsvps/{uid}     { userID, name, going, guests, answeredAt }  ("I'll pick" plans)
 *
 * Every handler catches its own errors: a failed push is logged, never retried or thrown.
 */
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type DocumentData, type DocumentSnapshot } from "firebase-admin/firestore";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

initializeApp();
const db = getFirestore();

/** FCM accepts at most 500 tokens per multicast. */
const MULTICAST_LIMIT = 500;

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
  return str(session.title) ?? "ForkRoad";
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

async function counts(sessionId: string): Promise<{ votes: number; members: number }> {
  const ref = db.collection("sessions").doc(sessionId);
  const [votes, members] = await Promise.all([
    ref.collection("votes").count().get(),
    ref.collection("members").count().get(),
  ]);
  return { votes: votes.data().count, members: members.data().count };
}

// MARK: - Sending

async function send(
  sessionId: string,
  to: Recipient[],
  title: string,
  body: string,
): Promise<void> {
  if (to.length === 0) return;
  for (let i = 0; i < to.length; i += MULTICAST_LIMIT) {
    const chunk = to.slice(i, i + MULTICAST_LIMIT);
    const message: MulticastMessage = {
      tokens: chunk.map((r) => r.token),
      notification: { title, body },
      data: { sessionId },
      apns: {
        payload: { aps: { sound: "default", "thread-id": `session-${sessionId}` } },
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

// MARK: - Votes → the session creator

async function notifyCreatorOfVote(
  sessionId: string,
  voterUid: string,
  vote: DocumentData,
  changed: boolean,
): Promise<void> {
  const sessionSnap = await db.collection("sessions").doc(sessionId).get();
  const session = sessionSnap.data();
  if (!session) return;
  const creator = str(session.createdBy);
  if (!creator || creator === voterUid || creator === vote.voterID) return;

  const to = await recipients(sessionId, { only: [creator] });
  if (to.length === 0) return;

  const voter = str(vote.voterName) ?? "Someone";
  const place = optionName(session, vote.optionID) ?? "a place";
  const { votes, members } = await counts(sessionId);
  const tally = `${votes} of ${Math.max(members, votes)} voted`;
  const body = changed
    ? `${voter} changed their vote to ${place} · ${tally}`
    : `${voter} voted for ${place} · ${tally}`;
  await send(sessionId, to, sessionTitle(session), body);
}

export const onVoteCreated = onDocumentCreated(
  "sessions/{sessionId}/votes/{uid}",
  async (event) => {
    try {
      const vote = event.data?.data();
      if (!vote) return;
      await notifyCreatorOfVote(event.params.sessionId, event.params.uid, vote, false);
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
      await notifyCreatorOfVote(event.params.sessionId, event.params.uid, after, true);
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
  const tally = isSpin ? `${total} on the wheel` : `${total} places in the vote`;
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
    await send(sessionId, to, sessionTitle(after), body);
  }
}

// MARK: - Session decided / meeting time → everyone but the creator

export const onSessionUpdated = onDocumentUpdated("sessions/{sessionId}", async (event) => {
  try {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const sessionId = event.params.sessionId;
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

// MARK: - Held results nobody sent

/** How long a creator can sit on a result before it's shared for them. */
const HOLD_LIMIT_MS = 10 * 60 * 1000;

/**
 * A result the creator held (iMessage: "Send to the group") but never sent.
 * After 10 minutes, share it: setting `announced` fires the usual
 * "It's decided!" push to everyone (onSessionUpdated), and the creator is
 * told why. The iMessage bubble can only be updated by the creator's tap.
 */
export const releaseHeldResults = onSchedule("every 5 minutes", async () => {
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
      await send(sessionId, to, sessionTitle(session), `${what} · ${count}`);
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
