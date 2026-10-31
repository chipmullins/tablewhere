/**
 * ForkRoad push notifications for group picks.
 *
 * Firestore layout (see web/firestore.rules and Shared/Group/GroupService.swift):
 *   sessions/{sessionId}                 the session (title, createdBy, status, options, winnerID, meetTime, meetTimeLabel)
 *   sessions/{sessionId}/members/{uid}   { id, name, joinedAt, fcmToken? }
 *   sessions/{sessionId}/votes/{uid}     { voterID, voterName, optionID, votedAt }
 *
 * Every handler catches its own errors: a failed push is logged, never retried or thrown.
 */
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, type DocumentData, type DocumentSnapshot } from "firebase-admin/firestore";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";

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

// MARK: - Session decided / meeting time → everyone but the creator

export const onSessionUpdated = onDocumentUpdated("sessions/{sessionId}", async (event) => {
  try {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const sessionId = event.params.sessionId;
    const creator = str(after.createdBy);
    const except = creator ? [creator] : [];

    const winner = optionName(after, after.winnerID) ?? "the winning pick";
    const label = str(after.meetTimeLabel);

    // 1. Just locked in.
    if (before.status !== "decided" && after.status === "decided") {
      const to = await recipients(sessionId, { except });
      const body = `We're going to ${winner}` + (label ? ` · ${label}` : "");
      await send(sessionId, to, "It's decided!", body);
      return;
    }

    // 2. Meeting time changed while decided. The label is what people read, and the
    //    app writes it with meetTime, so notify when the label changes to a new value.
    //    (A bare meetTime write with no label is skipped, so nobody gets a push twice.)
    if (before.status === "decided" && after.status === "decided") {
      if (!label || before.meetTimeLabel === after.meetTimeLabel) return;
      const to = await recipients(sessionId, { except });
      await send(sessionId, to, sessionTitle(after), `Meet: ${label} · ${winner}`);
    }
  } catch (err) {
    logger.error("onSessionUpdated failed", { params: event.params, err });
  }
});
